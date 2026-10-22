import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/orders/order_summary.dart';
import 'package:yazan_admin/src/orders/orders_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

Map<String, dynamic> _order(int id, String created, {String name = 'Sara Ali'}) => {
      'id': id,
      'number': '$id',
      'status': 'processing',
      'total': '129.50',
      'currency': 'USD',
      'items': 2,
      'name': name,
      'created': created,
      'modified': '2026-10-01 10:00:00',
      'version': 'v$id',
    };

DeltaPage _page(List<Map<String, dynamic>> items, {String cursor = 'c1', bool initial = true}) =>
    DeltaPage(items: items, cursor: cursor, hasMore: false, initial: initial);

void main() {
  group('OrderSummary.fromJson', () {
    test('parses a full feed record', () {
      final o = OrderSummary.fromJson(_order(7, '2026-10-01T09:00:00+00:00'));
      expect(o.id, 7);
      expect(o.number, '7');
      expect(o.status, 'processing');
      expect(o.total, const Money(12950, 'USD'));
      expect(o.itemCount, 2);
      expect(o.customerName, 'Sara Ali');
      expect(o.created, isNotNull);
      expect(o.version, 'v7');
    });

    test('tolerates missing and odd fields', () {
      final o = OrderSummary.fromJson({'id': 5, 'total': 'abc', 'items': '3'});
      expect(o.id, 5);
      expect(o.number, '5');
      expect(o.status, '');
      expect(o.total.minor, 0);
      expect(o.itemCount, 3);
      expect(o.customerName, '');
      expect(o.created, isNull);
      expect(o.version, '');
    });

    test('accepts a total with extra trailing zeros', () {
      final o = OrderSummary.fromJson({'id': 1, 'total': '10.500', 'currency': 'SAR'});
      expect(o.total, const Money(1050, 'SAR'));
    });
  });

  group('OrdersRepository', () {
    test('refresh lists orders newest first', () async {
      final repo = OrdersRepository(
        fetch: (_) async => _page([
          _order(1, '2026-09-01T09:00:00+00:00'),
          _order(3, '2026-10-03T09:00:00+00:00'),
          _order(2, '2026-10-02T09:00:00+00:00'),
        ]),
      );
      await repo.refresh();
      expect(repo.orders.map((o) => o.id), [3, 2, 1]);
      expect(repo.lastRefreshFailed, isFalse);
      expect(repo.loaded, isTrue);
    });

    test('a failed refresh keeps the cache and flags it', () async {
      var fail = false;
      final repo = OrdersRepository(
        fetch: (_) async {
          if (fail) throw Exception('offline');
          return _page([_order(1, '2026-09-01T09:00:00+00:00')]);
        },
      );
      await repo.refresh();
      fail = true;
      await repo.refresh();
      expect(repo.orders.length, 1);
      expect(repo.lastRefreshFailed, isTrue);
      expect(repo.noAccess, isFalse);
    });

    test('a 403 sets noAccess', () async {
      final repo = OrdersRepository(
        fetch: (_) async => throw const ApiError(status: 403, code: 'yazan_forbidden'),
      );
      await repo.refresh();
      expect(repo.noAccess, isTrue);
      expect(repo.orders, isEmpty);
    });

    test('a 403 with any other code also sets noAccess, and purge drops the cache', () async {
      var deny = false;
      final store = MemoryFeedStore();
      final repo = OrdersRepository(
        store: store,
        fetch: (_) async {
          if (deny) throw const ApiError(status: 403, code: 'yazan_suspended');
          return _page([_order(1, '2026-09-01T09:00:00+00:00')]);
        },
      );
      await repo.refresh();
      expect(repo.orders.length, 1);
      expect(repo.noAccess, isFalse);

      deny = true;
      await repo.refresh();
      expect(repo.noAccess, isTrue);
      await repo.purge();
      expect(repo.orders, isEmpty);
      expect(await store.readAll(), isEmpty);
    });

    test('a non-403 server error is not noAccess', () async {
      final repo = OrdersRepository(
        fetch: (_) async => throw const ApiError(status: 500, code: 'internal_server_error'),
      );
      await repo.refresh();
      expect(repo.lastRefreshFailed, isTrue);
      expect(repo.noAccess, isFalse);
    });

    test('shows the cache after a restart before any network call', () async {
      final store = MemoryFeedStore()
        ..cursor = 'c9'
        ..rows[4] = _order(4, '2026-10-04T09:00:00+00:00');
      var fetched = 0;
      final repo = OrdersRepository(
        store: store,
        fetch: (_) async {
          fetched++;
          return _page(const [], cursor: 'c9', initial: false);
        },
      );
      await repo.ready;
      expect(fetched, 0);
      expect(repo.orders.map((o) => o.id), [4]);
      await repo.refresh();
      expect(repo.orders.map((o) => o.id), [4]);
    });

    test('tombstones remove cached orders on the next pull', () async {
      var n = 0;
      final repo = OrdersRepository(
        fetch: (cursor) async {
          n++;
          if (n == 1) {
            return _page([_order(1, '2026-09-01T09:00:00+00:00')]);
          }
          return _page([
            {'id': 1, 'deleted': true}
          ], cursor: 'c2', initial: false);
        },
      );
      await repo.refresh();
      expect(repo.orders.length, 1);
      await repo.refresh();
      expect(repo.orders, isEmpty);
    });
  });
}
