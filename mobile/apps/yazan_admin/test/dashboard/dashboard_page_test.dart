import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/dashboard/dashboard_page.dart';
import 'package:yazan_admin/src/dashboard/dashboard_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'fakes.dart';

class _Taps {
  final List<String?> orders = [];
  int products = 0;
}

Widget _page(DashboardRepository repo, _Taps taps, {Locale locale = const Locale('en')}) {
  return dashboardHost(
    locale,
    DashboardPage(
      repository: repo,
      onOpenOrders: taps.orders.add,
      onOpenProducts: () => taps.products++,
    ),
  );
}

Finder _in(String key, Finder what) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: what);

void main() {
  testWidgets('English: sales, orders needing action, stock and recent orders', (tester) async {
    tallScreen(tester);
    final repo = FakeDashboardServer().repository();
    await tester.pumpWidget(_page(repo, _Taps()));
    await tester.pumpAndSettle();

    expect(find.text('Needs attention'), findsOneWidget);
    expect(_in('dash-processing', find.text('Orders to fulfil')), findsOneWidget);
    expect(_in('dash-processing', find.text('4')), findsOneWidget);
    expect(_in('dash-onhold', find.text('2')), findsOneWidget);
    expect(_in('dash-outofstock', find.text('3')), findsOneWidget);
    expect(_in('dash-lowstock', find.text('5')), findsOneWidget);
    expect(_in('dash-lowstock', find.textContaining('≤ 2')), findsOneWidget);

    expect(find.text('Sales'), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-today')), findsOneWidget);
    expect(find.text(r'150.50 $'), findsOneWidget);
    expect(find.text('Orders: 1'), findsOneWidget);
    expect(find.textContaining('2026-10-20'), findsWidgets);
    expect(_in('dash-net', find.text(r'450.00 $')), findsOneWidget);
    expect(_in('dash-net', find.textContaining('+50.0%')), findsOneWidget);
    expect(_in('dash-net', find.textContaining('vs previous 30 days')), findsOneWidget);
    expect(_in('dash-orders', find.text('3')), findsOneWidget);
    expect(find.text(r'150.00 $'), findsOneWidget); // average order
    expect(find.text(r'10.00 $'), findsOneWidget); // refunded

    expect(find.text('Recent orders'), findsOneWidget);
    expect(find.text('Order #1005'), findsOneWidget);
    expect(find.text(r'$770.00'), findsOneWidget);
    expect(find.textContaining('Sara Ali'), findsOneWidget);
    // An order with no name reads as a guest; its status is spelled out.
    expect(find.text('Guest · On hold'), findsOneWidget);
    // Nothing from the customer's contact details is drawn.
    expect(find.textContaining('example.test'), findsNothing);
  });

  testWidgets('the as-of time is always shown; no offline badge while the server answers', (tester) async {
    tallScreen(tester);
    final repo = FakeDashboardServer().repository();
    await tester.pumpWidget(_page(repo, _Taps()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dash-asof')), findsOneWidget);
    expect(find.textContaining('As of'), findsOneWidget);
    expect(find.textContaining('2026-10-20 14:05'), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-stale')), findsNothing);
  });

  testWidgets('offline: the saved copy shows with its time and an offline badge', (tester) async {
    tallScreen(tester);
    final store = MemoryFeedStore();
    final seed = FakeDashboardServer().repository(store: store);
    await seed.refresh();

    // A day later, no network.
    final offline = FakeDashboardServer()..failure = Exception('no network');
    final repo = offline.repository(store: store, clock: () => DateTime(2026, 10, 21, 8, 0));
    await tester.pumpWidget(_page(repo, _Taps()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dash-stale')), findsOneWidget);
    expect(find.text('Offline copy'), findsOneWidget);
    expect(find.textContaining('2026-10-20 14:05'), findsOneWidget);
    expect(_in('dash-processing', find.text('4')), findsOneWidget);
    expect(find.text(r'450.00 $'), findsOneWidget);
  });

  testWidgets('first load failing with nothing saved shows a message, not an empty dashboard', (tester) async {
    final repo = (FakeDashboardServer()..failure = Exception('offline')).repository();
    await tester.pumpWidget(_page(repo, _Taps()));
    await tester.pumpAndSettle();
    expect(find.text('Could not load the dashboard. Pull down to try again.'), findsOneWidget);
    expect(find.text('Offline copy'), findsOneWidget);
    expect(find.text('Needs attention'), findsNothing);
  });

  testWidgets('a warehouse account sees stock only: no sales, no order cards', (tester) async {
    tallScreen(tester);
    final server = FakeDashboardServer()
      ..answer = bootstrapAnswer(without: {'sales', 'sales2x', 'recentOrders', 'onHold', 'processing'});
    await tester.pumpWidget(_page(server.repository(), _Taps()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dash-outofstock')), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-lowstock')), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-processing')), findsNothing);
    expect(find.byKey(const ValueKey('dash-onhold')), findsNothing);
    expect(find.text('Sales'), findsNothing);
    expect(find.text('Recent orders'), findsNothing);
    expect(find.byType(SegmentedButton<int>), findsNothing);
  });

  testWidgets('an orders-only account sees no stock cards', (tester) async {
    tallScreen(tester);
    final server = FakeDashboardServer()
      ..answer = bootstrapAnswer(without: {'stock', 'stats', 'sales', 'sales2x'});
    await tester.pumpWidget(_page(server.repository(), _Taps()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dash-processing')), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-outofstock')), findsNothing);
    expect(find.byKey(const ValueKey('dash-lowstock')), findsNothing);
    expect(find.text('Sales'), findsNothing);
    expect(find.text('Recent orders'), findsOneWidget);
  });

  testWidgets('no access: the server said 403', (tester) async {
    final server = FakeDashboardServer()..failure = const ApiError(status: 403, code: 'yazan_forbidden');
    await tester.pumpWidget(_page(server.repository(), _Taps()));
    await tester.pumpAndSettle();
    expect(find.text('No access'), findsOneWidget);
    expect(find.textContaining('view the dashboard'), findsOneWidget);
    expect(find.text('Needs attention'), findsNothing);
  });

  testWidgets('no access: the server returned no section at all', (tester) async {
    final server = FakeDashboardServer()..answer = {'days': 30};
    await tester.pumpWidget(_page(server.repository(), _Taps()));
    await tester.pumpAndSettle();
    expect(find.text('No access'), findsOneWidget);
  });

  testWidgets('tapping a card opens the tab it belongs to', (tester) async {
    tallScreen(tester);
    final taps = _Taps();
    await tester.pumpWidget(_page(FakeDashboardServer().repository(), taps));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dash-processing')));
    await tester.tap(find.byKey(const ValueKey('dash-onhold')));
    await tester.tap(find.byKey(const ValueKey('dash-recent-1005')));
    expect(taps.orders, ['processing', 'on-hold', null]);
    expect(taps.products, 0);

    await tester.tap(find.byKey(const ValueKey('dash-outofstock')));
    await tester.tap(find.byKey(const ValueKey('dash-lowstock')));
    expect(taps.products, 2);
    expect(taps.orders, hasLength(3));
  });

  testWidgets('new orders: an alert card that opens Orders and clears itself', (tester) async {
    tallScreen(tester);
    final server = FakeDashboardServer();
    final repo = server.repository();
    await repo.refresh(); // seeds the baseline
    server.alerts = alertsAnswer(count: 2, latest: 1007);
    final taps = _Taps();
    await tester.pumpWidget(_page(repo, taps));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dash-alerts')), findsOneWidget);
    expect(find.text('New orders: 2'), findsOneWidget);
    expect(find.text('Order #1007  Customer 0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dash-alerts')));
    await tester.pumpAndSettle();
    expect(taps.orders, [null]);
    expect(find.byKey(const ValueKey('dash-alerts')), findsNothing);
  });

  testWidgets('no alert card when nothing is new', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(FakeDashboardServer().repository(), _Taps()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dash-alerts')), findsNothing);
  });

  testWidgets('pull to refresh asks the server again', (tester) async {
    tallScreen(tester);
    final server = FakeDashboardServer();
    await tester.pumpWidget(_page(server.repository(), _Taps()));
    await tester.pumpAndSettle();
    expect(server.daysAsked, hasLength(1));

    server.answer = bootstrapAnswer(processing: 9);
    // Same entry point the pull gesture uses; a synthetic drag is flaky across platforms.
    await tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pumpAndSettle();
    expect(server.daysAsked, hasLength(2));
    expect(_in('dash-processing', find.text('9')), findsOneWidget);
  });

  testWidgets('the period buttons ask for that window', (tester) async {
    tallScreen(tester);
    final server = FakeDashboardServer();
    await tester.pumpWidget(_page(server.repository(), _Taps()));
    await tester.pumpAndSettle();
    expect(find.text('7 days'), findsOneWidget);
    expect(find.text('30 days'), findsOneWidget);
    expect(find.text('90 days'), findsOneWidget);

    server.answer = bootstrapAnswer(days: 90);
    await tester.tap(find.text('90 days'));
    await tester.pumpAndSettle();
    expect(server.daysAsked, [30, 90]);
    expect(_in('dash-net', find.textContaining('vs previous 90 days')), findsOneWidget);
  });

  testWidgets('Arabic: wording, right-to-left, Latin digits', (tester) async {
    tallScreen(tester);
    final repo = FakeDashboardServer().repository();
    await tester.pumpWidget(_page(repo, _Taps(), locale: const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.text('يحتاج إلى انتباهك'), findsOneWidget);
    expect(find.text('طلبات بانتظار التجهيز'), findsOneWidget);
    expect(find.text('طلبات معلّقة'), findsOneWidget);
    expect(find.text('نفد من المخزون'), findsOneWidget);
    expect(find.textContaining('مخزون منخفض'), findsOneWidget);
    expect(find.text('المبيعات'), findsOneWidget);
    expect(find.text('صافي الإيرادات'), findsOneWidget);
    expect(find.text('أحدث الطلبات'), findsOneWidget);
    expect(find.textContaining('آخر تحديث'), findsOneWidget);
    expect(find.text('30 يوم'), findsOneWidget);
    expect(_in('dash-processing', find.text('4')), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byKey(const ValueKey('dash-processing')))),
      TextDirection.rtl,
    );
  });

  testWidgets('Arabic: no access', (tester) async {
    final server = FakeDashboardServer()..failure = const ApiError(status: 403, code: 'yazan_forbidden');
    await tester.pumpWidget(_page(server.repository(), _Taps(), locale: const Locale('ar')));
    await tester.pumpAndSettle();
    expect(find.textContaining('لوحة التحكم'), findsOneWidget);
  });
}
