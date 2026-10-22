import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/coupons/coupon_detail_page.dart';
import 'package:yazan_admin/src/coupons/coupon_summary.dart';
import 'package:yazan_admin/src/more/staff_permissions.dart';
import 'package:yazan_admin/src/products/product_detail_page.dart';
import 'package:yazan_admin/src/products/product_permissions.dart';
import 'package:yazan_admin/src/products/product_summary.dart';
import 'package:yazan_admin/src/security/app_lock_controller.dart';
import 'package:yazan_admin/src/security/app_lock_scope.dart';
import 'package:yazan_admin/src/security/lock_settings_store.dart';
import 'package:yazan_admin/src/users/staff_detail_page.dart';
import 'package:yazan_admin/src/users/staff_member.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../coupons/fakes.dart';
import '../orders/fakes.dart' show KeySeq;
import '../products/fakes.dart';
import '../users/fakes.dart';
import 'fake_gate.dart';

final ProductSummary _product = ProductSummary.fromJson(const {
  'id': 7,
  'type': 'simple',
  'name': 'Agate Ring',
  'sku': 'YZ-100',
  'price': '120.00',
  'regular_price': '120.00',
  'sale_price': '',
  'stock_status': 'instock',
  'stock': 3,
});

/// The app as it runs: the lock scope above the navigator, so pages and dialogs sit under it.
Widget _host(AppLockController lock, Widget home) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppLockScope(controller: lock, active: true, child: child!),
      home: home,
    );

/// A lock that is on and already unlocked (signed in, nothing to prompt at start).
Future<AppLockController> _unlockedLock(FakeBiometricGate gate) async {
  final lock = AppLockController(gate: gate, settings: MemoryLockSettingsStore());
  await lock.init();
  lock.markUnlocked();
  return lock;
}

void _tallView(WidgetTester t) {
  t.view.physicalSize = const Size(1000, 2200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

/// Fixed frames instead of pumpAndSettle: a "sending" spinner may be on screen.
Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _tap(WidgetTester t, Key key) async {
  await t.ensureVisible(find.byKey(key));
  await t.pump();
  await t.tap(find.byKey(key));
  await _frames(t);
}

Future<void> _tapText(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text));
  await t.pump();
  await t.tap(find.text(text));
  await _frames(t);
}

const String _offlineText =
    'This needs a connection. Nothing was saved on the phone; try again when you are online.';
const ApiError _stale = ApiError(status: 412, code: 'yazan_precondition_failed', current: 'v2');

Future<void> _enter(WidgetTester t, String key, String text) async {
  await t.enterText(find.byKey(ValueKey(key)), text);
  await t.pump();
}

// ---- products ----------------------------------------------------------------------------------

Widget _productPage(FakeProductServer server) => ProductDetailPage(
      summary: _product,
      load: server.load,
      write: server.write,
      permissions: ProductPermissions.of(allProductPermissions),
      newKey: KeySeq().next,
    );

Future<void> _changePrice(WidgetTester t) async {
  await _tap(t, const ValueKey('edit-price'));
  await _enter(t, 'regular-price-field', '150');
  await _tap(t, const ValueKey('price-save'));
  await _tap(t, const ValueKey('confirm-change'));
}

Future<void> _changeStock(WidgetTester t) async {
  await _tap(t, const ValueKey('edit-stock'));
  await _enter(t, 'stock-field', '5');
  await _tap(t, const ValueKey('stock-save'));
  await _tap(t, const ValueKey('confirm-change'));
}

// ---- staff -------------------------------------------------------------------------------------

Widget _staffPage(FakeStaffServer server) {
  var n = 0;
  return StaffDetailPage(
    member: StaffMember.fromJson(staffRows[1]),
    loadRoles: server.roles,
    signOut: server.signOut,
    permissions: StaffPermissions.of(const ['users.view', 'roles.view', 'users.force_logout']),
    newKey: () => 'key-${++n}',
  );
}

Future<void> _signOutEverywhere(WidgetTester t) async {
  await _tap(t, const ValueKey('staff-signout'));
  await _tap(t, const ValueKey('confirm-signout'));
}

// ---- coupons -----------------------------------------------------------------------------------

Widget _couponPage(FakeCouponServer server) {
  var n = 0;
  return CouponDetailPage(
    summary: CouponSummary.fromJson(couponRows[0]),
    load: server.loader,
    write: server.writer,
    permissions: StaffPermissions.of(const ['coupons.view', 'coupons.edit']),
    newKey: () => 'key-${++n}',
    clock: () => DateTime(2026, 10, 20, 15),
  );
}

Future<void> _changeCouponAmount(WidgetTester t) async {
  await _tap(t, const ValueKey('coupon-edit-amount'));
  await _enter(t, 'coupon-amount-field', '25');
  await _tap(t, const ValueKey('coupon-amount-save'));
  await _tap(t, const ValueKey('confirm-change'));
}

void main() {
  group('price change', () {
    testWidgets('refused check sends nothing and shows no error', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [false]);
      final server = FakeProductServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), _productPage(server)));
      await _frames(t);

      await _changePrice(t);
      expect(gate.authCalls, 1);
      expect(gate.reasons.single, 'Confirm it is you to change the price');
      expect(server.writes, isEmpty);
      expect(find.byKey(const ValueKey('edit-message')), findsNothing);
      expect(find.byKey(const ValueKey('lock-cover')), findsNothing);
      expect(find.text('120.00'), findsOneWidget);
    });

    testWidgets('accepted check sends the change once', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true]);
      final server = FakeProductServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), _productPage(server)));
      await _frames(t);

      await _changePrice(t);
      expect(gate.authCalls, 1);
      expect(server.writes.single.fields, {'regular_price': '150.00', 'sale_price': ''});
      expect(find.text('Product updated.'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation never asks for the check', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(fallback: true);
      final server = FakeProductServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), _productPage(server)));
      await _frames(t);

      await _tap(t, const ValueKey('edit-price'));
      await _enter(t, 'regular-price-field', '150');
      await _tap(t, const ValueKey('price-save'));
      await t.tap(find.text('Cancel'));
      await _frames(t);
      expect(gate.authCalls, 0);
      expect(server.writes, isEmpty);
    });

    testWidgets('a phone that cannot check lets the change through without asking', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(available: false);
      final server = FakeProductServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), _productPage(server)));
      await _frames(t);
      // The one-time "cannot lock" notice sits on top; dismiss it like the person would.
      await _tap(t, const ValueKey('lock-notice-ok'));

      await _changePrice(t);
      expect(gate.authCalls, 0);
      expect(server.writes, hasLength(1));
    });
  });

  group('stock change', () {
    testWidgets('refused check sends nothing', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [false]);
      final server = FakeProductServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), _productPage(server)));
      await _frames(t);

      await _changeStock(t);
      expect(gate.reasons.single, 'Confirm it is you to change the stock');
      expect(server.writes, isEmpty);
      expect(find.byKey(const ValueKey('edit-message')), findsNothing);
      expect(find.text('In stock: 3'), findsOneWidget);
    });

    testWidgets('accepted check sends the change', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true]);
      final server = FakeProductServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), _productPage(server)));
      await _frames(t);

      await _changeStock(t);
      expect(gate.authCalls, 1);
      expect(server.writes.single.fields, {'stock_quantity': 5, 'original_stock_quantity': 3});
      expect(find.text('In stock: 5'), findsOneWidget);
    });
  });

  group('Try again after a lost answer (product)', () {
    testWidgets('refused check resends nothing and keeps the button', (t) async {
      _tallView(t);
      // First check passes, the send is lost; the check before "Try again" is refused.
      final gate = FakeBiometricGate(results: [true, false]);
      final server = FakeProductServer()..writeFailures.addAll([Exception('offline'), null]);
      await t.pumpWidget(_host(await _unlockedLock(gate), _productPage(server)));
      await _frames(t);

      await _changePrice(t);
      expect(server.writes, hasLength(1));
      expect(find.text(_offlineText), findsOneWidget);

      await _tap(t, const ValueKey('edit-retry'));
      expect(gate.authCalls, 2);
      expect(gate.reasons[1], 'Confirm it is you to change the price');
      expect(server.writes, hasLength(1));
      // The attempt is still open: same message, same button.
      expect(find.text(_offlineText), findsOneWidget);
      expect(find.byKey(const ValueKey('edit-retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('lock-cover')), findsNothing);
      expect(find.text('120.00'), findsOneWidget);
    });

    testWidgets('accepted check resends the same request under the same key', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true, true]);
      final server = FakeProductServer()..writeFailures.addAll([Exception('offline'), null]);
      await t.pumpWidget(_host(await _unlockedLock(gate), _productPage(server)));
      await _frames(t);

      await _changePrice(t);
      await _tap(t, const ValueKey('edit-retry'));
      expect(gate.authCalls, 2);
      expect(server.writes, hasLength(2));
      expect(server.writes[1].key, server.writes[0].key);
      expect(server.writes[1].fields, {'regular_price': '150.00', 'sale_price': ''});
      expect(find.text('Product updated.'), findsOneWidget);
    });

    testWidgets('a stock retry asks with the stock reason', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true, false]);
      final server = FakeProductServer()..writeFailures.addAll([Exception('offline'), null]);
      await t.pumpWidget(_host(await _unlockedLock(gate), _productPage(server)));
      await _frames(t);

      await _changeStock(t);
      await _tap(t, const ValueKey('edit-retry'));
      expect(gate.reasons, [
        'Confirm it is you to change the stock',
        'Confirm it is you to change the stock',
      ]);
      expect(server.writes, hasLength(1));
      expect(find.byKey(const ValueKey('edit-retry')), findsOneWidget);
    });
  });

  group('Overwrite with mine (product conflict)', () {
    Future<void> openConflict(WidgetTester t, FakeProductServer server) async {
      await _tap(t, const ValueKey('edit-price'));
      await _enter(t, 'regular-price-field', '150');
      await _tap(t, const ValueKey('price-save'));
      // Someone changes the price on the website while the confirmation is open.
      server
        ..regular = '200.00'
        ..version = 'v2';
      await _tap(t, const ValueKey('confirm-change'));
      expect(find.text('This product changed'), findsOneWidget);
    }

    testWidgets('refused check sends nothing and keeps the conflict screen', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true, false]);
      final server = FakeProductServer()..writeFailures.add(_stale);
      await t.pumpWidget(_host(await _unlockedLock(gate), _productPage(server)));
      await _frames(t);

      await openConflict(t, server);
      expect(server.writes, hasLength(1));

      await _tapText(t, 'Overwrite with mine');
      expect(gate.authCalls, 2);
      expect(gate.reasons[1], 'Confirm it is you to change the price');
      expect(server.writes, hasLength(1));
      expect(server.regular, '200.00');
      // Still on the conflict screen, both choices still offered.
      expect(find.text('This product changed'), findsOneWidget);
      expect(find.text('Overwrite with mine'), findsOneWidget);
      expect(find.text('Keep server version'), findsOneWidget);
    });

    testWidgets('accepted check sends the change against the server version', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true, true]);
      final server = FakeProductServer()..writeFailures.add(_stale);
      await t.pumpWidget(_host(await _unlockedLock(gate), _productPage(server)));
      await _frames(t);

      await openConflict(t, server);
      await _tapText(t, 'Overwrite with mine');
      expect(gate.authCalls, 2);
      expect(server.writes.map((w) => w.version), ['v1', 'v2']);
      expect(server.writes[1].key, isNot(server.writes[0].key));
      expect(server.writes[1].fields, {'regular_price': '150.00', 'sale_price': ''});
      expect(server.regular, '150.00');
      expect(find.text('This product changed'), findsNothing);
      expect(find.text('Product updated.'), findsOneWidget);
    });
  });

  group('Try again after a lost answer (coupon, staff)', () {
    testWidgets('coupon amount: refused check resends nothing and keeps the button', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true, false]);
      final server = FakeCouponServer()..writeFailures.addAll([Exception('offline'), null]);
      await t.pumpWidget(_host(await _unlockedLock(gate), _couponPage(server)));
      await _frames(t);

      await _changeCouponAmount(t);
      expect(server.writes, hasLength(1));
      await _tap(t, const ValueKey('edit-retry'));
      expect(gate.reasons[1], 'Confirm it is you to change the coupon amount');
      expect(server.writes, hasLength(1));
      expect(find.byKey(const ValueKey('edit-retry')), findsOneWidget);
    });

    testWidgets('coupon amount: accepted check resends under the same key', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true, true]);
      final server = FakeCouponServer()..writeFailures.addAll([Exception('offline'), null]);
      await t.pumpWidget(_host(await _unlockedLock(gate), _couponPage(server)));
      await _frames(t);

      await _changeCouponAmount(t);
      await _tap(t, const ValueKey('edit-retry'));
      expect(gate.authCalls, 2);
      expect(server.writes, hasLength(2));
      expect(server.writes[1].key, server.writes[0].key);
    });

    testWidgets('sign out everywhere: refused check resends nothing and keeps the button', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true, false]);
      final server = FakeStaffServer()..signOutFailures.addAll([Exception('offline'), null]);
      await t.pumpWidget(_host(await _unlockedLock(gate), _staffPage(server)));
      await _frames(t);

      await _signOutEverywhere(t);
      expect(server.signOuts, hasLength(1));
      await _tap(t, const ValueKey('signout-retry'));
      expect(gate.reasons[1], 'Confirm it is you to sign out on all devices');
      expect(server.signOuts, hasLength(1));
      expect(find.byKey(const ValueKey('signout-retry')), findsOneWidget);
    });

    testWidgets('sign out everywhere: accepted check resends under the same key', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true, true]);
      final server = FakeStaffServer()..signOutFailures.addAll([Exception('offline'), null]);
      await t.pumpWidget(_host(await _unlockedLock(gate), _staffPage(server)));
      await _frames(t);

      await _signOutEverywhere(t);
      await _tap(t, const ValueKey('signout-retry'));
      expect(gate.authCalls, 2);
      expect(server.signOuts, hasLength(2));
      expect(find.text('Signed out on all devices.'), findsOneWidget);
    });
  });

  group('sign out on all devices', () {
    testWidgets('refused check sends nothing', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [false]);
      final server = FakeStaffServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), _staffPage(server)));
      await _frames(t);

      await _signOutEverywhere(t);
      expect(gate.reasons.single, 'Confirm it is you to sign out on all devices');
      expect(server.signOuts, isEmpty);
      expect(find.byKey(const ValueKey('signout-message')), findsNothing);
    });

    testWidgets('accepted check sends one request', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true]);
      final server = FakeStaffServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), _staffPage(server)));
      await _frames(t);

      await _signOutEverywhere(t);
      expect(gate.authCalls, 1);
      expect(server.signOuts.single.id, 6);
      expect(find.text('Signed out on all devices.'), findsOneWidget);
    });
  });

  group('coupon amount change', () {
    testWidgets('refused check sends nothing', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [false]);
      final server = FakeCouponServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), _couponPage(server)));
      await _frames(t);

      await _changeCouponAmount(t);
      expect(gate.reasons.single, 'Confirm it is you to change the coupon amount');
      expect(server.writes, isEmpty);
    });

    testWidgets('accepted check sends the change', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true]);
      final server = FakeCouponServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), _couponPage(server)));
      await _frames(t);

      await _changeCouponAmount(t);
      expect(gate.authCalls, 1);
      expect(server.writes.single.fields, {'amount': '25.00'});
    });
  });
}
