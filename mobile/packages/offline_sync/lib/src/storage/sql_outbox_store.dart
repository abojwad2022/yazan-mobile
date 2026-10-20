import 'dart:convert';

import '../outbox.dart';
import 'schema.dart';
import 'sql.dart';

/// [OutboxStore] over SQLite (SQLCipher in the apps). Survives process death.
///
/// Differences from [MemoryOutboxStore] that matter:
///
/// * Reads return fresh [OutboxOp] objects, so [update] really writes the mutable fields
///   (state, attempts, next attempt, last error, server version). The engine already calls it after
///   every change.
/// * Queue order is insertion order (`seq`), not clock order, so it is stable across restarts and
///   clock changes.
/// * [add] of an id that already exists is ignored (a double tap must not queue two ops).
/// * Ops left in `sending` by a killed process are put back to `pending` by [recoverInterrupted].
class SqlOutboxStore implements OutboxStore {
  SqlOutboxStore(this._db, {DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  final SqlExecutor _db;
  final DateTime Function() _clock;

  @override
  Future<void> add(OutboxOp op) => _db.execute(OutboxSql.insert, [
        op.id,
        op.accountId,
        op.kind.name,
        op.entity,
        op.method,
        op.path,
        op.idempotencyKey,
        op.body == null ? null : jsonEncode(op.body),
        op.baseVersion,
        op.state.name,
        op.attempts,
        op.nextAttemptAt.toUtc().millisecondsSinceEpoch,
        op.lastError,
        op.serverVersion,
        _clock().millisecondsSinceEpoch,
      ]);

  @override
  Future<void> update(OutboxOp op) => _db.execute(OutboxSql.update, [
        op.state.name,
        op.attempts,
        op.nextAttemptAt.toUtc().millisecondsSinceEpoch,
        op.lastError,
        op.serverVersion,
        op.id,
      ]);

  @override
  Future<void> remove(String id) => _db.execute(OutboxSql.remove, [id]);

  @override
  Future<List<OutboxOp>> due(String accountId, DateTime now) async => _decode(
        await _db.query(OutboxSql.due, [
          accountId,
          OpState.pending.name,
          now.toUtc().millisecondsSinceEpoch,
        ]),
      );

  @override
  Future<List<OutboxOp>> all(String accountId) async =>
      _decode(await _db.query(OutboxSql.all, [accountId]));

  @override
  Future<void> clearAccount(String accountId) =>
      _db.execute(OutboxSql.deleteAccount, [accountId]);

  /// Call once when the database is opened (before any sync run).
  Future<void> recoverInterrupted() =>
      _db.execute(OutboxSql.recoverInterrupted, [OpState.pending.name, OpState.sending.name]);

  /// A row this app version cannot read (unknown kind or state, broken JSON) is skipped rather than
  /// failing the whole queue; it stays in the file untouched.
  static List<OutboxOp> _decode(List<Map<String, Object?>> rows) {
    final ops = <OutboxOp>[];
    for (final r in rows) {
      final op = _fromRow(r);
      if (op != null) ops.add(op);
    }
    return ops;
  }

  static OutboxOp? _fromRow(Map<String, Object?> r) {
    try {
      final kind = QueueableKind.values.byName(r['kind']! as String);
      final state = OpState.values.byName(r['state']! as String);
      final rawBody = r['body'] as String?;
      return OutboxOp(
        id: r['id']! as String,
        accountId: r['account_id']! as String,
        kind: kind,
        method: r['method']! as String,
        path: r['path']! as String,
        idempotencyKey: r['idempotency_key']! as String,
        body: rawBody == null ? null : Map<String, dynamic>.from(jsonDecode(rawBody) as Map),
        entity: r['entity'] as String?,
        baseVersion: r['base_version'] as String?,
        state: state,
        attempts: (r['attempts'] as num?)?.toInt() ?? 0,
        nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(
          (r['next_attempt_at'] as num?)?.toInt() ?? 0,
          isUtc: true,
        ),
        lastError: r['last_error'] as String?,
        serverVersion: r['server_version'] as String?,
      );
    } on Object {
      return null;
    }
  }
}
