import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/products/products_list_page.dart';
import 'package:yazan_admin/src/products/products_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'fakes.dart';

Widget _host(Locale locale, Widget home) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: home),
    );

const List<Map<String, dynamic>> _items = [
  {
    'id': 1,
    'type': 'simple',
    'name': 'Agate Ring',
    'sku': 'YZ-100',
    'price': '120.00',
    'regular_price': '120.00',
    'sale_price': '',
    'stock_status': 'instock',
    'stock': 3,
    'modified': '2026-10-03T09:00:00+00:00',
  },
  {
    'id': 2,
    'type': 'simple',
    'name': 'Silver Band',
    'sku': 'YZ-200',
    'price': '80.00',
    'regular_price': '80.00',
    'sale_price': '',
    'stock_status': 'outofstock',
    'stock': 0,
    'modified': '2026-10-02T09:00:00+00:00',
  },
  {
    'id': 3,
    'type': 'simple',
    'name': 'Carnelian Pendant',
    'sku': 'PD-300',
    'price': '95.50',
    'regular_price': '95.50',
    'sale_price': '',
    'stock_status': 'onbackorder',
    'stock': null,
    'modified': '2026-10-01T09:00:00+00:00',
  },
];

ProductsRepository _repo({
  Object? fail,
  List<String>? permissions,
  FeedStore? store,
}) {
  return ProductsRepository(
    store: store,
    fetch: (_) async {
      if (fail != null) throw fail;
      return DeltaPage(items: _items, cursor: 'c1', hasMore: false, initial: true);
    },
    loadPermissions: permissions == null ? null : () async => FakeProductServer.me(permissions),
  );
}

void main() {
  testWidgets('the product list renders in English with stock badges', (tester) async {
    await tester.pumpWidget(_host(const Locale('en'), ProductsListPage(repository: _repo(), onOpen: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('Agate Ring'), findsOneWidget);
    expect(find.text('SKU: YZ-100'), findsOneWidget);
    expect(find.text('120.00'), findsOneWidget);
    expect(find.text('In stock: 3'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('On backorder'), findsOneWidget);
  });

  testWidgets('the product list renders right-to-left in Arabic', (tester) async {
    await tester.pumpWidget(_host(const Locale('ar'), ProductsListPage(repository: _repo(), onOpen: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('متوفر: 3'), findsOneWidget);
    expect(find.text('نفد من المخزون'), findsOneWidget);
    expect(find.text('طلب مسبق'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('Agate Ring'))), TextDirection.rtl);
  });

  testWidgets('search narrows the list by name and by SKU, and says when nothing matches', (tester) async {
    await tester.pumpWidget(_host(const Locale('en'), ProductsListPage(repository: _repo(), onOpen: (_) {})));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('product-search')), 'silver');
    await tester.pumpAndSettle();
    expect(find.text('Silver Band'), findsOneWidget);
    expect(find.text('Agate Ring'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('product-search')), 'pd-300');
    await tester.pumpAndSettle();
    expect(find.text('Carnelian Pendant'), findsOneWidget);
    expect(find.text('Silver Band'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('product-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No product matches “zzz”.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('product-search')), '');
    await tester.pumpAndSettle();
    expect(find.text('Agate Ring'), findsOneWidget);
    expect(find.text('Silver Band'), findsOneWidget);
  });

  testWidgets('tapping a row opens it', (tester) async {
    int? opened;
    await tester.pumpWidget(
      _host(const Locale('en'), ProductsListPage(repository: _repo(), onOpen: (p) => opened = p.id)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('product-2')));
    expect(opened, 2);
  });

  testWidgets('a failed refresh keeps the cached list and shows the offline badge', (tester) async {
    final store = MemoryFeedStore()
      ..rows[1] = Map<String, dynamic>.from(_items[0])
      ..cursor = 'c0';
    await tester.pumpWidget(
      _host(
        const Locale('en'),
        ProductsListPage(repository: _repo(fail: Exception('offline'), store: store), onOpen: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Agate Ring'), findsOneWidget);
    expect(find.text('Offline copy'), findsOneWidget);
  });

  testWidgets('an empty catalogue says so', (tester) async {
    final repo = ProductsRepository(
      fetch: (_) async => DeltaPage(items: const [], cursor: 'c1', hasMore: false, initial: true),
    );
    await tester.pumpWidget(_host(const Locale('en'), ProductsListPage(repository: repo, onOpen: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('No products yet.'), findsOneWidget);
  });

  testWidgets('a 403 shows the no-access state', (tester) async {
    await tester.pumpWidget(
      _host(
        const Locale('en'),
        ProductsListPage(
          repository: _repo(fail: const ApiError(status: 403, code: 'yazan_forbidden')),
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No access'), findsOneWidget);
    expect(find.text('Your account does not have permission to view products. Ask the store owner to grant it.'),
        findsOneWidget);
    expect(find.text('Agate Ring'), findsNothing);
  });

  testWidgets('a permission map without products.view hides the section (ar)', (tester) async {
    await tester.pumpWidget(
      _host(
        const Locale('ar'),
        ProductsListPage(repository: _repo(permissions: ['orders.view']), onOpen: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('لا صلاحية'), findsOneWidget);
    expect(find.text('Agate Ring'), findsNothing);
  });
}
