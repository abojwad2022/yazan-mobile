import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/customers/customers_repository.dart';
import 'package:yazan_admin/src/orders/orders_repository.dart';
import 'package:yazan_admin/src/products/products_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../customers/fakes.dart' show customerRows, customersMe;

DeltaPage _page(List<Map<String, dynamic>> items) =>
    DeltaPage(items: items, cursor: 'c1', hasMore: false, initial: true);

void main() {
  test('CustomersRepository.purge empties the list, the stored rows and the cursor', () async {
    final store = MemoryFeedStore();
    final repo = CustomersRepository(fetch: (_) async => _page(customerRows), store: store);
    await repo.refresh();
    expect(repo.all, isNotEmpty);
    expect(store.rows, isNotEmpty);
    expect(store.cursor, 'c1');

    await repo.purge();

    expect(repo.all, isEmpty);
    expect(store.rows, isEmpty);
    expect(store.cursor, '');
  });

  test('a customers refresh with no customers.view pulls nothing and leaves the rows to be purged',
      () async {
    final store = MemoryFeedStore();
    var fetches = 0;
    final repo = CustomersRepository(
      fetch: (_) async {
        fetches++;
        return _page(customerRows);
      },
      store: store,
      loadPermissions: () async => customersMe(['orders.view']),
    );

    await repo.refresh();

    expect(repo.noAccess, isTrue);
    expect(fetches, 0);
  });

  test('after a purge a later refresh starts from the beginning', () async {
    final store = MemoryFeedStore();
    final cursors = <String>[];
    final repo = CustomersRepository(
      fetch: (cursor) async {
        cursors.add(cursor);
        return _page(customerRows);
      },
      store: store,
    );
    await repo.refresh();
    await repo.purge();
    await repo.refresh();

    expect(cursors, ['', '']);
    expect(repo.all, isNotEmpty);
  });

  test('OrdersRepository.purge and ProductsRepository.purge clear their stores', () async {
    final orderStore = MemoryFeedStore();
    final orders = OrdersRepository(
      fetch: (_) async => _page([
        {'id': 1, 'number': '1', 'name': 'Sara Ali'},
      ]),
      store: orderStore,
    );
    await orders.refresh();
    expect(orders.orders, hasLength(1));
    await orders.purge();
    expect(orders.orders, isEmpty);
    expect(orderStore.rows, isEmpty);
    expect(orderStore.cursor, '');

    final productStore = MemoryFeedStore();
    final products = ProductsRepository(
      fetch: (_) async => _page([
        {'id': 2, 'name': 'Agate ring'},
      ]),
      store: productStore,
    );
    await products.refresh();
    expect(products.all, hasLength(1));
    await products.purge();
    expect(products.all, isEmpty);
    expect(productStore.rows, isEmpty);
    expect(productStore.cursor, '');
  });
}
