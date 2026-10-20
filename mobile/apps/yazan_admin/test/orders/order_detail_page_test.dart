import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/orders/order_detail_page.dart';
import 'package:yazan_admin/src/orders/order_summary.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

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

Widget _host(Locale locale, FakeOrderServer server, OutboxStore outbox) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: OrderDetailPage(
        summary: _summary,
        accountId: 'acct',
        load: server.load,
        sendStatus: server.sendStatus,
        sync: SyncEngine(store: outbox, send: server.sendOp),
        newKey: KeySeq().next,
      ),
    );

/// A tall surface so the notes below the status card are on screen without scrolling.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _chooseStatus(WidgetTester tester, String slug, String confirmLabel) async {
  await tester.tap(find.byKey(const ValueKey('change-status')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('status-$slug')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(confirmLabel));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('status change: offline is not queued, retry reuses the key (en)', (tester) async {
    _tallView(tester);
    final server = FakeOrderServer()..statusFailures.addAll([Exception('offline'), null]);
    final outbox = MemoryOutboxStore();
    await tester.pumpWidget(_host(const Locale('en'), server, outbox));
    await tester.pumpAndSettle();
    expect(find.text('Processing'), findsOneWidget);

    await _chooseStatus(tester, 'completed', 'Change');
    expect(server.statusCalls.single.version, 'v1');
    expect(server.statusCalls.single.key, 'key-1');
    expect(
      find.text('This needs a connection. Nothing was saved on the phone; try again when you are online.'),
      findsOneWidget,
    );
    expect(await outbox.all('acct'), isEmpty);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(server.statusCalls.length, 2);
    expect(server.statusCalls[1].key, 'key-1');
    expect(server.statusCalls[1].version, 'v1');
    expect(find.text('Order status updated.'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('a 412 opens the conflict screen; overwrite uses the new version (ar)', (tester) async {
    _tallView(tester);
    final server = FakeOrderServer()
      ..statusFailures.add(
        const ApiError(status: 412, code: 'yazan_precondition_failed', current: 'v2'),
      );
    await tester.pumpWidget(_host(const Locale('ar'), server, MemoryOutboxStore()));
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(find.text('Sara Ali'))), TextDirection.rtl);

    // Someone else cancels the order on the website meanwhile.
    server
      ..status = 'cancelled'
      ..version = 'v2';
    await _chooseStatus(tester, 'completed', 'تغيير');

    expect(find.text('تغيّر هذا الطلب'), findsOneWidget);
    expect(find.text('مكتمل'), findsOneWidget);
    expect(find.text('ملغى'), findsOneWidget);

    await tester.tap(find.text('استبدال بنسختي'));
    await tester.pumpAndSettle();
    expect(server.statusCalls.map((c) => c.version), ['v1', 'v2']);
    expect(server.statusCalls[1].key, isNot(server.statusCalls[0].key));
    expect(find.text('تم تحديث حالة الطلب.'), findsOneWidget);
  });

  testWidgets('keep server version reloads the order (ar)', (tester) async {
    _tallView(tester);
    final server = FakeOrderServer()
      ..statusFailures.add(
        const ApiError(status: 412, code: 'yazan_precondition_failed', current: 'v2'),
      );
    await tester.pumpWidget(_host(const Locale('ar'), server, MemoryOutboxStore()));
    await tester.pumpAndSettle();
    server.status = 'cancelled';
    await _chooseStatus(tester, 'completed', 'تغيير');

    await tester.tap(find.text('الإبقاء على نسخة الخادم'));
    await tester.pumpAndSettle();
    expect(find.text('تغيّر هذا الطلب'), findsNothing);
    expect(find.text('ملغى'), findsOneWidget);
    expect(server.statusCalls.length, 1);
  });

  testWidgets('403 on a status change shows the no-permission message (en)', (tester) async {
    _tallView(tester);
    final server = FakeOrderServer()
      ..statusFailures.add(const ApiError(status: 403, code: 'yazan_forbidden'));
    await tester.pumpWidget(_host(const Locale('en'), server, MemoryOutboxStore()));
    await tester.pumpAndSettle();
    await _chooseStatus(tester, 'completed', 'Change');
    expect(find.text("You do not have permission to change this order's status."), findsOneWidget);
  });

  testWidgets('an offline note waits greyed in the outbox and Sync now sends it (en)', (tester) async {
    _tallView(tester);
    final server = FakeOrderServer()..online = false;
    final outbox = MemoryOutboxStore();
    await tester.pumpWidget(_host(const Locale('en'), server, outbox));
    await tester.pumpAndSettle();
    expect(find.text('No notes yet.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('note-field')), 'Call before delivery');
    await tester.tap(find.byKey(const ValueKey('add-note')));
    await tester.pumpAndSettle();

    final queued = await outbox.all('acct');
    expect(queued.single.kind, QueueableKind.orderNote);
    expect(find.text('Waiting to send'), findsOneWidget);
    expect(find.text('Call before delivery'), findsOneWidget);
    expect(find.text('Saved on the phone. It will be sent when you are online.'), findsOneWidget);

    server.online = true;
    await tester.tap(find.byKey(const ValueKey('sync-now')));
    await tester.pumpAndSettle();
    expect(server.sentOps.single.idempotencyKey, queued.single.idempotencyKey);
    expect(await outbox.all('acct'), isEmpty);
    expect(find.text('Waiting to send'), findsNothing);
    expect(find.text('Call before delivery'), findsOneWidget);
  });

  testWidgets('notes render right-to-left with the Arabic labels (ar)', (tester) async {
    _tallView(tester);
    final server = FakeOrderServer()..online = false;
    await tester.pumpWidget(_host(const Locale('ar'), server, MemoryOutboxStore()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('note-field')), 'اتصل قبل التوصيل');
    await tester.tap(find.byKey(const ValueKey('add-note')));
    await tester.pumpAndSettle();
    expect(find.text('بانتظار الإرسال'), findsOneWidget);
    expect(find.text('مزامنة الآن'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('بانتظار الإرسال'))), TextDirection.rtl);
  });
}
