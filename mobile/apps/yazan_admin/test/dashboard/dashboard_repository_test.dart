import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/dashboard/dashboard_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'fakes.dart';

const _forbidden = ApiError(status: 403, code: 'yazan_forbidden');

/// A feed store whose writes always fail, as a full or locked disk would.
class _BrokenStore extends MemoryFeedStore {
  @override
  Future<void> apply({
    required List<Map<String, dynamic>> upserts,
    required List<int> deletedIds,
    required String cursor,
    required bool initial,
  }) async {
    throw Exception('disk full');
  }
}

void main() {
  test('a refresh loads the snapshot and saves it as one row of the feed store', () async {
    final server = FakeDashboardServer();
    final store = MemoryFeedStore();
    final repo = server.repository(store: store);
    await repo.refresh();

    expect(repo.loaded, isTrue);
    expect(repo.lastRefreshFailed, isFalse);
    expect(repo.noAccess, isFalse);
    expect(repo.snapshot!.processing, 4);
    expect(repo.snapshot!.fetchedAt, fixedNow);
    expect(store.rows.keys, [DashboardRepository.rowId]);
    expect(server.daysAsked, [30]);
  });

  test('the saved copy shows after a restart before any network call', () async {
    final server = FakeDashboardServer();
    final store = MemoryFeedStore();
    final first = server.repository(store: store);
    await first.refresh();
    first.dispose();

    final offline = FakeDashboardServer()..failure = Exception('offline');
    final second = offline.repository(store: store);
    await second.ready;
    expect(second.snapshot, isNotNull);
    expect(second.snapshot!.sales!.netRevenue, '450.00');
    expect(second.snapshot!.fetchedAt.toUtc(), fixedNow.toUtc());
    expect(second.loaded, isFalse);
    expect(offline.daysAsked, isEmpty);
  });

  test('offline: a failed refresh keeps the copy and says so', () async {
    final server = FakeDashboardServer();
    final repo = server.repository();
    await repo.refresh();
    final before = repo.snapshot;

    server.failure = Exception('no network');
    await repo.refresh();
    expect(repo.lastRefreshFailed, isTrue);
    expect(repo.noAccess, isFalse);
    expect(identical(repo.snapshot, before), isTrue);

    server.failure = null;
    await repo.refresh();
    expect(repo.lastRefreshFailed, isFalse);
  });

  test('a server error other than 403 keeps the copy', () async {
    final server = FakeDashboardServer();
    final repo = server.repository();
    await repo.refresh();
    server.failure = const ApiError(status: 500, code: 'internal');
    await repo.refresh();
    expect(repo.lastRefreshFailed, isTrue);
    expect(repo.noAccess, isFalse);
    expect(repo.snapshot, isNotNull);
  });

  test('first ever refresh failing leaves no snapshot', () async {
    final server = FakeDashboardServer()..failure = Exception('offline');
    final repo = server.repository();
    await repo.refresh();
    expect(repo.snapshot, isNull);
    expect(repo.loaded, isTrue);
    expect(repo.lastRefreshFailed, isTrue);
    expect(repo.noAccess, isFalse);
  });

  test('403 hides the dashboard and drops the saved copy', () async {
    final server = FakeDashboardServer();
    final store = MemoryFeedStore();
    final repo = server.repository(store: store);
    await repo.refresh();
    expect(store.rows, isNotEmpty);

    server.failure = _forbidden;
    await repo.refresh();
    expect(repo.noAccess, isTrue);
    expect(repo.snapshot, isNull);
    expect(store.rows, isEmpty);
  });

  test('an answer with no section at all means no access, and nothing is kept', () async {
    final server = FakeDashboardServer()..answer = {'days': 30};
    final store = MemoryFeedStore();
    final repo = server.repository(store: store);
    await repo.refresh();
    expect(repo.noAccess, isTrue);
    expect(repo.snapshot, isNull);
    expect(store.rows, isEmpty);
    expect(server.alertSinces, isEmpty);
  });

  test('access comes back when the permission is granted again', () async {
    final server = FakeDashboardServer()..failure = _forbidden;
    final repo = server.repository();
    await repo.refresh();
    expect(repo.noAccess, isTrue);

    server
      ..failure = null
      ..answer = bootstrapAnswer();
    await repo.refresh();
    expect(repo.noAccess, isFalse);
    expect(repo.snapshot, isNotNull);
  });

  test('a store that cannot be written does not break the refresh', () async {
    final server = FakeDashboardServer();
    final repo = server.repository(store: _BrokenStore());
    await repo.refresh();
    expect(repo.snapshot, isNotNull);
    expect(repo.lastRefreshFailed, isFalse);
  });

  test('a second refresh while one runs is ignored', () async {
    final server = FakeDashboardServer();
    final repo = server.repository();
    await Future.wait([repo.refresh(), repo.refresh(), repo.refresh()]);
    expect(server.daysAsked, hasLength(1));
  });

  test('choosing a window asks the server for it and remembers it', () async {
    final server = FakeDashboardServer();
    final store = MemoryFeedStore();
    final repo = server.repository(store: store);
    await repo.refresh();
    server.answer = bootstrapAnswer(days: 90);
    await repo.setDays(90);
    expect(repo.days, 90);
    expect(server.daysAsked, [30, 90]);
    expect(repo.snapshot!.days, 90);

    // The next start opens on the window that was last used.
    final restarted = FakeDashboardServer().repository(store: store);
    await restarted.ready;
    expect(restarted.days, 90);
  });

  group('new-order alerts', () {
    test('the first time only seeds the baseline: nothing is flagged', () async {
      final server = FakeDashboardServer()..alerts = alertsAnswer(latest: 1005);
      final repo = server.repository();
      await repo.refresh();
      expect(server.alertSinces, [null]);
      expect(repo.snapshot!.alerts, isNull);
      expect(repo.snapshot!.alertBaseline, 1005);
    });

    test('later refreshes ask after the baseline and flag what is new', () async {
      final server = FakeDashboardServer();
      final repo = server.repository();
      await repo.refresh();

      server.alerts = alertsAnswer(count: 2, latest: 1007);
      await repo.refresh();
      expect(server.alertSinces, [null, 1005]);
      expect(repo.snapshot!.alerts!.count, 2);
      expect(repo.snapshot!.alertBaseline, 1005);

      // Still flagged on the next refresh: it stays until the person acts on it.
      await repo.refresh();
      expect(server.alertSinces.last, 1005);
      expect(repo.snapshot!.alerts!.count, 2);
    });

    test('acknowledging clears the alert, moves the baseline and survives a restart', () async {
      final server = FakeDashboardServer();
      final store = MemoryFeedStore();
      final repo = server.repository(store: store);
      await repo.refresh();
      server.alerts = alertsAnswer(count: 2, latest: 1007);
      await repo.refresh();

      await repo.acknowledgeAlerts();
      expect(repo.snapshot!.alerts, isNull);
      expect(repo.snapshot!.alertBaseline, 1007);

      final restarted = server.repository(store: store);
      await restarted.ready;
      expect(restarted.snapshot!.alerts, isNull);
      expect(restarted.snapshot!.alertBaseline, 1007);

      server.alerts = alertsAnswer(latest: 1007);
      await restarted.refresh();
      expect(server.alertSinces.last, 1007);
      expect(restarted.snapshot!.alerts, isNull);
    });

    test('acknowledging with nothing flagged changes nothing', () async {
      final server = FakeDashboardServer();
      final repo = server.repository();
      await repo.refresh();
      final before = repo.snapshot;
      await repo.acknowledgeAlerts();
      expect(identical(repo.snapshot, before), isTrue);
    });

    test('a failing alerts route never fails the dashboard and keeps the old alert', () async {
      final server = FakeDashboardServer();
      final repo = server.repository();
      await repo.refresh();
      server.alerts = alertsAnswer(count: 1, latest: 1006);
      await repo.refresh();
      expect(repo.snapshot!.alerts!.count, 1);

      server.alertsFailure = Exception('boom');
      await repo.refresh();
      expect(repo.lastRefreshFailed, isFalse);
      expect(repo.snapshot!.alerts!.count, 1);
      expect(repo.snapshot!.processing, 4);
    });

    test('an account that may not read orders is never asked for alerts', () async {
      final server = FakeDashboardServer()
        ..answer = bootstrapAnswer(without: {'recentOrders', 'onHold', 'processing'});
      final repo = server.repository();
      await repo.refresh();
      expect(server.alertSinces, isEmpty);
      expect(repo.snapshot!.outOfStock, 3);
    });
  });
}
