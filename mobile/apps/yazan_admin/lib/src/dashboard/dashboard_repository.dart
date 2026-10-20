import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'dashboard_api.dart';
import 'dashboard_snapshot.dart';

/// Loads the dashboard home and keeps the last good answer for offline use.
///
/// Online first: [refresh] asks the server and replaces the snapshot. The snapshot is saved in a
/// [FeedStore] as a single row (id 1), so it lives in the same encrypted, per-account database as
/// the other caches and goes with them on sign-out. On start the snapshot is read back from the
/// store, so the dashboard shows after a restart before any network round trip. A failed refresh
/// keeps what is cached and sets [lastRefreshFailed]; the page then shows "as of <time>".
///
/// Access: the bootstrap route returns only the sections the account may read. A 403
/// (`ErrorAction.hideFeature`) or an answer with no section at all sets [noAccess], and the cached
/// copy is dropped so a revoked permission does not leave figures on the phone.
///
/// New-order alerts (`/orders/alerts`) are counted after a baseline order id kept in the snapshot.
/// The first time there is no baseline: the server is asked for its newest id, which becomes the
/// baseline, and nothing is flagged. Later refreshes flag the orders after the baseline until
/// [acknowledgeAlerts] moves it.
class DashboardRepository extends ChangeNotifier {
  DashboardRepository({
    required DashboardFetch fetch,
    AlertsFetch? fetchAlerts,
    FeedStore? store,
    DateTime Function()? clock,
    int days = 30,
  })  : _fetch = fetch,
        _fetchAlerts = fetchAlerts,
        _store = store ?? MemoryFeedStore(),
        _clock = clock ?? DateTime.now,
        _days = days {
    _ready = _reload();
  }

  /// The production wiring over the API client.
  factory DashboardRepository.forClient(YazanApiClient client, {FeedStore? store}) {
    return DashboardRepository(
      store: store,
      fetch: dashboardFetch(client),
      fetchAlerts: alertsFetch(client),
    );
  }

  /// The row id of the single cached snapshot.
  static const rowId = 1;

  /// The reporting windows the page offers, in days.
  static const periods = [7, 30, 90];

  final DashboardFetch _fetch;
  final AlertsFetch? _fetchAlerts;
  final FeedStore _store;
  final DateTime Function() _clock;
  late final Future<void> _ready;

  DashboardSnapshot? _snapshot;
  int _days;
  bool _daysChosen = false;
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  bool _noAccess = false;
  bool _disposed = false;
  ApiError? _error;

  /// Completes once the cached snapshot has been read.
  Future<void> get ready => _ready;

  DashboardSnapshot? get snapshot => _snapshot;

  /// The window asked for on the next refresh; follows the cached snapshot until the person picks.
  int get days => _days;

  bool get loading => _loading;

  /// True once a refresh has finished, successfully or not.
  bool get loaded => _loaded;
  bool get lastRefreshFailed => _failed;
  ApiError? get lastError => _error;

  /// The server denied the dashboard to this account (403, or it returned no section at all).
  bool get noAccess => _noAccess || _error?.action == ErrorAction.hideFeature;

  /// Picks the reporting window and refreshes.
  Future<void> setDays(int days) async {
    if (days == _days) return;
    _days = days;
    _daysChosen = true;
    _notify();
    await refresh();
  }

  Future<void> _reload() async {
    try {
      final rows = await _store.readAll();
      for (final r in rows) {
        if (r['id'] == rowId) {
          _snapshot = DashboardSnapshot.fromJson(r);
          if (!_daysChosen) _days = _snapshot!.days;
        }
      }
    } on Exception {
      // An unreadable cache shows as empty; the next refresh fills it.
    }
    _notify();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _notify();
    await _ready;
    try {
      final body = await _fetch(_days);
      final previous = _snapshot;
      var next = DashboardSnapshot.fromBootstrap(
        body,
        fetchedAt: _clock(),
        requestedDays: _days,
        alertBaseline: previous?.alertBaseline,
      );
      if (next.isEmpty) {
        _noAccess = true;
        _snapshot = null;
        await _save(null);
      } else {
        _noAccess = false;
        if (next.hasOrders) next = await _withAlerts(next, previous);
        _snapshot = next;
        await _save(next);
      }
      _failed = false;
      _error = null;
    } on ApiError catch (e) {
      _failed = true;
      _error = e;
      if (e.action == ErrorAction.hideFeature) {
        _snapshot = null;
        await _save(null);
      }
    } on Exception {
      _failed = true;
      _error = null;
    }
    _loading = false;
    _loaded = true;
    _notify();
  }

  /// Marks the new orders as seen: the baseline moves to the newest id and the alert disappears.
  Future<void> acknowledgeAlerts() async {
    final s = _snapshot;
    final alert = s?.alerts;
    if (s == null || alert == null) return;
    final next = s.copyWith(clearAlerts: true, alertBaseline: alert.latest);
    _snapshot = next;
    await _save(next);
    _notify();
  }

  /// Adds the new-order alert. Failing here never fails the dashboard: the figures are already
  /// good, so the alert simply keeps what it showed before.
  Future<DashboardSnapshot> _withAlerts(DashboardSnapshot next, DashboardSnapshot? previous) async {
    final fetch = _fetchAlerts;
    final baseline = previous?.alertBaseline;
    if (fetch == null) return next;
    try {
      final body = await fetch(baseline);
      if (baseline == null) {
        final latest = _latest(body);
        return latest == null ? next : next.copyWith(alertBaseline: latest);
      }
      return next.copyWith(alerts: NewOrdersAlert.fromServer(body));
    } on Exception {
      final old = previous?.alerts;
      return old == null ? next : next.copyWith(alerts: old);
    }
  }

  static int? _latest(Map<String, dynamic> body) {
    final v = body['latest'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  Future<void> _save(DashboardSnapshot? snapshot) async {
    try {
      await _store.apply(
        upserts: [
          if (snapshot != null) {'id': rowId, ...snapshot.toJson()},
        ],
        deletedIds: const [],
        cursor: '',
        initial: true,
      );
    } on Exception {
      // A cache that cannot be written only means no offline copy next time.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
