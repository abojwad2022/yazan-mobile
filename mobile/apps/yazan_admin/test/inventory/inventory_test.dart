import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/inventory/inventory_page.dart';
import 'package:yazan_admin/src/inventory/inventory_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../dashboard/fakes.dart' show dashboardHost, tallScreen;

final DateTime _now = DateTime(2026, 10, 20, 14, 5);

Map<String, dynamic> _row(int id, String name, String sku, int? qty, String status) =>
    {'id': id, 'name': name, 'sku': sku, 'qty': qty, 'managed': qty != null, 'status': status};

Map<String, dynamic> _answer() => {
      'low_threshold': 2,
      'out_of_stock': [
        _row(1, 'Agate ring red', 'AG-1', 0, 'outofstock'),
        _row(2, 'Silver cuff', 'SC-2', null, 'outofstock'),
      ],
      'low_stock': [
        _row(3, 'Agate ring blue', 'AG-3', 1, 'instock'),
      ],
    };

class _Server {
  Map<String, dynamic> answer = _answer();
  Object? failure;
  int calls = 0;

  Future<Map<String, dynamic>> fetch() async {
    calls++;
    if (failure != null) throw failure!;
    return answer;
  }

  InventoryRepository repository({FeedStore? store}) =>
      InventoryRepository(fetch: fetch, store: store, clock: () => _now);
}

Widget _page(InventoryRepository repo, {Locale locale = const Locale('en'), void Function(int)? open}) =>
    dashboardHost(locale, InventoryPage(repository: repo, onOpenProduct: open));

void main() {
  testWidgets('English: out of stock and low stock lists with counts', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(_Server().repository()));
    await tester.pumpAndSettle();

    expect(find.text('Out of stock (2)'), findsOneWidget);
    expect(find.textContaining('Low stock, '), findsOneWidget);
    expect(find.textContaining('(1)'), findsOneWidget);
    expect(find.text('Agate ring red'), findsOneWidget);
    expect(find.text('Silver cuff'), findsOneWidget);
    expect(find.text('Agate ring blue'), findsOneWidget);
    expect(find.textContaining('2026-10-20 14:05'), findsOneWidget);
  });

  testWidgets('Arabic: translated headers', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(_Server().repository(), locale: const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.text('نفد من المخزون (2)'), findsOneWidget);
    expect(find.text('Agate ring red'), findsOneWidget);
  });

  testWidgets('search narrows the list by name or SKU', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(_Server().repository()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('inventory-search')), 'blue');
    await tester.pump();
    expect(find.text('Agate ring blue'), findsOneWidget);
    expect(find.text('Agate ring red'), findsNothing);
    expect(find.byKey(const ValueKey('inventory-out-header')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('inventory-search')), 'sc-2');
    await tester.pump();
    expect(find.text('Silver cuff'), findsOneWidget);
    expect(find.text('Agate ring blue'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('inventory-search')), 'nothing like it');
    await tester.pump();
    expect(find.text('No products match your search.'), findsOneWidget);
  });

  testWidgets('tapping a row shows the quantity, read only', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(_Server().repository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('inventory-row-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inventory-detail')), findsOneWidget);
    expect(find.text('In stock: 1'), findsOneWidget);
    expect(find.textContaining('AG-3'), findsWidgets);
    expect(find.byKey(const ValueKey('inventory-open-product')), findsNothing);
    expect(find.byType(TextField), findsOneWidget); // only the search box: nothing to edit
  });

  testWidgets('a product without a tracked quantity says so', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(_Server().repository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('inventory-row-2')));
    await tester.pumpAndSettle();
    expect(find.text('Quantity is not tracked for this product.'), findsOneWidget);
  });

  testWidgets('the open-product link calls back with the id', (tester) async {
    tallScreen(tester);
    final opened = <int>[];
    await tester.pumpWidget(_page(_Server().repository(), open: opened.add));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('inventory-row-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inventory-open-product')));
    await tester.pumpAndSettle();
    expect(opened, [1]);
    expect(find.byKey(const ValueKey('inventory-detail')), findsNothing);
  });

  testWidgets('nothing to restock', (tester) async {
    final server = _Server()..answer = {'low_threshold': 2, 'out_of_stock': [], 'low_stock': []};
    await tester.pumpWidget(_page(server.repository()));
    await tester.pumpAndSettle();
    expect(find.text('Nothing needs restocking.'), findsOneWidget);
  });

  testWidgets('no access when the server says 403', (tester) async {
    final server = _Server()..failure = const ApiError(status: 403, code: 'yazan_forbidden');
    await tester.pumpWidget(_page(server.repository()));
    await tester.pumpAndSettle();
    expect(find.text('No access'), findsOneWidget);
    expect(find.textContaining('view inventory'), findsOneWidget);
  });

  testWidgets('offline: the cached list shows with the offline badge', (tester) async {
    tallScreen(tester);
    final store = MemoryFeedStore();
    await _Server().repository(store: store).refresh();

    final server = _Server()..failure = Exception('offline');
    await tester.pumpWidget(_page(server.repository(store: store)));
    await tester.pumpAndSettle();

    expect(find.text('Agate ring red'), findsOneWidget);
    expect(find.byKey(const ValueKey('inventory-stale')), findsOneWidget);
  });

  testWidgets('offline with nothing cached: a retry hint', (tester) async {
    final server = _Server()..failure = Exception('offline');
    await tester.pumpWidget(_page(server.repository()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load the stock report'), findsOneWidget);
  });

  testWidgets('pull to refresh asks the server again', (tester) async {
    tallScreen(tester);
    final server = _Server();
    await tester.pumpWidget(_page(server.repository()));
    await tester.pumpAndSettle();
    expect(server.calls, 1);

    server.answer = {
      'low_threshold': 2,
      'out_of_stock': [_row(5, 'Gold chain', 'GC-5', 0, 'outofstock')],
      'low_stock': [],
    };
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pumpAndSettle();

    expect(server.calls, 2);
    expect(find.text('Gold chain'), findsOneWidget);
    expect(find.text('Agate ring red'), findsNothing);
  });

  test('a 403 clears the cached copy', () async {
    final store = MemoryFeedStore();
    final server = _Server();
    final repo = server.repository(store: store);
    await repo.refresh();
    expect(store.rows, isNotEmpty);

    server.failure = const ApiError(status: 403, code: 'yazan_forbidden');
    await repo.refresh();
    expect(repo.noAccess, isTrue);
    expect(store.rows, isEmpty);
  });
}
