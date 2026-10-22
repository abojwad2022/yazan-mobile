import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/more/staff_permissions.dart';
import 'package:yazan_admin/src/orders/order_detail_controller.dart';
import 'package:yazan_admin/src/orders/order_detail_page.dart';
import 'package:yazan_admin/src/orders/order_refund.dart';
import 'package:yazan_admin/src/orders/order_summary.dart';
import 'package:yazan_admin/src/security/app_lock_controller.dart';
import 'package:yazan_admin/src/security/app_lock_scope.dart';
import 'package:yazan_admin/src/security/lock_settings_store.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../security/fake_gate.dart';
import 'fakes.dart';

final _summary = OrderSummary.fromJson(const {
  'id': 1001,
  'number': '1001',
  'status': 'processing',
  'total': '129.50',
  'currency': 'USD',
  'items': 2,
  'name': 'Sara Ali',
  'version': 'feed-v',
});

final StaffPermissions _canRefund = StaffPermissions.of(const ['orders.view', 'orders.refund']);

const String _reason = 'Confirm it is you to refund this order';
const String _offline =
    'No answer from the store, so the refund may not have been made. Nothing was saved on the phone. '
    'Try again sends the same request, so the order is never refunded twice.';

/// The app as it runs: the lock scope above the navigator, so the page, sheet and dialogs sit under it.
Widget _host(
  AppLockController lock,
  FakeRefundServer server,
  OutboxStore outbox, {
  StaffPermissions? permissions,
  Locale locale = const Locale('en'),
}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppLockScope(controller: lock, active: true, child: child!),
      home: OrderDetailPage(
        summary: _summary,
        accountId: 'acct',
        load: server.load,
        sendStatus: server.sendStatus,
        sync: SyncEngine(store: outbox, send: server.sendOp),
        newKey: KeySeq().next,
        sendRefund: server.sendRefund,
        permissions: permissions ?? _canRefund,
      ),
    );

Future<AppLockController> _unlockedLock(FakeBiometricGate gate) async {
  final lock = AppLockController(gate: gate, settings: MemoryLockSettingsStore());
  await lock.init();
  lock.markUnlocked();
  return lock;
}

void _tallView(WidgetTester t) {
  t.view.physicalSize = const Size(1000, 2400);
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

/// Opens the sheet, types [amount] (and [reason]) and presses Continue.
Future<void> _fillSheet(WidgetTester t, {String? amount, String reason = ''}) async {
  await _tap(t, const ValueKey('refund-start'));
  if (amount != null) {
    await t.enterText(find.byKey(const ValueKey('refund-amount-field')), amount);
    await t.pump();
  }
  if (reason.isNotEmpty) {
    await t.enterText(find.byKey(const ValueKey('refund-reason-field')), reason);
    await t.pump();
  }
  await _tap(t, const ValueKey('refund-continue'));
}

/// Sheet + confirmation; the identity check follows.
Future<void> _refund(WidgetTester t, {String? amount, String reason = ''}) async {
  await _fillSheet(t, amount: amount, reason: reason);
  await _tap(t, const ValueKey('refund-confirm'));
}

String? _textOf(WidgetTester t, String key) => t.widget<Text>(find.byKey(ValueKey(key))).data;

void main() {
  group('permission', () {
    testWidgets('without orders.refund there is no Refund button', (t) async {
      _tallView(t);
      final server = FakeRefundServer();
      final lock = await _unlockedLock(FakeBiometricGate(fallback: true));
      await t.pumpWidget(_host(lock, server, MemoryOutboxStore(),
          permissions: StaffPermissions.of(const ['orders.view'])));
      await _frames(t);
      expect(find.byKey(const ValueKey('refund-start')), findsNothing);
    });

    testWidgets('unknown permissions keep the Refund button hidden', (t) async {
      _tallView(t);
      final server = FakeRefundServer();
      final lock = await _unlockedLock(FakeBiometricGate(fallback: true));
      await t.pumpWidget(_host(lock, server, MemoryOutboxStore(),
          permissions: const StaffPermissions.unknown()));
      await _frames(t);
      expect(find.byKey(const ValueKey('refund-start')), findsNothing);
    });

    testWidgets('with orders.refund the button shows', (t) async {
      _tallView(t);
      final server = FakeRefundServer();
      final lock = await _unlockedLock(FakeBiometricGate(fallback: true));
      await t.pumpWidget(_host(lock, server, MemoryOutboxStore()));
      await _frames(t);
      expect(find.byKey(const ValueKey('refund-start')), findsOneWidget);
      expect(find.text('Up to 129.50 USD can still be refunded.'), findsOneWidget);
    });

    testWidgets('a fully refunded order shows its refunds and no button', (t) async {
      _tallView(t);
      final server = FakeRefundServer()
        ..remaining = '0.00'
        ..refunds.add({'id': 9, 'amount': '129.50', 'reason': '', 'date': '2026-10-01', 'by': 'Sara'});
      final lock = await _unlockedLock(FakeBiometricGate(fallback: true));
      await t.pumpWidget(_host(lock, server, MemoryOutboxStore()));
      await _frames(t);
      expect(find.byKey(const ValueKey('refund-start')), findsNothing);
      expect(find.byKey(const ValueKey('refund-full')), findsOneWidget);
      expect(find.text('−129.50 USD'), findsOneWidget);
    });
  });

  group('local checks', () {
    testWidgets('more than the remaining amount is refused in the sheet; nothing is sent', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(fallback: true);
      final server = FakeRefundServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), server, MemoryOutboxStore()));
      await _frames(t);

      await _fillSheet(t, amount: '200');
      expect(_textOf(t, 'refund-amount-error'), 'The most you can refund on this order is 129.50 USD.');
      // Still on the sheet: no confirmation, no check, no request.
      expect(find.byKey(const ValueKey('refund-continue')), findsOneWidget);
      expect(find.byKey(const ValueKey('refund-confirm')), findsNothing);
      expect(gate.authCalls, 0);
      expect(server.refundCalls, isEmpty);
    });

    testWidgets('zero is refused in the sheet', (t) async {
      _tallView(t);
      final server = FakeRefundServer();
      await t.pumpWidget(_host(await _unlockedLock(FakeBiometricGate(fallback: true)), server, MemoryOutboxStore()));
      await _frames(t);
      await _fillSheet(t, amount: '0');
      expect(_textOf(t, 'refund-amount-error'), 'Enter an amount greater than zero.');
      expect(server.refundCalls, isEmpty);
    });

    test('the controller refuses over-refunds and missing permission without a request', () async {
      final server = FakeRefundServer()..remaining = '40.00';
      final c = OrderDetailController(
        orderId: 1001,
        accountId: 'acct',
        initialStatus: 'processing',
        fallbackVersion: 'feed-v',
        load: server.load,
        sendStatus: server.sendStatus,
        sync: SyncEngine(store: MemoryOutboxStore(), send: server.sendOp),
        sendRefund: server.sendRefund,
        permissions: _canRefund,
        newKey: KeySeq().next,
      );
      await c.load();
      expect(await c.refund(const RefundDraft(amount: '40.01')), RefundResult.tooMuch);
      expect(await c.refund(const RefundDraft(amount: 'abc')), RefundResult.invalid);
      expect(await c.refund(const RefundDraft(amount: '10', viaGateway: true)), RefundResult.invalid);
      expect(server.refundCalls, isEmpty);

      final noPerm = OrderDetailController(
        orderId: 1001,
        accountId: 'acct',
        initialStatus: 'processing',
        fallbackVersion: 'feed-v',
        load: server.load,
        sendStatus: server.sendStatus,
        sync: SyncEngine(store: MemoryOutboxStore(), send: server.sendOp),
        sendRefund: server.sendRefund,
        permissions: StaffPermissions.of(const ['orders.view']),
      );
      await noPerm.load();
      expect(noPerm.canRefund, isFalse);
      expect(await noPerm.refund(const RefundDraft(amount: '10')), RefundResult.noAccess);
      expect(server.refundCalls, isEmpty);
      c.dispose();
      noPerm.dispose();
    });

    test('amount checks work in minor units and accept Arabic-Indic digits', () {
      expect(checkRefundAmount('129.50', '129.5'), RefundAmountCheck.ok);
      expect(checkRefundAmount('129.51', '129.50'), RefundAmountCheck.tooMuch);
      expect(checkRefundAmount('١٢٫٥٠', '129.50'), RefundAmountCheck.ok);
      expect(canonicalRefundAmount('١٢٫٥'), '12.50');
      expect(checkRefundAmount('-1', '129.50'), RefundAmountCheck.invalid);
      expect(checkRefundAmount('', '129.50'), RefundAmountCheck.invalid);
    });
  });

  group('identity check', () {
    testWidgets('a refused check sends nothing and shows no error', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [false]);
      final server = FakeRefundServer();
      final outbox = MemoryOutboxStore();
      await t.pumpWidget(_host(await _unlockedLock(gate), server, outbox));
      await _frames(t);

      await _refund(t, amount: '50');
      expect(gate.authCalls, 1);
      expect(gate.reasons.single, _reason);
      expect(server.refundCalls, isEmpty);
      expect(find.byKey(const ValueKey('refund-message')), findsNothing);
      expect(await outbox.all('acct'), isEmpty);
    });

    testWidgets('cancelling the confirmation never asks for the check', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(fallback: true);
      final server = FakeRefundServer();
      await t.pumpWidget(_host(await _unlockedLock(gate), server, MemoryOutboxStore()));
      await _frames(t);

      await _fillSheet(t, amount: '50');
      await t.tap(find.text('Cancel'));
      await _frames(t);
      expect(gate.authCalls, 0);
      expect(server.refundCalls, isEmpty);
    });

    testWidgets('an accepted check sends the refund once, with a key and If-Match, then refreshes',
        (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true]);
      final server = FakeRefundServer();
      final outbox = MemoryOutboxStore();
      await t.pumpWidget(_host(await _unlockedLock(gate), server, outbox));
      await _frames(t);
      final loadsBefore = server.loads;

      await _refund(t, amount: '50', reason: 'Scratched band');
      expect(gate.authCalls, 1);
      final call = server.refundCalls.single;
      expect(call.key, 'key-1');
      expect(call.version, 'v1');
      expect(call.body, {
        'amount': '50.00',
        'reason': 'Scratched band',
        'restock': false,
        'refund_payment': false,
      });
      expect(server.loads, greaterThan(loadsBefore));
      expect(find.text('Manual refund recorded.'), findsOneWidget);
      expect(find.text('Up to 79.50 USD can still be refunded.'), findsOneWidget);
      expect(find.text('−50.00 USD'), findsOneWidget);
      expect(await outbox.all('acct'), isEmpty);
    });
  });

  group('lost answer', () {
    testWidgets('offline: nothing is queued, Try again re-checks and reuses the key', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true, true]);
      final server = FakeRefundServer()..refundFailures.addAll([Exception('lost'), null]);
      final outbox = MemoryOutboxStore();
      await t.pumpWidget(_host(await _unlockedLock(gate), server, outbox));
      await _frames(t);

      await _refund(t, amount: '50');
      expect(server.refundCalls, hasLength(1));
      expect(_textOf(t, 'refund-message'), _offline);
      expect(await outbox.all('acct'), isEmpty);
      // No second refund can be started while this one is open.
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('refund-start'))).onPressed, isNull);

      await _tap(t, const ValueKey('refund-retry'));
      expect(gate.authCalls, 2);
      expect(gate.reasons, [_reason, _reason]);
      expect(server.refundCalls, hasLength(2));
      expect(server.refundCalls[1].key, server.refundCalls[0].key);
      expect(server.refundCalls[1].version, server.refundCalls[0].version);
      expect(server.refundCalls[1].body, server.refundCalls[0].body);
      expect(find.text('Manual refund recorded.'), findsOneWidget);
      expect(find.byKey(const ValueKey('refund-message')), findsNothing);
    });

    testWidgets('a refused check on Try again resends nothing and keeps the button', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true, false]);
      final server = FakeRefundServer()..refundFailures.addAll([Exception('lost'), null]);
      await t.pumpWidget(_host(await _unlockedLock(gate), server, MemoryOutboxStore()));
      await _frames(t);

      await _refund(t, amount: '50');
      await _tap(t, const ValueKey('refund-retry'));
      expect(gate.authCalls, 2);
      expect(server.refundCalls, hasLength(1));
      expect(_textOf(t, 'refund-message'), _offline);
      expect(find.byKey(const ValueKey('refund-retry')), findsOneWidget);
    });

    testWidgets('a busy answer keeps the same key for later', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true, true]);
      final server = FakeRefundServer()
        ..refundFailures.addAll([
          const ApiError(status: 409, code: 'yazan_idempotency_busy', retryAfter: 2),
          null,
        ]);
      await t.pumpWidget(_host(await _unlockedLock(gate), server, MemoryOutboxStore()));
      await _frames(t);

      await _refund(t, amount: '50');
      expect(_textOf(t, 'refund-message'), 'The store is still processing this refund. Try again in a moment.');
      await _tap(t, const ValueKey('refund-retry'));
      expect(server.refundCalls.map((c) => c.key), ['key-1', 'key-1']);
    });
  });

  group('server refusals', () {
    testWidgets('a 4xx shows the server message as plain text and offers no retry', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true]);
      final server = FakeRefundServer()
        ..refundFailures.add(const ApiError(
          status: 400,
          code: 'yazan_amount_too_high',
          message: r'That is more than the <span class="amount">$12.00</span> still refundable on this order.',
        ));
      await t.pumpWidget(_host(await _unlockedLock(gate), server, MemoryOutboxStore()));
      await _frames(t);

      await _refund(t, amount: '50');
      expect(server.refundCalls, hasLength(1));
      expect(_textOf(t, 'refund-message'), r'That is more than the $12.00 still refundable on this order.');
      expect(find.byKey(const ValueKey('refund-retry')), findsNothing);
      // The attempt is closed: a new refund can be started.
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('refund-start'))).onPressed, isNotNull);
    });

    testWidgets('a gateway failure is shown verbatim', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true]);
      final server = FakeRefundServer()
        ..gatewaySupported = true
        ..canGateway = true
        ..refundFailures.add(const ApiError(
          status: 400,
          code: 'yazan_refund_failed',
          message: 'The card issuer declined the refund &amp; asked to retry later.',
        ));
      await t.pumpWidget(_host(await _unlockedLock(gate), server, MemoryOutboxStore()));
      await _frames(t);

      await _tap(t, const ValueKey('refund-start'));
      await _tap(t, const ValueKey('refund-gateway'));
      await _tap(t, const ValueKey('refund-continue'));
      await _tap(t, const ValueKey('refund-confirm'));
      // Money through the gateway gets a second, explicit confirmation.
      expect(gate.authCalls, 0);
      await _tap(t, const ValueKey('refund-confirm-gateway'));
      expect(gate.authCalls, 1);
      expect(server.refundCalls.single.body['refund_payment'], isTrue);
      expect(server.refundCalls.single.body['amount'], '129.50');
      expect(_textOf(t, 'refund-message'), 'The card issuer declined the refund & asked to retry later.');
    });

    testWidgets('a 412 reloads the order and asks to start again (ar)', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true]);
      final server = FakeRefundServer()
        ..refundFailures.add(const ApiError(status: 412, code: 'yazan_precondition_failed', current: 'v2'));
      await t.pumpWidget(_host(await _unlockedLock(gate), server, MemoryOutboxStore(), locale: const Locale('ar')));
      await _frames(t);
      expect(Directionality.of(t.element(find.byKey(const ValueKey('refund-start')))), TextDirection.rtl);

      final loadsBefore = server.loads;
      await _refund(t, amount: '10');
      expect(server.loads, greaterThan(loadsBefore));
      expect(
        _textOf(t, 'refund-message'),
        'تغيّر هذا الطلب منذ فتحته، فلم يُسترد شيء. راجع المبالغ وابدأ الاسترداد من جديد.',
      );
      expect(find.byKey(const ValueKey('refund-retry')), findsNothing);
    });

    testWidgets('a 403 shows the no-permission message', (t) async {
      _tallView(t);
      final gate = FakeBiometricGate(results: [true]);
      final server = FakeRefundServer()
        ..refundFailures.add(const ApiError(status: 403, code: 'yazan_suspended'));
      await t.pumpWidget(_host(await _unlockedLock(gate), server, MemoryOutboxStore()));
      await _frames(t);

      await _refund(t, amount: '10');
      expect(_textOf(t, 'refund-message'), 'You do not have permission to refund this order.');
      expect(find.byKey(const ValueKey('refund-retry')), findsNothing);
    });
  });
}
