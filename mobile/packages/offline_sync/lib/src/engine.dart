import 'dart:math';

import 'package:yazan_domain/yazan_domain.dart';

import 'outbox.dart';

/// Sends one op. Throws [ApiError] for a server answer; any other exception means "no network".
typedef OpSender = Future<void> Function(OutboxOp op);

class SyncReport {
  SyncReport({
    this.sent = 0,
    this.conflicts = 0,
    this.failed = 0,
    this.retryLater = 0,
    this.signedOut = false,
    this.offline = false,
  });

  int sent;
  int conflicts;
  int failed;
  int retryLater;
  bool signedOut;
  bool offline;
}

/// Replays the outbox. Rules:
///
/// * Oldest first, one at a time (order matters: a note must follow the edit it refers to).
/// * Success: removed. 412 conflict: kept, flagged, and NOT retried — the person decides.
/// * 409 busy / 429 / 5xx / refresh needed: rescheduled with exponential backoff + jitter.
/// * Other 4xx (the request itself is wrong): marked failed, kept for the sync centre to show.
/// * Session over: stop everything. No network: stop at once, nothing is counted as an attempt.
class SyncEngine {
  SyncEngine({
    required this.store,
    required this.send,
    DateTime Function()? clock,
    double Function()? jitter,
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 30),
  })  : _clock = clock ?? (() => DateTime.now().toUtc()),
        _jitter = jitter ?? Random().nextDouble;

  final OutboxStore store;
  final OpSender send;
  final Duration baseDelay;
  final Duration maxDelay;
  final DateTime Function() _clock;
  final double Function() _jitter;

  /// Adds an op. Online-only actions cannot be built: [QueueableKind] has no value for them.
  Future<void> enqueue(OutboxOp op) => store.add(op);

  Duration backoff(int attempts) {
    final exp = baseDelay.inMilliseconds * pow(2, attempts.clamp(0, 12)).toInt();
    final capped = min(exp, maxDelay.inMilliseconds);
    // 50–100% of the delay, so many phones coming back online do not hit the server together.
    return Duration(milliseconds: (capped * (0.5 + 0.5 * _jitter())).round());
  }

  Future<SyncReport> run(String accountId) async {
    final report = SyncReport();
    final ops = await store.due(accountId, _clock());

    for (final op in ops) {
      op.state = OpState.sending;
      await store.update(op);
      try {
        await send(op);
        await store.remove(op.id);
        report.sent++;
      } on ApiError catch (e) {
        switch (e.action) {
          case ErrorAction.signIn:
            op.state = OpState.pending;
            await store.update(op);
            report.signedOut = true;
            return report;
          case ErrorAction.showConflict:
            op.state = OpState.conflict;
            op.serverVersion = e.current;
            op.lastError = e.code;
            report.conflicts++;
          case ErrorAction.waitAndRetrySameKey:
          case ErrorAction.backOff:
          case ErrorAction.refreshThenRetry:
            await _later(op, e, report, e.retryAfter);
          case ErrorAction.other when e.status >= 500:
            await _later(op, e, report, null);
          default:
            op.state = OpState.failed;
            op.lastError = e.code;
            report.failed++;
        }
        await store.update(op);
      } catch (_) {
        // No network: put it back untouched and stop; the next trigger tries again.
        op.state = OpState.pending;
        await store.update(op);
        report.offline = true;
        return report;
      }
    }
    return report;
  }

  Future<void> _later(OutboxOp op, ApiError e, SyncReport r, int? retryAfter) async {
    op.attempts++;
    op.state = OpState.pending;
    op.lastError = e.code;
    final wait = retryAfter != null ? Duration(seconds: retryAfter) : backoff(op.attempts);
    op.nextAttemptAt = _clock().add(wait);
    r.retryLater++;
  }
}
