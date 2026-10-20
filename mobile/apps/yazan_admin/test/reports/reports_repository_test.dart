import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/reports/reports_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'fakes.dart';

const _forbidden = ApiError(status: 403, code: 'yazan_forbidden');

void main() {
  test('refresh builds the snapshot of the chosen window', () async {
    final server = FakeReportsServer();
    final repo = server.repository();
    await repo.refresh();

    final s = repo.snapshot!;
    expect(s.days, 30);
    expect(s.fetchedAt, reportsNow);
    expect(s.sales!.netRevenue, '450.00');
    expect(s.sales!.series, hasLength(3));
    expect(s.sales!.top.first.name, 'Agate ring');
    expect(s.sales!.refundedOrders, 1);
    expect(s.statusCounts!['processing'], 4);
    expect(s.statusCounts!['pending'], 0);
    expect(s.statusCounts!.keys, ReportsRepository.statuses);
    expect(repo.lastRefreshFailed, isFalse);
    expect(repo.noAccess, isFalse);
  });

  test('each window keeps its own copy and asks the server for its days', () async {
    final server = FakeReportsServer();
    final repo = server.repository();
    await repo.refresh();
    server.sales = salesAnswer(scale: 2);
    await repo.setDays(7);

    expect(server.daysAsked, [30, 7]);
    expect(repo.days, 7);
    expect(repo.snapshot!.days, 7);
    expect(repo.snapshot!.sales!.series.first.total, 200.0);
    await repo.setDays(30);
    expect(server.daysAsked, [30, 7, 30]);
  });

  test('a new repository over the same store shows the last snapshot before any network', () async {
    final store = MemoryFeedStore();
    await (FakeReportsServer().repository(store: store)).refresh();

    final server = FakeReportsServer()..salesFailure = Exception('offline');
    server.countFailure = Exception('offline');
    final repo = server.repository(store: store);
    await repo.ready;
    expect(repo.snapshot!.sales!.netRevenue, '450.00');
    expect(repo.snapshot!.fetchedAt, reportsNow);

    await repo.refresh();
    expect(repo.lastRefreshFailed, isTrue);
    expect(repo.snapshot!.sales!.netRevenue, '450.00');
  });

  test('a failed refresh keeps the old figures and the old time', () async {
    final server = FakeReportsServer();
    final repo = server.repository();
    await repo.refresh();
    server.salesFailure = Exception('timeout');
    await repo.refresh();

    expect(repo.lastRefreshFailed, isTrue);
    expect(repo.snapshot!.sales!.netRevenue, '450.00');
    expect(repo.snapshot!.statusCounts!['completed'], 12);
  });

  test('sales refused: status counts alone are kept', () async {
    final server = FakeReportsServer()..salesFailure = _forbidden;
    final repo = server.repository();
    await repo.refresh();

    expect(repo.noAccess, isFalse);
    expect(repo.snapshot!.sales, isNull);
    expect(repo.snapshot!.statusCounts!['processing'], 4);
  });

  test('both refused: no access, and the cached copy is dropped', () async {
    final store = MemoryFeedStore();
    final server = FakeReportsServer();
    final repo = server.repository(store: store);
    await repo.refresh();
    expect(store.rows, isNotEmpty);

    server.salesFailure = _forbidden;
    server.countFailure = _forbidden;
    await repo.refresh();
    expect(repo.noAccess, isTrue);
    expect(repo.snapshot, isNull);
    expect(store.rows, isEmpty);
  });

  test('without a count route the status section is left out', () async {
    final server = FakeReportsServer();
    final repo = ReportsRepository(fetchSales: server.fetchSales, clock: () => reportsNow);
    await repo.refresh();
    expect(repo.snapshot!.sales, isNotNull);
    expect(repo.snapshot!.statusCounts, isNull);
  });
}
