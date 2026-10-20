import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/products/products_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'fakes.dart';

Map<String, dynamic> _product(
  int id,
  String name, {
  String sku = '',
  String modified = '2026-10-01T09:00:00+00:00',
  int? stock = 1,
  String status = 'instock',
}) =>
    {
      'id': id,
      'type': 'simple',
      'name': name,
      'sku': sku,
      'price': '100.00',
      'regular_price': '100.00',
      'sale_price': '',
      'on_sale': false,
      'stock_status': status,
      'stock': stock,
      'images': <Object?>[],
      'modified': modified,
    };

DeltaPage _page(List<Map<String, dynamic>> items, {String cursor = 'c1', bool initial = true}) =>
    DeltaPage(items: items, cursor: cursor, hasMore: false, initial: initial);

void main() {
  group('ProductsRepository', () {
    test('refresh lists the catalogue, most recently changed first', () async {
      final repo = ProductsRepository(
        fetch: (_) async => _page([
          _product(1, 'Old ring', modified: '2026-09-01T09:00:00+00:00'),
          _product(2, 'New ring', modified: '2026-10-05T09:00:00+00:00'),
          _product(3, 'Middle ring', modified: '2026-09-20T09:00:00+00:00'),
        ]),
      );
      await repo.refresh();
      expect(repo.loaded, isTrue);
      expect(repo.lastRefreshFailed, isFalse);
      expect(repo.products.map((p) => p.id), [2, 3, 1]);
    });

    test('search matches the name or the SKU and can be cleared', () async {
      final repo = ProductsRepository(
        fetch: (_) async => _page([
          _product(1, 'Agate Ring', sku: 'YZ-100'),
          _product(2, 'Silver Band', sku: 'YZ-200'),
          _product(3, 'Aqeeq Pendant', sku: 'PD-300'),
        ]),
      );
      await repo.refresh();
      repo.setQuery('ring');
      expect(repo.products.map((p) => p.id), [1]);
      repo.setQuery('yz-');
      expect(repo.products.map((p) => p.id).toSet(), {1, 2});
      repo.setQuery('PD-300');
      expect(repo.products.single.name, 'Aqeeq Pendant');
      repo.setQuery('nothing like this');
      expect(repo.products, isEmpty);
      expect(repo.all.length, 3);
      repo.setQuery('');
      expect(repo.products.length, 3);
    });

    test('the cache shows before any network round trip and survives a failed refresh', () async {
      final store = MemoryFeedStore()..rows[1] = _product(1, 'Cached ring');
      store.cursor = 'c0';
      var calls = 0;
      final repo = ProductsRepository(
        store: store,
        fetch: (_) async {
          calls++;
          throw Exception('offline');
        },
      );
      await repo.ready;
      expect(repo.products.single.name, 'Cached ring');
      expect(calls, 0);

      await repo.refresh();
      expect(calls, 1);
      expect(repo.lastRefreshFailed, isTrue);
      expect(repo.noAccess, isFalse);
      expect(repo.products.single.name, 'Cached ring');
    });

    test('a delta applies changes and removes tombstoned products', () async {
      final store = MemoryFeedStore()
        ..rows[1] = _product(1, 'Gone ring')
        ..rows[2] = _product(2, 'Stays ring', stock: 4)
        ..cursor = 'c0';
      final repo = ProductsRepository(
        store: store,
        fetch: (cursor) async {
          expect(cursor, 'c0');
          return _page(
            [
              {'id': 1, 'deleted': true},
              _product(2, 'Stays ring', stock: 0, status: 'outofstock'),
            ],
            cursor: 'c1',
            initial: false,
          );
        },
      );
      await repo.refresh();
      expect(repo.products.map((p) => p.id), [2]);
      expect(repo.products.single.stock, 0);
      expect(store.cursor, 'c1');
    });

    test('a 403 from the feed is no access', () async {
      final repo = ProductsRepository(
        fetch: (_) async => throw const ApiError(status: 403, code: 'yazan_forbidden'),
      );
      await repo.refresh();
      expect(repo.noAccess, isTrue);
    });

    test('a permission map without products.view hides the list and skips the feed', () async {
      var pulled = false;
      final repo = ProductsRepository(
        fetch: (_) async {
          pulled = true;
          return _page([_product(1, 'Hidden')]);
        },
        loadPermissions: () async => FakeProductServer.me(['orders.view']),
      );
      await repo.refresh();
      expect(repo.noAccess, isTrue);
      expect(pulled, isFalse);
      expect(repo.permissions.known, isTrue);
    });

    test('a permission map with products.view lists the catalogue and tells the edits apart', () async {
      final repo = ProductsRepository(
        fetch: (_) async => _page([_product(1, 'Visible')]),
        loadPermissions: () async => FakeProductServer.me(['products.view', 'products.edit', 'products.change_stock']),
      );
      await repo.refresh();
      expect(repo.noAccess, isFalse);
      expect(repo.products.length, 1);
      expect(repo.permissions.canEditStock, isTrue);
      expect(repo.permissions.canEditPrice, isFalse);
    });

    test('permissions that cannot be read do not block the cached list', () async {
      final repo = ProductsRepository(
        fetch: (_) async => _page([_product(1, 'Visible')]),
        loadPermissions: () async => throw Exception('offline'),
      );
      await repo.refresh();
      expect(repo.noAccess, isFalse);
      expect(repo.permissions.known, isFalse);
      expect(repo.products.length, 1);
    });

    test('a refresh while one is running is ignored', () async {
      var calls = 0;
      final repo = ProductsRepository(
        fetch: (_) async {
          calls++;
          return _page([_product(1, 'One')]);
        },
      );
      final first = repo.refresh();
      final second = repo.refresh();
      await Future.wait([first, second]);
      expect(calls, 1);
    });
  });
}
