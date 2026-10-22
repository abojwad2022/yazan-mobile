import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/storage/admin_stores.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'fakes.dart';

Future<void> _page(FeedStore f, int id, {String cursor = 'c1'}) => f.apply(
      upserts: [
        {'id': id, 'email': 'customer$id@example.test'},
      ],
      deletedIds: const [],
      cursor: cursor,
      initial: false,
    );

void main() {
  group('DurableAdminStores', () {
    late FakeAccountStorage storage;
    late DurableAdminStores a;
    late DurableAdminStores b;

    setUp(() async {
      storage = FakeAccountStorage();
      a = DurableAdminStores(storage, 'shop.test:1');
      b = DurableAdminStores(storage, 'shop.test:2');
      await storage.seed(a.accountId);
      await storage.seed(b.accountId);
    });

    test('is durable and scoped to the account', () async {
      expect(a.durable, isTrue);
      expect((await a.feed(AdminFeeds.orders).readAll()).single['name'], 'Buyer of shop.test:1');
      expect((await b.feed(AdminFeeds.orders).readAll()).single['name'], 'Buyer of shop.test:2');
      expect((await a.outbox.all(a.accountId)).map((o) => o.id), ['op-shop.test:1']);
    });

    test('wipe removes the queue and every feed of that account, and only that account', () async {
      await a.wipe();

      expect(storage.rowCount('shop.test:1'), 0);
      for (final feed in [AdminFeeds.orders, AdminFeeds.products, AdminFeeds.customers]) {
        expect(await a.feed(feed).readAll(), isEmpty, reason: feed);
        expect(await a.feed(feed).readCursor(), '', reason: feed);
      }
      expect(await a.outbox.all(a.accountId), isEmpty);

      expect(storage.rowCount('shop.test:2'), 2);
      expect(await b.feed(AdminFeeds.orders).readCursor(), 'orders-cursor');
      expect(await b.outbox.all(b.accountId), hasLength(1));
    });

    test('a page that arrives after the wipe is dropped, not written back', () async {
      // A refresh started before sign-out holds this feed object and is still pulling pages.
      final inFlight = a.feed(AdminFeeds.customers);
      await _page(inFlight, 11);
      expect(storage.rowCount('shop.test:1'), 3);

      await a.wipe();
      await _page(inFlight, 12, cursor: 'c2');

      expect(storage.rowCount('shop.test:1'), 0);
      expect(await inFlight.readCursor(), '');
    });

    test('feed metadata reaches the account store, and is refused after the wipe', () async {
      final feed = a.feed(AdminFeeds.products);
      await feed.writeMeta('synced_at', '2026-10-20T12:00:00.000Z');
      expect(storage.raw(a.accountId, AdminFeeds.products).meta['synced_at'], '2026-10-20T12:00:00.000Z');
      expect(await b.feed(AdminFeeds.products).readMeta('synced_at'), isNull);

      await a.wipe();
      await feed.writeMeta('synced_at', '2026-10-21T12:00:00.000Z');
      expect(await feed.readMeta('synced_at'), isNull);
    });

    test('wiping twice is harmless', () async {
      await a.wipe();
      await a.wipe();
      expect(storage.rowCount('shop.test:1'), 0);
      expect(storage.rowCount('shop.test:2'), 2);
    });

    test('a failing wipe throws so the caller can keep the account id and retry', () async {
      storage.failWipe = true;
      await expectLater(a.wipe(), throwsStateError);
      expect(storage.rowCount('shop.test:1'), 2);
    });
  });

  group('MemoryAdminStores', () {
    test('keeps feeds apart and is not durable', () async {
      final s = MemoryAdminStores();
      expect(s.durable, isFalse);
      await _page(s.feed(AdminFeeds.customers), 1);
      expect(await s.feed(AdminFeeds.orders).readAll(), isEmpty);
      expect(await s.feed(AdminFeeds.customers).readAll(), hasLength(1));
    });

    test('wipe empties the feeds and the queue, and later pages are dropped', () async {
      final s = MemoryAdminStores(accountId: 'x');
      final feed = s.feed(AdminFeeds.customers);
      await _page(feed, 1);
      await s.outbox.add(OutboxOp(
        id: 'op',
        accountId: 'x',
        kind: QueueableKind.orderNote,
        method: 'POST',
        path: '/n',
        idempotencyKey: 'k',
      ));

      await s.wipe();
      await _page(feed, 2, cursor: 'c2');

      expect(await feed.readAll(), isEmpty);
      expect(await feed.readCursor(), '');
      expect(await s.outbox.all('x'), isEmpty);
    });
  });
}
