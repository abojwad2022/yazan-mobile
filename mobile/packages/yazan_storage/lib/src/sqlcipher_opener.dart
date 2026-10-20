import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'wrong_key.dart';

/// Opens the app's database file with SQLCipher. [fileName] lives in the platform databases
/// directory (app-private); [databasesPath] overrides that directory (tests).
class SqlCipherOpener implements EncryptedDatabaseOpener {
  SqlCipherOpener({required this.fileName, this.databasesPath});

  final String fileName;
  final String? databasesPath;

  Future<String> _path() async => '${databasesPath ?? await getDatabasesPath()}/$fileName';

  @override
  Future<SqlDatabase> open(String key) async {
    final path = await _path();
    Database? db;
    try {
      db = await openDatabase(
        path,
        password: key,
        onConfigure: (d) async {
          // Best effort: freed pages are overwritten, so wiped rows do not linger in the file.
          await d
              .rawQuery('PRAGMA secure_delete = ON')
              .catchError((Object _) => <Map<String, Object?>>[]);
        },
      );
      final wrapped = SqfliteSqlDatabase(db);
      // Reading the header is what actually proves the key; do it here so a wrong key is reported
      // as "unreadable", not as a random failure in the first query of the app.
      await wrapped.userVersion();
      return wrapped;
    } on Object catch (e) {
      // The handle may already be unusable; the original error is the one to report.
      await db?.close().catchError((Object _) {});
      if (looksLikeWrongKey(e)) throw StorageUnreadableException(e);
      rethrow;
    }
  }

  @override
  Future<void> deleteDatabase() async => databaseFactory.deleteDatabase(await _path());
}

/// [SqlDatabase] over a sqflite (SQLCipher) [Database].
class SqfliteSqlDatabase extends _SqfliteExecutor implements SqlDatabase {
  // The Database is also kept as a typed field for transaction(), so this is not a plain super parameter.
  // ignore: use_super_parameters
  SqfliteSqlDatabase(Database db)
      : _db = db,
        super(db);

  final Database _db;

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor txn) action) =>
      _db.transaction((txn) => action(_SqfliteExecutor(txn)));

  @override
  Future<void> close() => _db.close();
}

class _SqfliteExecutor implements SqlExecutor {
  _SqfliteExecutor(this._e);

  final DatabaseExecutor _e;

  @override
  Future<void> execute(String sql, [List<Object?> args = const []]) => _e.execute(sql, args);

  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?> args = const []]) async {
    final rows = await _e.rawQuery(sql, args);
    // sqflite returns read-only maps; hand out ordinary ones.
    return [for (final r in rows) Map<String, Object?>.from(r)];
  }

  @override
  Future<int> userVersion() async {
    final rows = await _e.rawQuery('PRAGMA user_version');
    if (rows.isEmpty) return 0;
    return (rows.first.values.first as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> setUserVersion(int version) => _e.execute('PRAGMA user_version = $version');
}
