import 'package:yazan_offline_sync/yazan_offline_sync.dart';

/// In-memory stand-in for the SQLite driver. It understands exactly the statements in [OutboxSql]
/// and [FeedSql] (matched by their text) plus a no-op for any DDL, and it mimics the two driver
/// behaviours the stores depend on:
///
/// * transactions are atomic (a throw rolls back rows, cursors AND `user_version`);
/// * using the outer database while a transaction is open is an error (real drivers deadlock).
///
/// It checks the store LOGIC (ordering, isolation, wipe, atomicity, state persistence). It does not
/// prove the SQL text is valid SQLite; that needs a real engine (see the package README).
class FakeSqlDatabase implements SqlDatabase {
  _Data _data = _Data();
  bool _inTxn = false;
  bool closed = false;

  /// Statements that are not data operations (DDL, test-only SQL).
  int otherStatements = 0;

  /// Every statement executed, in order (including those inside transactions).
  final List<String> log = [];

  /// Statements whose exact text is in this set throw when executed.
  final Set<String> failOn = {};

  List<Map<String, Object?>> get outboxRows => _data.outbox;
  int get version => _data.version;
  set version(int v) => _data.version = v;
  int get feedRowCount => _data.feedRows.length;
  int get cursorCount => _data.cursors.length;

  late final SqlExecutor _outer = _FakeExecutor(this, isTxn: false);

  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) => _outer.execute(sql, args);

  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?> args = const []]) =>
      _outer.query(sql, args);

  @override
  Future<int> userVersion() => _outer.userVersion();

  @override
  Future<void> setUserVersion(int version) => _outer.setUserVersion(version);

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor txn) action) async {
    if (_inTxn) throw StateError('nested transaction');
    final snapshot = _data.copy();
    _inTxn = true;
    try {
      return await action(_FakeExecutor(this, isTxn: true));
    } on Object {
      _data = snapshot;
      rethrow;
    } finally {
      _inTxn = false;
    }
  }

  @override
  Future<void> close() async => closed = true;
}

class _Data {
  int version = 0;
  int seq = 0;
  List<Map<String, Object?>> outbox = [];
  Map<String, Map<String, Object?>> feedRows = {};
  Map<String, String> cursors = {};

  _Data copy() => _Data()
    ..version = version
    ..seq = seq
    ..outbox = [for (final r in outbox) Map<String, Object?>.from(r)]
    ..feedRows = {for (final e in feedRows.entries) e.key: Map<String, Object?>.from(e.value)}
    ..cursors = Map<String, String>.from(cursors);
}

class _FakeExecutor implements SqlExecutor {
  _FakeExecutor(this._db, {required this.isTxn});

  final FakeSqlDatabase _db;
  final bool isTxn;

  _Data get _d => _db._data;

  void _guard(String sql) {
    if (_db.closed) throw StateError('database is closed');
    if (_db._inTxn && !isTxn) {
      throw StateError('outer database used inside a transaction: $sql');
    }
    _db.log.add(sql);
    if (_db.failOn.contains(sql)) throw StateError('forced failure: $sql');
  }

  @override
  Future<int> userVersion() async => _d.version;

  @override
  Future<void> setUserVersion(int version) async {
    if (_db._inTxn && !isTxn) throw StateError('outer database used inside a transaction');
    _d.version = version;
  }

  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) async {
    _guard(sql);
    switch (sql) {
      case OutboxSql.insert:
        if (_d.outbox.any((r) => r['id'] == args[0])) return; // INSERT OR IGNORE
        _d.outbox.add({
          'seq': ++_d.seq,
          'id': args[0],
          'account_id': args[1],
          'kind': args[2],
          'entity': args[3],
          'method': args[4],
          'path': args[5],
          'idempotency_key': args[6],
          'body': args[7],
          'base_version': args[8],
          'state': args[9],
          'attempts': args[10],
          'next_attempt_at': args[11],
          'last_error': args[12],
          'server_version': args[13],
          'created_at': args[14],
        });
      case OutboxSql.update:
        for (final r in _d.outbox.where((r) => r['id'] == args[5])) {
          r['state'] = args[0];
          r['attempts'] = args[1];
          r['next_attempt_at'] = args[2];
          r['last_error'] = args[3];
          r['server_version'] = args[4];
        }
      case OutboxSql.remove:
        _d.outbox.removeWhere((r) => r['id'] == args[0]);
      case OutboxSql.deleteAccount:
        _d.outbox.removeWhere((r) => r['account_id'] == args[0]);
      case OutboxSql.recoverInterrupted:
        for (final r in _d.outbox.where((r) => r['state'] == args[1])) {
          r['state'] = args[0];
        }
      case FeedSql.clearFeed:
        _d.feedRows.removeWhere((_, r) => r['account_id'] == args[0] && r['feed'] == args[1]);
      case FeedSql.upsertRow:
        _d.feedRows['${args[0]}|${args[1]}|${args[2]}'] = {
          'account_id': args[0],
          'feed': args[1],
          'id': args[2],
          'json': args[3],
        };
      case FeedSql.deleteRow:
        _d.feedRows.remove('${args[0]}|${args[1]}|${args[2]}');
      case FeedSql.upsertCursor:
        _d.cursors['${args[0]}|${args[1]}'] = args[2]! as String;
      case FeedSql.deleteAccountRows:
        _d.feedRows.removeWhere((_, r) => r['account_id'] == args[0]);
      case FeedSql.deleteAccountCursors:
        _d.cursors.removeWhere((k, _) => k.startsWith('${args[0]}|'));
      default:
        // DDL (CREATE TABLE ...) and test-only statements: recorded in the log, nothing else.
        _db.otherStatements++;
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?> args = const []]) async {
    _guard(sql);
    switch (sql) {
      case OutboxSql.due:
        return _sorted(
          _d.outbox.where((r) =>
              r['account_id'] == args[0] &&
              r['state'] == args[1] &&
              (r['next_attempt_at']! as int) <= (args[2]! as int)),
        );
      case OutboxSql.all:
        return _sorted(_d.outbox.where((r) => r['account_id'] == args[0]));
      case FeedSql.readCursor:
        final c = _d.cursors['${args[0]}|${args[1]}'];
        return c == null ? [] : [{'cursor_value': c}];
      case FeedSql.readAll:
        final rows = _d.feedRows.values
            .where((r) => r['account_id'] == args[0] && r['feed'] == args[1])
            .toList()
          ..sort((a, b) => (a['id']! as int).compareTo(b['id']! as int));
        return [for (final r in rows) {'json': r['json']}];
      default:
        throw StateError('FakeSqlDatabase: unsupported query $sql');
    }
  }

  List<Map<String, Object?>> _sorted(Iterable<Map<String, Object?>> rows) {
    final list = [for (final r in rows) Map<String, Object?>.from(r)]
      ..sort((a, b) => (a['seq']! as int).compareTo(b['seq']! as int));
    return list;
  }
}

/// A file on "disk": survives [YazanStorage.close] and re-open, rejects a key it was not created
/// with, and can be deleted.
class FakeDatabaseOpener implements EncryptedDatabaseOpener {
  FakeSqlDatabase? file;
  String? _fileKey;
  int opens = 0;
  int deletes = 0;

  @override
  Future<SqlDatabase> open(String key) async {
    opens++;
    final existing = file;
    if (existing != null) {
      if (_fileKey != key) throw const StorageUnreadableException('file is not a database');
      existing.closed = false;
      return existing;
    }
    _fileKey = key;
    return file = FakeSqlDatabase();
  }

  @override
  Future<void> deleteDatabase() async {
    deletes++;
    file = null;
    _fileKey = null;
  }
}

class MapSecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String name) async => values[name];

  @override
  Future<void> write(String name, String value) async => values[name] = value;

  @override
  Future<void> delete(String name) async => values.remove(name);
}
