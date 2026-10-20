import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/orders/order_detail_controller.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'fakes.dart';

const _conflict = ApiError(status: 412, code: 'yazan_precondition_failed', current: 'v2');

void main() {
  late FakeOrderServer server;
  late MemoryOutboxStore outbox;
  late OrderDetailController c;

  OrderDetailController make({NotesLoader? loadNotes}) => OrderDetailController(
        orderId: 1001,
        accountId: 'acct',
        initialStatus: 'processing',
        fallbackVersion: 'feed-v',
        load: server.load,
        sendStatus: server.sendStatus,
        sync: SyncEngine(store: outbox, send: server.sendOp),
        loadNotes: loadNotes,
        newKey: KeySeq().next,
      );

  setUp(() async {
    server = FakeOrderServer();
    outbox = MemoryOutboxStore();
    c = make();
    await c.load();
  });

  tearDown(() => c.dispose());

  group('status change', () {
    test('sends the ETag version and an Idempotency-Key', () async {
      expect(c.version, 'v1');
      final r = await c.changeStatus('completed');
      expect(r, StatusResult.done);
      expect(server.statusCalls.single.status, 'completed');
      expect(server.statusCalls.single.version, 'v1');
      expect(server.statusCalls.single.key, 'key-1');
      // Re-read after the write: the next edit is based on the new version.
      expect(c.version, 'v-after-completed');
      expect(c.status, 'completed');
    });

    test('falls back to the feed version when the read had no ETag', () async {
      server.version = null;
      await c.load();
      await c.changeStatus('completed');
      expect(server.statusCalls.single.version, 'feed-v');
    });

    test('a network failure is not queued and the retry reuses the key', () async {
      server.statusFailures.addAll([Exception('offline'), null]);
      expect(await c.changeStatus('completed'), StatusResult.offline);
      expect(c.lastResult, StatusResult.offline);
      expect(c.canRetry, isTrue);
      expect(await outbox.all('acct'), isEmpty);

      expect(await c.retryStatus(), StatusResult.done);
      expect(server.statusCalls.map((s) => s.key), ['key-1', 'key-1']);
      expect(c.canRetry, isFalse);
    });

    test('a busy answer keeps the same key', () async {
      server.statusFailures.addAll([
        const ApiError(status: 409, code: 'yazan_idempotency_busy', retryAfter: 2),
        null,
      ]);
      expect(await c.changeStatus('completed'), StatusResult.busy);
      expect(await c.changeStatus('completed'), StatusResult.done);
      expect(server.statusCalls[0].key, server.statusCalls[1].key);
    });

    test('choosing another status starts a new attempt', () async {
      server.statusFailures.add(Exception('offline'));
      await c.changeStatus('completed');
      await c.changeStatus('on-hold');
      expect(server.statusCalls.map((s) => s.key), ['key-1', 'key-2']);
    });

    test('412 opens a conflict; overwrite retries with the new version', () async {
      server.statusFailures.add(_conflict);
      server.status = 'cancelled';
      server.version = 'v2';
      expect(await c.changeStatus('completed'), StatusResult.conflict);
      final conflict = c.conflict;
      expect(conflict, isNotNull);
      expect(conflict?.mine, 'completed');
      expect(conflict?.serverStatus, 'cancelled');
      expect(conflict?.serverVersion, 'v2');

      expect(await c.overwrite(), StatusResult.done);
      expect(server.statusCalls.map((s) => s.version), ['v1', 'v2']);
      expect(server.statusCalls[1].status, 'completed');
      expect(c.conflict, isNull);
    });

    test('keep server version drops the choice and reloads', () async {
      server.statusFailures.add(_conflict);
      server.status = 'cancelled';
      server.version = 'v2';
      await c.changeStatus('completed');
      final before = server.loads;
      await c.keepServer();
      expect(server.loads, before + 1);
      expect(c.status, 'cancelled');
      expect(c.version, 'v2');
      expect(c.canRetry, isFalse);
      expect(server.statusCalls.length, 1);
    });

    test('403 hideFeature reports no permission', () async {
      server.statusFailures.add(const ApiError(status: 403, code: 'yazan_forbidden'));
      expect(await c.changeStatus('completed'), StatusResult.noAccess);
      expect(c.noAccess, isFalse, reason: 'the order itself is still viewable');
    });
  });

  group('notes', () {
    test('are read from the order payload as plain text', () async {
      server.notes.add({'id': 5, 'content': 'Paid <b>in full</b> &amp; packed', 'customer_note': true});
      await c.load();
      expect(c.notes.single.content, 'Paid in full & packed');
      expect(c.notes.single.toCustomer, isTrue);
    });

    test('come from the notes route when the payload has none', () async {
      server.includeNotes = false;
      final withLoader = make(
        loadNotes: (id) async => [
          {'id': 7, 'content': 'From the route'},
        ],
      );
      await withLoader.load();
      expect(withLoader.notes.single.content, 'From the route');
      withLoader.dispose();
    });

    test('an offline note waits in the outbox and SyncEngine sends it later', () async {
      server.online = false;
      final first = await c.addNote('  Call before delivery ');
      expect(first.offline, isTrue);

      final queued = await outbox.all('acct');
      expect(queued.single.kind, QueueableKind.orderNote);
      expect(queued.single.method, 'POST');
      expect(queued.single.path, '/yazan/v1/orders/1001/notes');
      expect(queued.single.body, {'note': 'Call before delivery', 'customer_note': false});
      expect(c.pendingNotes.single.state, OpState.pending);
      final key = queued.single.idempotencyKey;

      server.online = true;
      final report = await c.syncNow();
      expect(report.sent, 1);
      expect(server.sentOps.single.idempotencyKey, key);
      expect(c.pendingNotes, isEmpty);
      expect(c.notes.first.content, 'Call before delivery');
    });

    test('an empty note is ignored', () async {
      await c.addNote('   ');
      expect(await outbox.all('acct'), isEmpty);
    });
  });
}
