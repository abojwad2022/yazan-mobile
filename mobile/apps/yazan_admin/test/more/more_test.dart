import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/app.dart';
import 'package:yazan_admin/src/more/more_page.dart';
import 'package:yazan_admin/src/more/more_registry.dart';
import 'package:yazan_admin/src/more/staff_permissions.dart';
import 'package:yazan_admin/src/storage/admin_stores.dart';
import 'package:yazan_admin/src/sync/observed_sync_engine.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../customers/fakes.dart' show customersHost, customersMe;

YazanApiClient _client(TokenStore t) => YazanApiClient(
      baseUrl: 'https://example.test',
      scope: AppScope.admin,
      deviceId: 'test-device',
      tokens: t,
    );

Future<MemoryTokenStore> _signedIn() async {
  final tokens = MemoryTokenStore();
  await tokens.write(Session.fromJson(
      {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
  return tokens;
}

MoreServices _services() {
  final stores = MemoryAdminStores();
  return MoreServices(
    client: _client(MemoryTokenStore()),
    stores: stores,
    sync: ObservedSyncEngine(store: stores.outbox, send: (op) async {}),
  );
}

final List<MoreEntry> _entries = [
  MoreEntry(
    key: 'free',
    title: (l) => 'Free entry',
    icon: Icons.star_outline,
    builder: (_, __) => const Scaffold(body: Text('free page')),
  ),
  MoreEntry(
    key: 'reports',
    title: (l) => 'Reports entry',
    icon: Icons.bar_chart_outlined,
    permission: 'reports.view',
    builder: (_, __) => const Scaffold(body: Text('reports page')),
  ),
];

void main() {
  test('StaffPermissions: unknown allows, a known map allows only what it lists', () {
    expect(const StaffPermissions.unknown().allows('reports.view'), isTrue);
    expect(StaffPermissions.of(['a']).allows('a'), isTrue);
    expect(StaffPermissions.of(['a']).allows('b'), isFalse);
    expect(StaffPermissions.of(const []).allows(null), isTrue);
    expect(StaffPermissions.fromMe(customersMe(['x'])).allows('x'), isTrue);
    expect(StaffPermissions.fromMe({'permissions': <dynamic>[]}).allows('x'), isFalse);
    expect(StaffPermissions.fromMe(const {}).known, isFalse);
  });

  test('the registry has Coupons and the Sync center, with the coupon permission', () {
    final keys = moreEntries.map((e) => e.key).toList();
    expect(keys, containsAll(['coupons', 'sync']));
    expect(moreEntries.firstWhere((e) => e.key == 'coupons').permission, 'coupons.view');
    expect(moreEntries.firstWhere((e) => e.key == 'sync').permission, isNull);
  });

  testWidgets('tiles the permission map allows are shown; the others are hidden', (tester) async {
    await tester.pumpWidget(customersHost(
      const Locale('en'),
      MorePage(
        entries: _entries,
        services: _services(),
        loadPermissions: () async => customersMe(['orders.view']),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-free')), findsOneWidget);
    expect(find.byKey(const ValueKey('more-reports')), findsNothing);
  });

  testWidgets('a permission that is granted shows its tile and opens its page', (tester) async {
    await tester.pumpWidget(customersHost(
      const Locale('en'),
      MorePage(
        entries: _entries,
        services: _services(),
        loadPermissions: () async => customersMe(['reports.view']),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-reports')));
    await tester.pumpAndSettle();
    expect(find.text('reports page'), findsOneWidget);
  });

  testWidgets('offline (permissions unknown) every tile shows', (tester) async {
    await tester.pumpWidget(customersHost(
      const Locale('en'),
      MorePage(
        entries: _entries,
        services: _services(),
        loadPermissions: () async => throw Exception('offline'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-free')), findsOneWidget);
    expect(find.byKey(const ValueKey('more-reports')), findsOneWidget);
  });

  testWidgets('with nothing allowed it says so, in Arabic too', (tester) async {
    await tester.pumpWidget(customersHost(
      const Locale('ar'),
      MorePage(
        entries: [_entries[1]],
        services: _services(),
        loadPermissions: () async => customersMe(const []),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-empty')), findsOneWidget);
    expect(find.text('لا يتوفر شيء آخر لحسابك.'), findsOneWidget);
  });

  testWidgets('the shell has a More tab that lists Coupons and the Sync center, and opens Coupons (en)',
      (tester) async {
    final tokens = await _signedIn();
    await tester.pumpWidget(YazanApp(client: _client(tokens), tokens: tokens));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tab-more')), findsOneWidget);
    // Built on first use.
    expect(find.byKey(const ValueKey('more-coupons')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('more-coupons')), findsOneWidget);
    expect(find.byKey(const ValueKey('more-sync')), findsOneWidget);
    expect(find.text('Coupons'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('more-coupons')));
    await tester.pumpAndSettle();
    // No network in tests: the list shows its search box and the "could not load" text.
    expect(find.byKey(const ValueKey('coupon-search')), findsOneWidget);
  });

  testWidgets('the More tab is labelled in Arabic and is right-to-left (ar)', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ar')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final tokens = await _signedIn();
    await tester.pumpWidget(YazanApp(client: _client(tokens), tokens: tokens));
    await tester.pumpAndSettle();
    expect(find.text('المزيد'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab-more')));
    await tester.pumpAndSettle();
    expect(find.text('الكوبونات'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byKey(const ValueKey('more-coupons')))),
      TextDirection.rtl,
    );
  });
}
