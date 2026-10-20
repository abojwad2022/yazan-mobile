import 'package:test/test.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

OutboxOp op(String id, {String account = 'u1'}) => OutboxOp(
      id: id,
      accountId: account,
      kind: QueueableKind.orderNote,
      method: 'POST',
      path: '/yazan/v1/orders/5/notes',
      idempotencyKey: 'key-$id-0000',
      body: {'note': id},
    );

void main() {
  final t0 = DateTime.utc(2026, 1, 1);
  late MemoryOutboxStore store;
  DateTime now = t0;

  SyncEngine engine(OpSender send) => SyncEngine(
        store: store,
        send: send,
        clock: () => now,
        jitter: () => 1.0,
      );

  setUp(() {
    store = MemoryOutboxStore();
    now = t0;
  });

  test('sends oldest first and removes on success', () async {
    final order = <String>[];
    await store.add(op('a'));
    await store.add(op('b'));
    final r = await engine((o) async => order.add(o.id)).run('u1');
    expect(order, ['a', 'b']);
    expect(r.sent, 2);
    expect(await store.all('u1'), isEmpty);
  });

  test('every retry reuses the same idempotency key', () async {
    final keys = <String>[];
    await store.add(op('a'));
    var n = 0;
    final e = engine((o) async {
      keys.add(o.idempotencyKey);
      if (++n == 1) throw const ApiError(status: 503, code: 'unavailable');
    });
    await e.run('u1');
    now = now.add(const Duration(hours: 1));
    await e.run('u1');
    expect(keys, ['key-a-0000', 'key-a-0000']);
  });

  test('a server error backs off exponentially and is not retried early', () async {
    await store.add(op('a'));
    var calls = 0;
    final e = engine((o) async {
      calls++;
      throw const ApiError(status: 500, code: 'boom');
    });
    final r = await e.run('u1');
    expect(r.retryLater, 1);
    await e.run('u1'); // not due yet
    expect(calls, 1);
    expect(e.backoff(1) < e.backoff(3), isTrue);
    expect(e.backoff(40) <= e.maxDelay, isTrue);
  });

  test('retry_after from the server wins over the computed delay', () async {
    final o = op('a');
    await store.add(o);
    final e = engine((_) async =>
        throw const ApiError(status: 409, code: 'yazan_idempotency_busy', retryAfter: 7));
    await e.run('u1');
    expect(o.nextAttemptAt, t0.add(const Duration(seconds: 7)));
  });

  test('a conflict is kept with the server version and never retried', () async {
    final o = op('a');
    await store.add(o);
    var calls = 0;
    final e = engine((_) async {
      calls++;
      throw const ApiError(status: 412, code: 'yazan_precondition_failed', current: 'v9');
    });
    final r = await e.run('u1');
    now = now.add(const Duration(days: 1));
    await e.run('u1');
    expect(r.conflicts, 1);
    expect(o.state, OpState.conflict);
    expect(o.serverVersion, 'v9');
    expect(calls, 1);
  });

  test('a wrong request is marked failed, not retried forever', () async {
    final o = op('a');
    await store.add(o);
    final r = await engine((_) async =>
        throw const ApiError(status: 422, code: 'yazan_idempotency_mismatch')).run('u1');
    expect(r.failed, 1);
    expect(o.state, OpState.failed);
  });

  test('no network stops the run without spending an attempt', () async {
    final o = op('a');
    await store.add(o);
    await store.add(op('b'));
    final r = await engine((_) async => throw Exception('socket')).run('u1');
    expect(r.offline, isTrue);
    expect(o.attempts, 0);
    expect(o.state, OpState.pending);
    expect(await store.all('u1'), hasLength(2));
  });

  test('a dead session stops everything and keeps the queue', () async {
    await store.add(op('a'));
    await store.add(op('b'));
    var calls = 0;
    final r = await engine((_) async {
      calls++;
      throw const ApiError(status: 401, code: 'yazan_mobile_bad_refresh');
    }).run('u1');
    expect(r.signedOut, isTrue);
    expect(calls, 1);
  });

  test('queues are isolated per account and cleared on sign-out', () async {
    await store.add(op('a', account: 'u1'));
    await store.add(op('b', account: 'u2'));
    final sent = <String>[];
    await engine((o) async => sent.add(o.id)).run('u1');
    expect(sent, ['a']);
    await store.clearAccount('u2');
    expect(await store.all('u2'), isEmpty);
  });

  group('pullFeed', () {
    DeltaPage page(List<Map<String, dynamic>> items, String cursor,
            {bool more = false, bool initial = false}) =>
        DeltaPage(items: items, cursor: cursor, hasMore: more, initial: initial);

    test('walks pages, saves the cursor, applies tombstones', () async {
      final fs = MemoryFeedStore();
      final pages = {
        '': page([{'id': 1}, {'id': 2}], 'c1', more: true, initial: true),
        'c1': page([{'id': 2, 'deleted': true}, {'id': 3}], 'c2'),
      };
      final n = await pullFeed(fetch: (c) async => pages[c]!, store: fs);
      expect(n, 2);
      expect(fs.rows.keys.toSet(), {1, 3});
      expect(fs.cursor, 'c2');
    });

    test('resumes from the saved cursor after an interruption', () async {
      final fs = MemoryFeedStore()..cursor = 'c1';
      final asked = <String>[];
      await pullFeed(
        fetch: (c) async {
          asked.add(c);
          return page([{'id': 9}], 'c2');
        },
        store: fs,
      );
      expect(asked, ['c1']);
    });

    test('stops at maxPages', () async {
      final fs = MemoryFeedStore();
      final n = await pullFeed(
        fetch: (c) async => page([], '${c}x', more: true),
        store: fs,
        maxPages: 3,
      );
      expect(n, 3);
    });
  });
}
