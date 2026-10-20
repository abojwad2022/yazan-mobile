import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';
import 'package:yazan_store/l10n/app_localizations.dart';
import 'package:yazan_store/src/catalogue/catalogue_list_page.dart';
import 'package:yazan_store/src/catalogue/catalogue_repository.dart';
import 'package:yazan_store/src/catalogue/category_repository.dart';
import 'package:yazan_store/src/catalogue/product.dart';
import 'package:yazan_store/src/catalogue/product_page.dart';

import 'fixtures/catalogue_fixtures.dart';

/// `GET /sync/terms` rows as the server sends them.
Map<String, dynamic> _term(int id, String name, {int parent = 0, int count = 1}) =>
    {'id': id, 'name': name, 'slug': name.toLowerCase(), 'parent': parent, 'count': count, 'image': null};

List<Map<String, dynamic>> _terms() => [
      _term(1, 'Rings'),
      _term(2, 'Signet', parent: 1),
      _term(3, 'Stone', parent: 1),
      _term(4, 'Gifts'),
      _term(5, 'Deep', parent: 2),
    ];

Map<String, dynamic> _row(int id, String name, List<int> categories) => {
      'id': id,
      'name': name,
      'price': '100.00',
      'regular_price': '100.00',
      'on_sale': false,
      'stock_status': 'instock',
      'categories': categories,
      'images': <Object>[],
    };

CatalogueRepository _products() => CatalogueRepository(
      store: MemoryFeedStore()
        ..rows.addAll({
          1: _row(1, 'Alpha signet', [2]),
          2: _row(2, 'Beta stone', [3]),
          3: _row(3, 'Gamma gift', [4]),
          4: _row(4, 'Delta deep', [5]),
        }),
      fetch: (cursor) async => throw Exception('offline'),
    );

Widget _app(CatalogueRepository products, CategoryRepository? categories, {Locale? locale}) =>
    MaterialApp(
      locale: locale ?? const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: CatalogueListPage(repository: products, categories: categories)),
    );

void main() {
  group('CategoryTree', () {
    test('top level plus one level of children; deeper ones fold into their level-one ancestor', () {
      final tree = CategoryTree([for (final r in _terms()) ProductCategory.tryParse(r)!]);
      expect([for (final c in tree.topLevel) c.name], ['Gifts', 'Rings']);
      expect([for (final c in tree.childrenOf(1)) c.name], ['Signet', 'Stone']);
      expect(tree.childrenOf(4), isEmpty);
      expect(tree.idsUnder(1), {1, 2, 3, 5});
      expect(tree.idsUnder(2), {2});
      expect(tree.idsUnder(4), {4});
    });

    test('an unknown parent is shown at the top level and a parent loop does not hang', () {
      final tree = CategoryTree([
        const ProductCategory(id: 7, name: 'Orphan', parent: 99),
        const ProductCategory(id: 8, name: 'A', parent: 9),
        const ProductCategory(id: 9, name: 'B', parent: 8),
      ]);
      expect([for (final c in tree.topLevel) c.name], ['Orphan']);
    });

    test('malformed rows are ignored', () {
      expect(ProductCategory.tryParse({'name': 'x'}), isNull);
      expect(ProductCategory.tryParse({'id': 0}), isNull);
      expect(ProductCategory.tryParse({'id': '6', 'name': 'Six', 'count': '3'})!.count, 3);
    });
  });

  group('CategoryRepository', () {
    test('refresh replaces the cache; a failed refresh keeps it and throws', () async {
      final store = MemoryFeedStore();
      var fail = false;
      var rows = _terms();
      final repo = CategoryRepository(
        store: store,
        fetch: () async {
          if (fail) throw Exception('offline');
          return rows;
        },
      );
      expect(await repo.categories(), isEmpty);
      await repo.refresh();
      expect(await repo.categories(), hasLength(5));

      fail = true;
      await expectLater(repo.refresh(), throwsException);
      expect(await repo.categories(), hasLength(5));

      // Offline-readable from a second repository over the same durable store.
      final reopened = CategoryRepository(store: store, fetch: () async => throw Exception('x'));
      expect(await reopened.categories(), hasLength(5));

      fail = false;
      rows = [_term(4, 'Gifts')];
      await repo.refresh();
      expect([for (final c in await repo.categories()) c.id], [4]);
    });
  });

  group('catalogue list with categories', () {
    CategoryRepository categoriesOf(MemoryFeedStore store) =>
        CategoryRepository(store: store, fetch: () async => _terms());

    testWidgets('chips filter by category, a parent includes its children', (tester) async {
      await tester.pumpWidget(_app(_products(), categoriesOf(MemoryFeedStore())));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('category-all')), findsOneWidget);
      expect(find.text('Rings'), findsOneWidget);
      expect(find.text('Gifts'), findsOneWidget);
      // Children only appear once their parent is chosen.
      expect(find.text('Signet'), findsNothing);
      for (final n in ['Alpha signet', 'Beta stone', 'Gamma gift', 'Delta deep']) {
        expect(find.text(n), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey<String>('category-1')));
      await tester.pumpAndSettle();
      expect(find.text('Gamma gift'), findsNothing);
      expect(find.text('Alpha signet'), findsOneWidget);
      expect(find.text('Beta stone'), findsOneWidget);
      expect(find.text('Delta deep'), findsOneWidget); // a grandchild is still under Rings
      expect(find.text('Signet'), findsOneWidget);
      expect(find.text('Stone'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('category-3')));
      await tester.pumpAndSettle();
      expect(find.text('Alpha signet'), findsNothing);
      expect(find.text('Beta stone'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('category-all')));
      await tester.pumpAndSettle();
      expect(find.text('Gamma gift'), findsOneWidget);
      expect(find.text('Stone'), findsNothing);
    });

    testWidgets('search works inside the chosen category', (tester) async {
      await tester.pumpWidget(_app(_products(), categoriesOf(MemoryFeedStore())));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('category-1')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey<String>('catalogue-search')), 'BETA');
      await tester.pumpAndSettle();
      expect(find.text('Beta stone'), findsOneWidget);
      expect(find.text('Alpha signet'), findsNothing);

      // A match that lives in another category is not shown.
      await tester.enterText(find.byKey(const ValueKey<String>('catalogue-search')), 'gamma');
      await tester.pumpAndSettle();
      expect(find.text('Gamma gift'), findsNothing);
      expect(find.text('No products match. Try another category or search.'), findsOneWidget);
    });

    testWidgets('offline: saved categories still show and filter', (tester) async {
      final store = MemoryFeedStore();
      await categoriesOf(store).refresh();
      final offline = CategoryRepository(store: store, fetch: () async => throw Exception('offline'));
      await tester.pumpWidget(_app(_products(), offline));
      await tester.pumpAndSettle();
      expect(find.text('Rings'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('category-4')));
      await tester.pumpAndSettle();
      expect(find.text('Gamma gift'), findsOneWidget);
      expect(find.text('Alpha signet'), findsNothing);
    });

    testWidgets('without categories the list has no chips', (tester) async {
      await tester.pumpWidget(_app(_products(), null));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('category-all')), findsNothing);
      expect(find.text('Alpha signet'), findsOneWidget);
    });

    testWidgets('Arabic: right-to-left chips with translated labels', (tester) async {
      await tester.pumpWidget(
          _app(_products(), categoriesOf(MemoryFeedStore()), locale: const Locale('ar')));
      await tester.pumpAndSettle();
      expect(find.text('الكل'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('الكل'))), TextDirection.rtl);
      // The first chip sits at the right edge in RTL.
      final all = tester.getTopRight(find.byKey(const ValueKey<String>('category-all')));
      final rings = tester.getTopRight(find.byKey(const ValueKey<String>('category-1')));
      expect(all.dx > rings.dx, isTrue);
    });
  });

  group('product page stock line and size labels', () {
    Widget page(Product p, {Locale locale = const Locale('en')}) => MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProductPage(product: p),
        );

    testWidgets('the size picker shows the term label, not the slug', (tester) async {
      await tester.pumpWidget(page(Product.fromRecord(sizedRecord())));
      await tester.scrollUntilVisible(find.byKey(const ValueKey<String>('variation-212')), 200);
      expect(find.text('7.5'), findsOneWidget);
      expect(find.text('7-5'), findsNothing);
      expect(find.text('Size'), findsOneWidget);
    });

    testWidgets('without labels the slug is shown (older server)', (tester) async {
      final record = sizedRecord()..remove('variation_attributes');
      await tester.pumpWidget(page(Product.fromRecord(record)));
      await tester.scrollUntilVisible(find.byKey(const ValueKey<String>('variation-212')), 200);
      expect(find.text('7-5'), findsOneWidget);
    });

    testWidgets('a non-size attribute is headed with the shop label', (tester) async {
      final record = sizedRecord();
      record['variation_attributes'] = [
        {
          'key': 'pa_metal',
          'label': 'Metal',
          'options': [
            {'value': 'silver', 'label': 'Sterling silver'},
          ],
        },
      ];
      record['variations'] = [
        {'id': 1, 'attributes': {'pa_metal': 'silver'}, 'price': '10.00', 'stock_status': 'instock', 'stock': null},
        {'id': 2, 'attributes': {'pa_metal': 'silver'}, 'price': '10.00', 'stock_status': 'instock', 'stock': null},
      ];
      await tester.pumpWidget(page(Product.fromRecord(record)));
      await tester.scrollUntilVisible(find.byKey(const ValueKey<String>('variation-1')), 200);
      expect(find.text('Metal'), findsOneWidget);
      expect(find.text('Sterling silver'), findsWidgets);
    });

    testWidgets('no stock number: plain In stock; a number that arrives still says Only N left',
        (tester) async {
      await tester.pumpWidget(page(Product.fromRecord(simpleRecord())));
      await tester.scrollUntilVisible(find.text('In stock'), 200);
      expect(find.text('In stock'), findsOneWidget);

      final counted = simpleRecord()..['stock'] = 2;
      await tester.pumpWidget(page(Product.fromRecord(counted)));
      await tester.scrollUntilVisible(find.text('Only 2 left'), 200);
      expect(find.text('Only 2 left'), findsOneWidget);
    });

    testWidgets('prices show the item currency code', (tester) async {
      final record = simpleRecord()..['currency'] = 'OMR';
      await tester.pumpWidget(page(Product.fromRecord(record)));
      expect(find.text('OMR 120.00'), findsOneWidget);
    });
  });
}
