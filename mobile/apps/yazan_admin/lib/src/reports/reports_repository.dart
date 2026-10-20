import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'reports_api.dart';
import 'reports_snapshot.dart';

/// Loads the reports and keeps the last good answer of each window for offline use.
///
/// Online first: [refresh] asks the server for the chosen window and replaces its snapshot. Each
/// window (7, 30, 90 days) is one row of a [FeedStore] (row id = days), so the copy lives in the
/// encrypted per-account database and goes with it on sign-out. A failed refresh keeps what is
/// cached and sets [lastRefreshFailed]; the page then shows "as of <time>".
///
/// Access: sales come from a route that needs `reports.view`, the status counts from the orders
/// list (`orders.view`). A section the server refuses (403, `ErrorAction.hideFeature`) is left out;
/// when both are refused [noAccess] is set and every cached copy is dropped, so a revoked
/// permission does not leave figures on the phone.
class ReportsRepository extends ChangeNotifier {
  ReportsRepository({
    required SalesFetch fetchSales,
    StatusCountFetch? fetchStatusCount,
    FeedStore? store,
    DateTime Function()? clock,
    int days = 30,
  })  : _fetchSales = fetchSales,
        _fetchCount = fetchStatusCount,
        _store = store ?? MemoryFeedStore(),
        _clock = clock ?? DateTime.now,
        _days = days {
    _ready = _reload();
  }

  /// The production wiring over the API client.
  factory ReportsRepository.forClient(YazanApiClient client, {FeedStore? store}) {
    return ReportsRepository(
      store: store,
      fetchSales: salesFetch(client),
      fetchStatusCount: statusCountFetch(client),
    );
  }

  /// The reporting windows the page offers, in days.
  static const periods = [7, 30, 90];

  /// The order statuses counted, in the order they are listed.
  static const statuses = [
    'pending',
    'processing',
    'on-hold',
    'completed',
    'cancelled',
    'refunded',
    'failed',
  ];

  final SalesFetch _fetchSales;
  final StatusCountFetch? _fetchCount;
  final FeedStore _store;
  final DateTime Function() _clock;
  late final Future<void> _ready;

  final Map<int, ReportsSnapshot> _cache = {};
  int _days;
  bool _loading = false;
  bool _again = false;
  bool _loaded = false;
  bool _failed = false;
  bool _noAccess = false;
  bool _disposed = false;

  /// Completes once the cached snapshots have been read.
  Future<void> get ready => _ready;

  /// The snapshot of the chosen window, if there is one.
  ReportsSnapshot? get snapshot => _cache[_days];

  int get days => _days;
  bool get loading => _loading;

  /// True once a refresh has finished, successfully or not.
  bool get loaded => _loaded;
  bool get lastRefreshFailed => _failed;

  /// The server denied every report to this account.
  bool get noAccess => _noAccess;

  /// Picks the reporting window and refreshes.
  Future<void> setDays(int days) async {
    if (days == _days) return;
    _days = days;
    _notify();
    await refresh();
  }

  Future<void> _reload() async {
    try {
      for (final r in await _store.readAll()) {
        final s = ReportsSnapshot.fromJson(r);
        _cache[s.days] = s;
      }
    } on Exception {
      // An unreadable cache shows as empty; the next refresh fills it.
    }
    _notify();
  }

  Future<void> refresh() async {
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    _notify();
    await _ready;
    do {
      _again = false;
      await _refreshOnce(_days);
    } while (_again && !_disposed);
    _loading = false;
    _loaded = true;
    _notify();
  }

  Future<void> _refreshOnce(int days) async {
    final previous = _cache[days];

    var salesForbidden = false;
    var salesFailed = false;
    SalesReport? sales;
    try {
      sales = SalesReport.fromServer(await _fetchSales(days));
    } on ApiError catch (e) {
      if (e.action == ErrorAction.hideFeature) {
        salesForbidden = true;
      } else {
        salesFailed = true;
      }
    } on Exception {
      salesFailed = true;
    }

    var countsForbidden = false;
    var countsFailed = false;
    Map<String, int>? counts;
    final fetchCount = _fetchCount;
    if (fetchCount == null) {
      countsForbidden = true;
    } else {
      try {
        final totals = await Future.wait([for (final s in statuses) fetchCount(s, days)]);
        counts = {for (var i = 0; i < statuses.length; i++) statuses[i]: totals[i]};
      } on ApiError catch (e) {
        if (e.action == ErrorAction.hideFeature) {
          countsForbidden = true;
        } else {
          countsFailed = true;
        }
      } on Exception {
        countsFailed = true;
      }
    }

    _failed = salesFailed || countsFailed;
    if (salesForbidden && countsForbidden) {
      _noAccess = true;
      _cache.clear();
      await _drop();
      return;
    }
    _noAccess = false;

    final next = ReportsSnapshot(
      days: days,
      fetchedAt: _failed ? (previous?.fetchedAt ?? _clock()) : _clock(),
      sales: salesFailed ? previous?.sales : sales,
      statusCounts: countsFailed ? previous?.statusCounts : counts,
    );
    if (next.isEmpty) {
      _cache.remove(days);
      await _drop(days: [days]);
      return;
    }
    _cache[days] = next;
    await _save(next);
  }

  Future<void> _save(ReportsSnapshot snapshot) async {
    try {
      await _store.apply(upserts: [snapshot.toJson()], deletedIds: const [], cursor: '', initial: false);
    } on Exception {
      // A cache that cannot be written only means no offline copy next time.
    }
  }

  Future<void> _drop({List<int> days = periods}) async {
    try {
      await _store.apply(upserts: const [], deletedIds: days, cursor: '', initial: false);
    } on Exception {
      // Nothing more to do for an unwritable cache.
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
