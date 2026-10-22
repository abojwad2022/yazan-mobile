import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/security/app_lock_controller.dart';
import 'package:yazan_admin/src/security/app_lock_scope.dart';
import 'package:yazan_admin/src/security/biometric_gate.dart';
import 'package:yazan_admin/src/security/lock_settings_store.dart';
import 'package:yazan_admin/src/security/require_unlock_tile.dart';

import 'fake_gate.dart';

bool? confirmed;

void main() {
  late DateTime clock;
  late FakeBiometricGate gate;
  late MemoryLockSettingsStore store;
  late AppLockController lock;

  Future<void> start(WidgetTester t, {bool active = true, Locale? locale}) async {
    lock = AppLockController(gate: gate, settings: store, now: () => clock);
    await lock.init();
    await t.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppLockScope(controller: lock, active: active, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(children: [
            const Text('customers'),
            TextButton(
              key: const ValueKey('refund'),
              onPressed: () async => confirmed = await confirmSensitive(context, 'refund'),
              child: const Text('refund'),
            ),
          ]),
        ),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  Future<void> away(WidgetTester t, Duration d) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    clock = clock.add(d);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    await t.pump();
  }

  final cover = find.byKey(const ValueKey('lock-cover'));
  final unlockButton = find.byKey(const ValueKey('lock-unlock'));

  setUp(() {
    clock = DateTime(2026, 10, 22, 9);
    gate = FakeBiometricGate();
    store = MemoryLockSettingsStore();
    confirmed = null;
  });

  testWidgets('cold start is locked and prompts once; success shows the app', (t) async {
    gate.fallback = true;
    await start(t);
    expect(gate.authCalls, 1);
    expect(cover, findsNothing);
    expect(lock.locked, isFalse);
  });

  testWidgets('short absence covers while away but does not lock', (t) async {
    gate.fallback = true;
    await start(t);
    gate.authCalls = 0;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    expect(cover, findsOneWidget, reason: 'task switcher must not show customers');
    expect(unlockButton, findsNothing);
    clock = clock.add(const Duration(seconds: 30));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(cover, findsNothing);
    expect(gate.authCalls, 0);
  });

  testWidgets('more than 60 s away locks and asks on resume', (t) async {
    gate.fallback = true;
    await start(t);
    gate.authCalls = 0;
    gate.fallback = false;
    gate.results.add(true);
    await away(t, const Duration(seconds: 61));
    expect(gate.authCalls, 1);
    expect(cover, findsNothing);
  });

  testWidgets('exactly the timeout does not lock', (t) async {
    gate.fallback = true;
    await start(t);
    gate.authCalls = 0;
    await away(t, defaultLockTimeout);
    expect(gate.authCalls, 0);
    expect(lock.locked, isFalse);
  });

  testWidgets('failures keep it locked, offer retry, never sign out', (t) async {
    gate.results.addAll([false, false, true]);
    await start(t);
    expect(cover, findsOneWidget);
    expect(find.byKey(const ValueKey('lock-failed')), findsOneWidget);
    expect(gate.authCalls, 1, reason: 'no automatic re-prompt loop after a failure');
    await t.pump();
    expect(gate.authCalls, 1);
    await t.tap(unlockButton);
    await t.pump();
    expect(lock.failures, 2);
    expect(cover, findsOneWidget);
    await t.tap(unlockButton);
    await t.pump();
    expect(cover, findsNothing);
    expect(lock.failures, 2);
  });

  testWidgets('no biometrics or credential: notice once, never locked', (t) async {
    gate.available = false;
    await start(t);
    expect(cover, findsNothing);
    expect(find.byKey(const ValueKey('lock-notice')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('lock-notice-ok')));
    await t.pump();
    expect(find.byKey(const ValueKey('lock-notice')), findsNothing);
    await away(t, const Duration(minutes: 10));
    expect(cover, findsNothing);
    expect(gate.authCalls, 0);
  });

  testWidgets('credential removed while locked: lets the owner in with the notice', (t) async {
    await start(t, active: false);
    expect(lock.locked, isTrue);
    gate.available = false;
    expect(await lock.unlock('x'), isTrue);
    expect(lock.locked, isFalse);
    expect(lock.noticePending, isTrue);
  });

  group('capability check errors fail closed', () {
    final failedLine = find.byKey(const ValueKey('lock-failed'));
    final notice = find.byKey(const ValueKey('lock-notice'));

    testWidgets('at cold start: stays locked with Unlock and "could not confirm", no notice',
        (t) async {
      gate.availability = GateAvailability.error;
      await start(t);
      expect(lock.locked, isTrue);
      expect(lock.available, isTrue, reason: 'an error is not "nothing enrolled"');
      expect(cover, findsOneWidget);
      expect(unlockButton, findsOneWidget);
      expect(failedLine, findsOneWidget);
      expect(notice, findsNothing);
      expect(gate.authCalls, 0);
      expect(gate.checkCalls, 2, reason: 'init, then the automatic prompt re-checks once');
      await t.pump();
      expect(gate.checkCalls, 2, reason: 'no re-check loop while the error stands');

      // Retrying while it still errors keeps it locked.
      await t.tap(unlockButton);
      await t.pump();
      expect(lock.locked, isTrue);
      expect(cover, findsOneWidget);
      expect(gate.authCalls, 0);

      // Once the phone answers again, Unlock raises the prompt as usual.
      gate.availability = GateAvailability.available;
      gate.fallback = true;
      await t.tap(unlockButton);
      await t.pump();
      expect(gate.authCalls, 1);
      expect(cover, findsNothing);
      expect(lock.locked, isFalse);
    });

    testWidgets('a throwing check is an error too: unlock refuses, no notice', (t) async {
      gate.throwOnCheck = true;
      await start(t, active: false);
      expect(lock.locked, isTrue);
      expect(await lock.unlock('x'), isFalse);
      expect(lock.locked, isTrue);
      expect(lock.lastFailed, isTrue);
      expect(lock.noticePending, isFalse);
      expect(gate.authCalls, 0);
    });

    testWidgets('after a long absence: locks and stays locked', (t) async {
      gate.fallback = true;
      await start(t);
      gate.authCalls = 0;
      gate.availability = GateAvailability.error;
      await away(t, const Duration(seconds: 61));
      expect(lock.locked, isTrue);
      expect(cover, findsOneWidget);
      expect(unlockButton, findsOneWidget);
      expect(failedLine, findsOneWidget);
      expect(notice, findsNothing);
      expect(gate.authCalls, 0);
    });

    testWidgets('confirmSensitive refuses without prompting', (t) async {
      gate.fallback = true;
      await start(t);
      gate.authCalls = 0;
      gate.availability = GateAvailability.error;
      await t.tap(find.byKey(const ValueKey('refund')));
      await t.pump();
      expect(confirmed, isFalse);
      expect(gate.authCalls, 0);
      expect(cover, findsNothing, reason: 'a refused action does not lock the app');

      gate.availability = GateAvailability.available;
      gate.throwOnCheck = true;
      confirmed = null;
      await t.tap(find.byKey(const ValueKey('refund')));
      await t.pump();
      expect(confirmed, isFalse);
      expect(gate.authCalls, 0);
    });

    testWidgets('turning the lock on is refused, the phone is not marked unable', (t) async {
      store = MemoryLockSettingsStore(false);
      await start(t);
      gate.availability = GateAvailability.error;
      expect(await lock.setEnabled(true, reason: 'x'), isFalse);
      expect(lock.enabled, isFalse);
      expect(lock.available, isTrue);
      expect(await store.read(), isFalse);
    });

    testWidgets('stored off is still respected', (t) async {
      store = MemoryLockSettingsStore(false);
      gate.availability = GateAvailability.error;
      await start(t);
      expect(lock.locked, isFalse);
      expect(lock.shouldGuard, isFalse);
      expect(notice, findsNothing);
    });
  });

  testWidgets('inactive scope (signed out) neither covers nor prompts', (t) async {
    await start(t, active: false);
    expect(cover, findsNothing);
    expect(gate.authCalls, 0);
    lock.markUnlocked();
    await away(t, const Duration(minutes: 5));
    expect(gate.authCalls, 0);
  });

  testWidgets('toggle off needs proof, is stored, and stops the lock', (t) async {
    gate.fallback = true;
    await start(t);
    gate.authCalls = 0;
    gate.fallback = false;
    expect(await lock.setEnabled(false, reason: 'off'), isFalse);
    expect(lock.enabled, isTrue);
    gate.results.add(true);
    expect(await lock.setEnabled(false, reason: 'off'), isTrue);
    expect(await store.read(), isFalse);
    await away(t, const Duration(minutes: 5));
    expect(cover, findsNothing);
    expect(await lock.setEnabled(true, reason: 'x'), isTrue);
    expect(await store.read(), isTrue);
  });

  testWidgets('stored off is respected at start', (t) async {
    store = MemoryLockSettingsStore(false);
    await start(t);
    expect(lock.locked, isFalse);
    expect(lock.shouldGuard, isFalse);
  });

  testWidgets('confirmSensitive asks, and passes when the lock is off', (t) async {
    gate.fallback = true;
    await start(t);
    gate.authCalls = 0;
    gate.fallback = false;
    await t.tap(find.byKey(const ValueKey('refund')));
    await t.pump();
    expect(gate.authCalls, 1);
    expect(gate.reasons.last, 'refund');
    expect(confirmed, isFalse);
    gate.fallback = true;
    await t.tap(find.byKey(const ValueKey('refund')));
    await t.pump();
    expect(confirmed, isTrue);
    await lock.setEnabled(false, reason: 'off');
    gate.authCalls = 0;
    await t.tap(find.byKey(const ValueKey('refund')));
    await t.pump();
    expect(gate.authCalls, 0);
    expect(confirmed, isTrue);
  });

  testWidgets('arabic cover renders RTL with the Arabic title', (t) async {
    await start(t, locale: const Locale('ar'));
    expect(find.text('تطبيق يَزَن للإدارة مقفل'), findsOneWidget);
    expect(Directionality.of(t.element(cover)), TextDirection.rtl);
  });

  testWidgets('settings tile reflects and changes the switch', (t) async {
    gate.fallback = true;
    lock = AppLockController(gate: gate, settings: store, now: () => clock);
    await lock.init();
    await lock.unlock('x');
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: RequireUnlockTile(controller: lock)),
    ));
    final tile = find.byKey(const ValueKey('require-unlock'));
    expect(t.widget<SwitchListTile>(tile).value, isTrue);
    await t.tap(tile);
    await t.pump();
    expect(lock.enabled, isFalse);
  });
}
