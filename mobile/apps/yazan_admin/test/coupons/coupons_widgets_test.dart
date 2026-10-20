import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/coupons/coupon_detail_page.dart';
import 'package:yazan_admin/src/coupons/coupon_summary.dart';
import 'package:yazan_admin/src/coupons/coupons_list_page.dart';
import 'package:yazan_admin/src/coupons/coupons_page.dart';
import 'package:yazan_admin/src/coupons/coupons_repository.dart';
import 'package:yazan_admin/src/more/staff_permissions.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../customers/fakes.dart' show customersHost, customersMe;
import 'fakes.dart';

CouponsRepository _repo({Object? fail, List<String>? permissions, FeedStore? store}) {
  return CouponsRepository(
    store: store,
    fetch: (_) async {
      if (fail != null) throw fail;
      return couponsPage(couponRows);
    },
    loadPermissions: permissions == null ? null : () async => customersMe(permissions),
  );
}

CouponDetailPage _detail(FakeCouponServer server, {List<String> slugs = const ['coupons.view', 'coupons.edit'], VoidCallback? onChanged}) {
  var n = 0;
  return CouponDetailPage(
    summary: CouponSummary.fromJson(couponRows[0]),
    load: server.loader,
    write: server.writer,
    permissions: StaffPermissions.of(slugs),
    newKey: () => 'key-${++n}',
    clock: () => DateTime(2026, 10, 20, 15),
    onChanged: onChanged,
  );
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('confirm-change')));
  await tester.pumpAndSettle();
}

void main() {
  group('list', () {
    testWidgets('renders in English with the Active / Expired badge and usage', (tester) async {
      await tester.pumpWidget(customersHost(
        const Locale('en'),
        CouponsListPage(repository: _repo(), onOpen: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('SPRING20'), findsOneWidget);
      expect(find.text('20% · Used 3 of 10'), findsOneWidget);
      expect(find.text('Expires 2099-12-31'), findsOneWidget);
      expect(find.text(r'$5.00 · Used 40'), findsOneWidget);
      expect(find.text('No expiry'), findsOneWidget);
      expect(find.byKey(const ValueKey('coupon-badge-21')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('coupon-badge-21'))).data, 'Active');
      expect(tester.widget<Text>(find.byKey(const ValueKey('coupon-badge-22'))).data, 'Expired');
    });

    testWidgets('renders right-to-left in Arabic', (tester) async {
      await tester.pumpWidget(customersHost(
        const Locale('ar'),
        CouponsListPage(repository: _repo(), onOpen: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('coupon-badge-22'))).data, 'منتهي');
      expect(tester.widget<Text>(find.byKey(const ValueKey('coupon-badge-21'))).data, 'فعّال');
      expect(find.text('20% · استُخدم 3 من 10'), findsOneWidget);
      expect(find.text('بلا تاريخ انتهاء'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('SPRING20'))), TextDirection.rtl);
    });

    testWidgets('search narrows the list and says when nothing matches', (tester) async {
      await tester.pumpWidget(customersHost(
        const Locale('en'),
        CouponsListPage(repository: _repo(), onOpen: (_) {}),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('coupon-search')), 'old');
      await tester.pumpAndSettle();
      expect(find.text('OLD5'), findsOneWidget);
      expect(find.text('SPRING20'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('coupon-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No coupon matches “zzz”.'), findsOneWidget);
    });

    testWidgets('a failed refresh shows the cached list with the offline badge', (tester) async {
      final store = MemoryFeedStore();
      await _repo(store: store).refresh();
      await tester.pumpWidget(customersHost(
        const Locale('en'),
        CouponsListPage(repository: _repo(fail: Exception('offline'), store: store), onOpen: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('SPRING20'), findsOneWidget);
      expect(find.text('Offline copy'), findsOneWidget);
    });

    testWidgets('an empty cache and a failed refresh says so', (tester) async {
      await tester.pumpWidget(customersHost(
        const Locale('en'),
        CouponsListPage(repository: _repo(fail: Exception('offline')), onOpen: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Could not load coupons. Pull down to try again.'), findsOneWidget);
    });

    testWidgets('no coupons.view in the permission map shows the lock', (tester) async {
      await tester.pumpWidget(customersHost(
        const Locale('en'),
        CouponsListPage(repository: _repo(permissions: ['orders.view']), onOpen: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No access'), findsOneWidget);
      expect(find.byKey(const ValueKey('coupon-search')), findsNothing);
    });

    testWidgets('tapping a row opens it', (tester) async {
      CouponSummary? opened;
      await tester.pumpWidget(customersHost(
        const Locale('en'),
        CouponsListPage(repository: _repo(), onOpen: (c) => opened = c),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('coupon-22')));
      expect(opened?.code, 'OLD5');
    });
  });

  group('detail', () {
    testWidgets('shows the coupon and the online-only note (en)', (tester) async {
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(FakeCouponServer())));
      await tester.pumpAndSettle();
      expect(find.text('Percentage: 20%'), findsOneWidget);
      expect(find.text('2099-12-31'), findsOneWidget);
      expect(find.text('Used 3 of 10'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Coupon changes need a connection and are never saved offline.'), findsOneWidget);
      expect(find.text('Expire now'), findsOneWidget);
    });

    testWidgets('is right-to-left in Arabic', (tester) async {
      await tester.pumpWidget(customersHost(const Locale('ar'), _detail(FakeCouponServer())));
      await tester.pumpAndSettle();
      expect(find.text('نسبة مئوية: 20%'), findsOneWidget);
      expect(find.text('إنهاء الآن'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('فعّال'))), TextDirection.rtl);
    });

    testWidgets('changing the amount asks for confirmation, then sends one write', (tester) async {
      final server = FakeCouponServer();
      var changed = 0;
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server, onChanged: () => changed++)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('coupon-edit-amount')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('coupon-amount-field')), '25');
      await tester.tap(find.byKey(const ValueKey('coupon-amount-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Set the discount of “SPRING20” to 25.00%'), findsOneWidget);
      expect(server.writes, isEmpty); // nothing before the confirmation
      await _confirm(tester);

      expect(server.writes.single.fields, {'amount': '25.00'});
      expect(server.writes.single.key, 'key-1');
      expect(changed, 1);
      expect(find.text('Used 3 of 10'), findsOneWidget);
      expect(find.text('Percentage: 25.00%'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      final server = FakeCouponServer();
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('coupon-edit-amount')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('coupon-amount-field')), '25');
      await tester.tap(find.byKey(const ValueKey('coupon-amount-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.writes, isEmpty);
    });

    testWidgets('a percentage over 100 is refused in the dialog', (tester) async {
      final server = FakeCouponServer();
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('coupon-edit-amount')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('coupon-amount-field')), '150');
      await tester.tap(find.byKey(const ValueKey('coupon-amount-save')));
      await tester.pumpAndSettle();
      expect(find.text('A percentage cannot be more than 100.'), findsOneWidget);
      expect(server.writes, isEmpty);
    });

    testWidgets('changing the expiry sends the date', (tester) async {
      final server = FakeCouponServer();
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('coupon-edit-expiry')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('coupon-expiry-field')), '2027-03-01');
      await tester.tap(find.byKey(const ValueKey('coupon-expiry-save')));
      await tester.pumpAndSettle();
      await _confirm(tester);
      expect(server.writes.single.fields, {'date_expires': '2027-03-01'});
      expect(find.text('2027-03-01'), findsOneWidget);
    });

    testWidgets('a bad date is refused in the dialog', (tester) async {
      final server = FakeCouponServer();
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('coupon-edit-expiry')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('coupon-expiry-field')), '2027-02-31');
      await tester.tap(find.byKey(const ValueKey('coupon-expiry-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a date like 2026-12-31, or leave it empty.'), findsOneWidget);
      expect(server.writes, isEmpty);
    });

    testWidgets('Expire now stops the coupon, then the button offers to remove the expiry', (tester) async {
      final server = FakeCouponServer();
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('coupon-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Stop “SPRING20” now?'), findsOneWidget);
      await _confirm(tester);
      expect(server.writes.single.fields, {'date_expires': '2026-10-20'});
      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Remove expiry'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('coupon-toggle')));
      await tester.pumpAndSettle();
      await _confirm(tester);
      expect(server.writes.last.fields, {'date_expires': ''});
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('offline shows a message and Try again resends under the same key', (tester) async {
      final server = FakeCouponServer()..writeFailures.add(Exception('offline'));
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('coupon-toggle')));
      await tester.pumpAndSettle();
      await _confirm(tester);
      expect(find.byKey(const ValueKey('edit-message')), findsOneWidget);
      expect(find.text('No connection. Nothing was changed. Try again when you are online.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('edit-retry')));
      await tester.pumpAndSettle();
      expect(server.writes.map((w) => w.key), ['key-1', 'key-1']);
      expect(find.byKey(const ValueKey('edit-message')), findsNothing);
    });

    testWidgets('a viewer without coupons.edit sees no change buttons', (tester) async {
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(FakeCouponServer(), slugs: ['coupons.view'])));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('coupon-edit-amount')), findsNothing);
      expect(find.byKey(const ValueKey('coupon-toggle')), findsNothing);
      expect(find.text('Your account can view this coupon but not change it.'), findsOneWidget);
    });

    testWidgets('a 403 on load shows the no-access view', (tester) async {
      final server = FakeCouponServer()..loadError = const ApiError(status: 403, code: 'rest_forbidden');
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server)));
      await tester.pumpAndSettle();
      expect(find.text('No access'), findsOneWidget);
    });
  });

  testWidgets('CouponsPage lists the coupons and opens one', (tester) async {
    final server = FakeCouponServer();
    await tester.pumpWidget(customersHost(
      const Locale('en'),
      CouponsPage(
        repository: _repo(permissions: ['coupons.view', 'coupons.edit']),
        load: server.loader,
        write: server.writer,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Coupons'), findsOneWidget); // app bar
    await tester.tap(find.byKey(const ValueKey('coupon-21')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('coupon-edit-amount')), findsOneWidget);
  });
}
