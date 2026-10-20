/// What may be queued while offline. Everything else (payments, order placement, refunds, final
/// price/stock changes, permission grants, account deletion) is online-only and is refused here,
/// so no code path can quietly queue it. See docs/mobile/02-FEATURE-PARITY-MATRIX.md (class D).
enum QueueableKind {
  orderNote,
  productText,
  wishlist,
  address,
  task,
  couponDraft,
  mediaUpload,
}

enum OpState { pending, sending, failed, conflict }

class OutboxOp {
  OutboxOp({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.method,
    required this.path,
    required this.idempotencyKey,
    this.body,
    this.baseVersion,
    this.state = OpState.pending,
    this.attempts = 0,
    DateTime? nextAttemptAt,
    this.lastError,
    this.serverVersion,
  }) : nextAttemptAt = nextAttemptAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  final String id;

  /// Data is isolated per account: another user signing in on this phone never sees or sends these.
  final String accountId;
  final QueueableKind kind;
  final String method;
  final String path;

  /// Fixed when the op is created and reused on EVERY retry: that is what makes a replay execute once.
  final String idempotencyKey;
  final Map<String, dynamic>? body;

  /// Version token the user last saw (sent as If-Match for admin edits).
  final String? baseVersion;

  OpState state;
  int attempts;
  DateTime nextAttemptAt;
  String? lastError;

  /// Server's current token when the op ended in a conflict.
  String? serverVersion;
}

/// Persistent queue. The apps implement this over encrypted SQLite; tests use [MemoryOutboxStore].
abstract class OutboxStore {
  Future<void> add(OutboxOp op);
  Future<void> update(OutboxOp op);
  Future<void> remove(String id);

  /// Ops for [accountId] that are pending and due at [now], oldest first.
  Future<List<OutboxOp>> due(String accountId, DateTime now);
  Future<List<OutboxOp>> all(String accountId);

  /// Sign-out or revoked access: the account's queue is dropped.
  Future<void> clearAccount(String accountId);
}

class MemoryOutboxStore implements OutboxStore {
  final List<OutboxOp> _ops = [];

  @override
  Future<void> add(OutboxOp op) async => _ops.add(op);

  @override
  Future<void> update(OutboxOp op) async {}

  @override
  Future<void> remove(String id) async => _ops.removeWhere((o) => o.id == id);

  @override
  Future<List<OutboxOp>> due(String accountId, DateTime now) async => [
        for (final o in _ops)
          if (o.accountId == accountId &&
              o.state == OpState.pending &&
              !o.nextAttemptAt.isAfter(now))
            o,
      ];

  @override
  Future<List<OutboxOp>> all(String accountId) async =>
      [for (final o in _ops) if (o.accountId == accountId) o];

  @override
  Future<void> clearAccount(String accountId) async =>
      _ops.removeWhere((o) => o.accountId == accountId);
}
