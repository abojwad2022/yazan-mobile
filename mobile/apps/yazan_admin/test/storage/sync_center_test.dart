import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/sync/observed_sync_engine.dart';
import 'package:yazan_admin/src/sync/sync_center_page.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../customers/fakes.dart' show customersHost;

OutboxOp _op(String id, {OpState state = OpState.pending, int attempts = 0, String? entity}) =>
    OutboxOp(
      id: id,
      accountId: 'a',
      kind: QueueableKind.orderNote,
      method: 'POST',
      path: '/yazan/v1/orders/5/notes',
      idempotencyKey: 'key-$id',
      entity: entity ?? 'order:5',
      body: {'note': 'hello'},
      state: state,
      attempts: attempts,
    );

final _t = DateTime.utc(2026, 10, 20, 9, 30);

void main() {
  group('ObservedSyncEngine', () {
    test('records when the server was last reached', () async {
      final store = MemoryOutboxStore();
      await store.add(_op('1'));
      final sent = <String>[];
      final engine = ObservedSyncEngine(
        store: store,
        send: (op) async => sent.add(op.id),
        now: () => _t,
      );
      expect(engine.status.lastSuccessAt, isNull);

      final report = await engine.run('a');

      expect(report.sent, 1);
      expect(sent, ['1']);
      expect(engine.status.lastSuccessAt, _t);
      expect(engine.status.running, isFalse);
    });

    test('an offline run is an attempt, not a success', () async {
      final store = MemoryOutboxStore();
      await store.add(_op('1'));
      final engine = ObservedSyncEngine(
        store: store,
        send: (op) async => throw Exception('offline'),
        now: () => _t,
      );

      final report = await engine.run('a');

      expect(report.offline, isTrue);
      expect(engine.status.lastAttemptAt, _t);
      expect(engine.status.lastSuccessAt, isNull);
      expect((await store.all('a')).single.state, OpState.pending);
    });

    test('a refused session is reported to the app shell', () async {
      final store = MemoryOutboxStore();
      await store.add(_op('1'));
      var ended = 0;
      final engine = ObservedSyncEngine(
        store: store,
        send: (op) async => throw const ApiError(status: 401, code: 'yazan_mobile_bad_refresh'),
        onSessionEnded: () => ended++,
        now: () => _t,
      );

      final report = await engine.run('a');

      expect(report.signedOut, isTrue);
      expect(ended, 1);
      expect(engine.status.lastSuccessAt, isNull);
    });

    test('two callers share one run, so an op is not sent twice', () async {
      final store = MemoryOutboxStore();
      await store.add(_op('1'));
      final release = Completer<void>();
      var sends = 0;
      final engine = ObservedSyncEngine(
        store: store,
        send: (op) async {
          sends++;
          await release.future;
        },
      );

      final first = engine.run('a');
      final second = engine.run('a');
      expect(engine.status.running, isTrue);
      release.complete();

      final reports = await Future.wait([first, second]);
      expect(sends, 1);
      expect(identical(reports[0], reports[1]), isTrue);
      expect(engine.status.running, isFalse);

      // Once it is over, a new run starts a new send.
      await store.add(_op('2'));
      await engine.run('a');
      expect(sends, 2);
    });
  });

  group('SyncCenterPage', () {
    late MemoryOutboxStore store;
    late List<String> sent;
    late bool online;
    late ObservedSyncEngine engine;

    setUp(() {
      store = MemoryOutboxStore();
      sent = [];
      online = true;
      engine = ObservedSyncEngine(
        store: store,
        send: (op) async {
          if (!online) throw Exception('offline');
          sent.add(op.id);
        },
        now: () => _t,
      );
    });

    Widget page() => customersHost(
          const Locale('en'),
          SyncCenterPage(accountId: 'a', store: store, engine: engine),
        );

    testWidgets('shows what is waiting, what needs attention, and that nothing synced yet',
        (tester) async {
      await store.add(_op('p1'));
      await store.add(_op('f1', state: OpState.failed, attempts: 3));
      await store.add(_op('c1', state: OpState.conflict));
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      expect(find.text('Waiting to send: 1'), findsOneWidget);
      expect(find.text('Needs attention: 2'), findsOneWidget);
      expect(find.text('Not synced yet.'), findsOneWidget);
      expect(find.text('Note on order #5'), findsNWidgets(3));
      expect(find.text('Could not send · Attempts: 3'), findsOneWidget);
      expect(find.text('Changed on the server'), findsOneWidget);
      // Only a failed op can be retried; failed and conflicted ones can be discarded.
      expect(find.byKey(const ValueKey('sync-retry-f1')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-retry-c1')), findsNothing);
      expect(find.byKey(const ValueKey('sync-discard-f1')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-discard-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-discard-p1')), findsNothing);
    });

    testWidgets('only the signed-in account\'s ops are listed', (tester) async {
      await store.add(_op('mine'));
      await store.add(OutboxOp(
        id: 'theirs',
        accountId: 'someone-else',
        kind: QueueableKind.orderNote,
        method: 'POST',
        path: '/n',
        idempotencyKey: 'k',
      ));
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sync-op-mine')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-op-theirs')), findsNothing);
      expect(find.text('Waiting to send: 1'), findsOneWidget);
    });

    testWidgets('Sync now sends the queue and shows the time of the last sync', (tester) async {
      await store.add(_op('p1'));
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sync-center-run')));
      await tester.pumpAndSettle();

      expect(sent, ['p1']);
      expect(find.byKey(const ValueKey('sync-empty')), findsOneWidget);
      expect(find.text('Everything is sent.'), findsOneWidget);
      expect(find.textContaining('Last sync:'), findsOneWidget);
      expect(find.text('Waiting to send: 0'), findsOneWidget);
    });

    testWidgets('Sync now also sends ops that were waiting out a backoff', (tester) async {
      final op = _op('p1')..nextAttemptAt = DateTime.now().toUtc().add(const Duration(hours: 1));
      await store.add(op);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sync-center-run')));
      await tester.pumpAndSettle();

      expect(sent, ['p1']);
    });

    testWidgets('offline: the op stays queued and the screen says so', (tester) async {
      online = false;
      await store.add(_op('p1'));
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sync-center-run')));
      await tester.pumpAndSettle();

      expect(sent, isEmpty);
      expect(find.text('Waiting to send: 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-offline')), findsOneWidget);
      expect(find.text('Not synced yet.'), findsOneWidget);
    });

    testWidgets('Retry puts a failed op back in the queue and sends it', (tester) async {
      await store.add(_op('f1', state: OpState.failed, attempts: 4)..lastError = 'bad');
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sync-retry-f1')));
      await tester.pumpAndSettle();

      expect(sent, ['f1']);
      expect(await store.all('a'), isEmpty);
      expect(find.byKey(const ValueKey('sync-empty')), findsOneWidget);
    });

    testWidgets('Discard removes an op for good', (tester) async {
      await store.add(_op('c1', state: OpState.conflict));
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sync-discard-c1')));
      await tester.pumpAndSettle();

      expect(await store.all('a'), isEmpty);
      expect(sent, isEmpty);
      expect(find.byKey(const ValueKey('sync-empty')), findsOneWidget);
    });

    testWidgets('is labelled in Arabic', (tester) async {
      await tester.pumpWidget(customersHost(
        const Locale('ar'),
        SyncCenterPage(accountId: 'a', store: store, engine: engine),
      ));
      await tester.pumpAndSettle();
      expect(find.text('مركز المزامنة'), findsOneWidget);
    });
  });
}
