import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/reports/reports_page.dart';
import 'package:yazan_admin/src/reports/reports_repository.dart';
import 'package:yazan_admin/src/reports/sales_bar_chart.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../dashboard/fakes.dart' show dashboardHost, tallScreen;
import 'fakes.dart';

Widget _page(ReportsRepository repo, {Locale locale = const Locale('en')}) =>
    dashboardHost(locale, ReportsPage(repository: repo));

Finder _in(String key, Finder what) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: what);

void main() {
  testWidgets('English: sales, chart, top products, statuses and refunds', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(FakeReportsServer().repository()));
    await tester.pumpAndSettle();

    expect(find.text(r'450.00 $'), findsOneWidget);
    expect(find.byKey(const ValueKey('reports-chart-paint')), findsOneWidget);
    expect(find.text('2026-10-18'), findsOneWidget);
    expect(_in('reports-orders', find.text('3')), findsOneWidget);
    expect(find.text('Top products'), findsOneWidget);
    expect(find.text('Agate ring'), findsOneWidget);
    expect(find.text('Sold: 3'), findsOneWidget);
    expect(find.text(r'300.00 $'), findsOneWidget);
    expect(find.text('Orders by status'), findsOneWidget);
    expect(_in('reports-status-processing', find.text('4')), findsOneWidget);
    expect(_in('reports-status-completed', find.text('12')), findsOneWidget);
    expect(_in('reports-refunded', find.text(r'10.00 $')), findsOneWidget);
    expect(find.text('Fully refunded orders: 1'), findsOneWidget);
    expect(find.textContaining('2026-10-20 14:05'), findsOneWidget);
    expect(find.byKey(const ValueKey('reports-stale')), findsNothing);
  });

  testWidgets('Arabic: translated sections and Latin amounts', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(FakeReportsServer().repository(), locale: const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.text('أفضل المنتجات مبيعًا'), findsOneWidget);
    expect(find.text('الطلبات حسب الحالة'), findsOneWidget);
    expect(find.text('المبالغ المستردة'), findsOneWidget);
    expect(find.text(r'450.00 $'), findsOneWidget);
    expect(find.text('Agate ring'), findsOneWidget);
  });

  testWidgets('only the sections the server returned are drawn', (tester) async {
    tallScreen(tester);
    final server = FakeReportsServer()
      ..salesFailure = const ApiError(status: 403, code: 'yazan_forbidden');
    await tester.pumpWidget(_page(server.repository()));
    await tester.pumpAndSettle();

    expect(find.text('Sales'), findsNothing);
    expect(find.text('Top products'), findsNothing);
    expect(find.text('Refunds'), findsNothing);
    expect(find.text('Orders by status'), findsOneWidget);
  });

  testWidgets('no access when both routes refuse', (tester) async {
    const denied = ApiError(status: 403, code: 'yazan_forbidden');
    final server = FakeReportsServer()
      ..salesFailure = denied
      ..countFailure = denied;
    await tester.pumpWidget(_page(server.repository()));
    await tester.pumpAndSettle();

    expect(find.text('No access'), findsOneWidget);
    expect(find.textContaining('view reports'), findsOneWidget);
  });

  testWidgets('no sales in the window: a note instead of the chart', (tester) async {
    tallScreen(tester);
    final server = FakeReportsServer()..sales = salesAnswer(scale: 0);
    await tester.pumpWidget(_page(server.repository()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reports-no-sales')), findsOneWidget);
    expect(find.byKey(const ValueKey('reports-chart-paint')), findsNothing);
  });

  testWidgets('offline: the cached snapshot shows with the offline badge and its time', (tester) async {
    tallScreen(tester);
    final store = MemoryFeedStore();
    await FakeReportsServer().repository(store: store).refresh();

    final server = FakeReportsServer()
      ..salesFailure = Exception('offline')
      ..countFailure = Exception('offline');
    await tester.pumpWidget(_page(server.repository(store: store)));
    await tester.pumpAndSettle();

    expect(find.text(r'450.00 $'), findsOneWidget);
    expect(find.byKey(const ValueKey('reports-stale')), findsOneWidget);
    expect(find.text('Offline copy'), findsOneWidget);
    expect(find.textContaining('2026-10-20 14:05'), findsOneWidget);
  });

  testWidgets('offline with nothing cached: a retry hint', (tester) async {
    final server = FakeReportsServer()
      ..salesFailure = Exception('offline')
      ..countFailure = Exception('offline');
    await tester.pumpWidget(_page(server.repository()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load the reports'), findsOneWidget);
  });

  testWidgets('choosing a period asks the server for it', (tester) async {
    tallScreen(tester);
    final server = FakeReportsServer();
    await tester.pumpWidget(_page(server.repository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reports-period-7')));
    await tester.pumpAndSettle();
    expect(server.daysAsked, [30, 7]);

    await tester.tap(find.byKey(const ValueKey('reports-period-90')));
    await tester.pumpAndSettle();
    expect(server.daysAsked, [30, 7, 90]);
  });

  testWidgets('pull to refresh asks the server again', (tester) async {
    tallScreen(tester);
    final server = FakeReportsServer();
    await tester.pumpWidget(_page(server.repository()));
    await tester.pumpAndSettle();
    expect(server.daysAsked, hasLength(1));

    server.sales = salesAnswer()
      ..['totals'] = {
        'net_revenue': '999.00',
        'gross_revenue': '999.00',
        'refunded': '0.00',
        'orders': 4,
        'refunded_orders': 0,
        'items_sold': 6,
        'average_order': '249.75',
      };
    final state = tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator));
    state.show();
    await tester.pumpAndSettle();

    expect(server.daysAsked, hasLength(2));
    expect(find.text(r'999.00 $'), findsOneWidget);
  });

  test('bar heights scale to the highest day; an empty day has no bar', () {
    final painter = SalesBarPainter(
      values: const [0, 50, 100],
      barColor: Colors.red,
      baseColor: Colors.grey,
    );
    expect(painter.maxValue, 100);
    expect(painter.barHeight(100, 80), 80);
    expect(painter.barHeight(50, 80), 40);
    expect(painter.barHeight(0, 80), 0);
    expect(painter.barHeight(0.01, 80), 2);
    final none = SalesBarPainter(values: const [0, 0], barColor: Colors.red, baseColor: Colors.grey);
    expect(none.barHeight(0, 80), 0);
  });
}
