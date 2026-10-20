import 'package:flutter/foundation.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

/// What the Sync center shows besides the queue itself.
class SyncStatus extends ChangeNotifier {
  bool _running = false;
  DateTime? _lastAttemptAt;
  DateTime? _lastSuccessAt;
  SyncReport? _lastReport;

  bool get running => _running;

  /// When a run last finished, whatever its result.
  DateTime? get lastAttemptAt => _lastAttemptAt;

  /// When a run last reached the server (it was online and the session was valid). The queue need
  /// not have been empty: failures and conflicts are reported separately.
  DateTime? get lastSuccessAt => _lastSuccessAt;
  SyncReport? get lastReport => _lastReport;

  void begin() {
    _running = true;
    notifyListeners();
  }

  void end(SyncReport? report, DateTime now) {
    _running = false;
    if (report != null) {
      _lastAttemptAt = now;
      _lastReport = report;
      if (!report.offline && !report.signedOut) _lastSuccessAt = now;
    }
    notifyListeners();
  }
}

/// A [SyncEngine] that records [status] and never runs the same account twice at once (the order
/// screen and the Sync center can both ask; a second caller waits for the run already in flight).
class ObservedSyncEngine extends SyncEngine {
  ObservedSyncEngine({
    required super.store,
    required super.send,
    SyncStatus? status,
    this.onSessionEnded,
    DateTime Function()? now,
  })  : status = status ?? SyncStatus(),
        _now = now ?? (() => DateTime.now().toUtc());

  final SyncStatus status;

  /// Called when the server refused the session during a run.
  final VoidCallback? onSessionEnded;
  final DateTime Function() _now;
  final Map<String, Future<SyncReport>> _inFlight = {};

  @override
  Future<SyncReport> run(String accountId) {
    final running = _inFlight[accountId];
    if (running != null) return running;
    final future = _observed(accountId);
    _inFlight[accountId] = future;
    return future.whenComplete(() => _inFlight.remove(accountId));
  }

  Future<SyncReport> _observed(String accountId) async {
    status.begin();
    SyncReport? report;
    try {
      report = await super.run(accountId);
      return report;
    } finally {
      status.end(report, _now());
      if (report != null && report.signedOut) onSessionEnded?.call();
    }
  }
}
