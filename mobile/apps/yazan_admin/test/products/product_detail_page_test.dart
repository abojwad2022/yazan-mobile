import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/products/product_detail_page.dart';
import 'package:yazan_admin/src/products/product_permissions.dart';
import 'package:yazan_admin/src/products/product_summary.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../orders/fakes.dart' show KeySeq;
import 'fakes.dart';

final ProductSummary _summary = ProductSummary.fromJson(const {
  'id': 7,
  'type': 'simple',
  'name': 'Agate Ring',
  'sku': 'YZ-100',
  'price': '120.00',
  'regular_price': '120.00',
  'sale_price': '',
  'stock_status': 'instock',
  'stock': 3,
});

Widget _host(
  Locale locale,
  FakeProductServer server, {
  ProductPermissions? permissions,
  PermissionsLoader? loadPermissions,
}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProductDetailPage(
        summary: _summary,
        load: server.load,
        write: server.write,
        permissions: permissions ?? ProductPermissions.of(allProductPermissions),
        loadPermissions: loadPermissions,
        newKey: KeySeq().next,
      ),
    );

/// A tall surface so the edit card is on screen without scrolling.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(ValueKey(key)), text);
  await tester.pump();
}

const ApiError _stale = ApiError(status: 412, code: 'yazan_precondition_failed', current: 'v2');

void main() {
  testWidgets('shows the product, its price and its stock (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer()..sale = '99.00';
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();
    expect(find.text('SKU: YZ-100'), findsOneWidget);
    expect(find.text('120.00'), findsOneWidget);
    expect(find.text('99.00'), findsOneWidget);
    expect(find.text('In stock: 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-price')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-stock')), findsOneWidget);
    expect(
      find.text('Price and stock changes need a connection and are never saved offline.'),
      findsOneWidget,
    );
  });

  testWidgets('editing the stock asks to confirm, then sends If-Match once (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer();
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('edit-stock'));
    await _enter(tester, 'stock-field', '5');
    await _tap(tester, const ValueKey('stock-save'));
    // Nothing is sent before the confirmation.
    expect(server.writes, isEmpty);
    expect(find.textContaining('to 5?'), findsOneWidget);
    expect(find.textContaining('It is 3 now'), findsOneWidget);

    await _tap(tester, const ValueKey('confirm-change'));
    expect(server.writes.length, 1);
    expect(server.writes.single.fields, {'stock_quantity': 5, 'original_stock_quantity': 3});
    expect(server.writes.single.version, 'v1');
    expect(server.writes.single.key, 'key-1');
    expect(find.text('Product updated.'), findsOneWidget);
    expect(find.text('In stock: 5'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation sends nothing', (tester) async {
    _tallView(tester);
    final server = FakeProductServer();
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('edit-stock'));
    await _enter(tester, 'stock-field', '9');
    await _tap(tester, const ValueKey('stock-save'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.writes, isEmpty);
    expect(find.text('In stock: 3'), findsOneWidget);
  });

  testWidgets('a quantity that is not a whole number is refused in the dialog (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer();
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('edit-stock'));
    await _enter(tester, 'stock-field', '2.5');
    await _tap(tester, const ValueKey('stock-save'));
    expect(find.text('Enter a whole number, zero or more.'), findsOneWidget);
    expect(find.byKey(const ValueKey('confirm-change')), findsNothing);
    expect(server.writes, isEmpty);
  });

  testWidgets('editing the price with a sale price (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer();
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('edit-price'));
    await _enter(tester, 'regular-price-field', '150');
    await _enter(tester, 'sale-price-field', '129.5');
    await _tap(tester, const ValueKey('price-save'));
    expect(find.textContaining('150.00'), findsOneWidget);
    expect(find.textContaining('129.50'), findsOneWidget);
    await _tap(tester, const ValueKey('confirm-change'));

    expect(server.writes.single.fields, {'regular_price': '150.00', 'sale_price': '129.50'});
    expect(server.writes.single.version, 'v1');
    expect(find.text('Product updated.'), findsOneWidget);
    expect(find.byKey(const ValueKey('sale-price')), findsOneWidget);
  });

  testWidgets('price rules: zero is refused, and a sale price must be lower (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer();
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('edit-price'));
    await _enter(tester, 'regular-price-field', '0');
    await _tap(tester, const ValueKey('price-save'));
    expect(find.text('Enter a price greater than zero, for example 129.50.'), findsOneWidget);

    await _enter(tester, 'regular-price-field', '100');
    await _enter(tester, 'sale-price-field', '100');
    await _tap(tester, const ValueKey('price-save'));
    expect(find.text('Enter a sale price lower than the regular price, or leave it empty.'), findsOneWidget);
    expect(server.writes, isEmpty);
  });

  testWidgets('Arabic digits typed on an Arabic keyboard are understood, and the page is RTL (ar)',
      (tester) async {
    _tallView(tester);
    final server = FakeProductServer();
    await tester.pumpWidget(_host(const Locale('ar'), server));
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(find.byKey(const ValueKey('edit-price')))), TextDirection.rtl);

    await _tap(tester, const ValueKey('edit-price'));
    await _enter(tester, 'regular-price-field', '١٥٠٫٥٠');
    await _tap(tester, const ValueKey('price-save'));
    await _tap(tester, const ValueKey('confirm-change'));

    expect(server.writes.single.fields, {'regular_price': '150.50', 'sale_price': ''});
    expect(find.text('تم تحديث المنتج.'), findsOneWidget);
  });

  testWidgets('offline: nothing is saved on the phone and Try again reuses the key (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer()..writeFailures.addAll([Exception('offline'), null]);
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('edit-stock'));
    await _enter(tester, 'stock-field', '5');
    await _tap(tester, const ValueKey('stock-save'));
    await _tap(tester, const ValueKey('confirm-change'));
    expect(
      find.text('This needs a connection. Nothing was saved on the phone; try again when you are online.'),
      findsOneWidget,
    );
    expect(find.text('In stock: 3'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(server.writes.length, 2);
    expect(server.writes[1].key, server.writes[0].key);
    expect(server.writes[1].version, server.writes[0].version);
    expect(find.text('Product updated.'), findsOneWidget);
    expect(find.text('In stock: 5'), findsOneWidget);
  });

  testWidgets('a 412 opens the conflict screen; overwrite uses the new version (ar)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer()..writeFailures.add(_stale);
    await tester.pumpWidget(_host(const Locale('ar'), server));
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('edit-stock'));
    await _enter(tester, 'stock-field', '5');
    await _tap(tester, const ValueKey('stock-save'));
    // The ring sells on the website while the confirmation is open.
    server
      ..stock = 1
      ..version = 'v2';
    await _tap(tester, const ValueKey('confirm-change'));

    expect(find.text('تغيّر هذا المنتج'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('استبدال بنسختي'));
    await tester.pumpAndSettle();
    expect(server.writes.map((w) => w.version), ['v1', 'v2']);
    expect(server.writes[1].key, isNot(server.writes[0].key));
    expect(server.writes[1].fields['original_stock_quantity'], 1);
    expect(server.stock, 5);
  });

  testWidgets('keep server version shows the server copy and sends nothing more (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer()..writeFailures.add(_stale);
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('edit-price'));
    await _enter(tester, 'regular-price-field', '150');
    await _tap(tester, const ValueKey('price-save'));
    server
      ..regular = '200.00'
      ..version = 'v2';
    await _tap(tester, const ValueKey('confirm-change'));

    expect(find.text('This product changed'), findsOneWidget);
    expect(find.text('150.00'), findsOneWidget);
    expect(find.text('200.00'), findsOneWidget);

    await tester.tap(find.text('Keep server version'));
    await tester.pumpAndSettle();
    expect(find.text('This product changed'), findsNothing);
    expect(server.writes.length, 1);
    expect(find.text('200.00'), findsOneWidget);
  });

  testWidgets('a 200 that did not take the value is reported (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer()..ignorePrice = true;
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('edit-price'));
    await _enter(tester, 'regular-price-field', '150');
    await _tap(tester, const ValueKey('price-save'));
    await _tap(tester, const ValueKey('confirm-change'));
    expect(
      find.text(
          'The store did not apply this change. Check your permission and the current values, then try again.'),
      findsOneWidget,
    );
    expect(find.text('Product updated.'), findsNothing);
  });

  testWidgets('a 403 on the write shows the no-permission message (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer()
      ..writeFailures.add(const ApiError(status: 403, code: 'yazan_forbidden'));
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();

    await _tap(tester, const ValueKey('edit-stock'));
    await _enter(tester, 'stock-field', '5');
    await _tap(tester, const ValueKey('stock-save'));
    await _tap(tester, const ValueKey('confirm-change'));
    expect(find.text('You do not have permission to change this.'), findsOneWidget);
  });

  testWidgets('without change_price the price button is hidden but stock stays (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer();
    await tester.pumpWidget(_host(
      const Locale('en'),
      server,
      permissions: ProductPermissions.of(['products.view', 'products.edit', 'products.change_stock']),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-price')), findsNothing);
    expect(find.byKey(const ValueKey('edit-stock')), findsOneWidget);
  });

  testWidgets('view-only staff see no edit buttons and are told why (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer();
    await tester.pumpWidget(_host(
      const Locale('en'),
      server,
      permissions: ProductPermissions.of(['products.view']),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-price')), findsNothing);
    expect(find.byKey(const ValueKey('edit-stock')), findsNothing);
    expect(find.text('Your account can view this product but not change its price or stock.'), findsOneWidget);
  });

  testWidgets('permissions still unknown: edits stay off and the person is told (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer();
    await tester.pumpWidget(_host(
      const Locale('en'),
      server,
      permissions: const ProductPermissions.unknown(),
      loadPermissions: () async => throw Exception('offline'),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-price')), findsNothing);
    expect(find.byKey(const ValueKey('edit-stock')), findsNothing);
    expect(find.byKey(const ValueKey('edit-note')), findsOneWidget);
  });

  testWidgets('permissions that load on this screen turn the edits on (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer();
    await tester.pumpWidget(_host(
      const Locale('en'),
      server,
      permissions: const ProductPermissions.unknown(),
      loadPermissions: () async => FakeProductServer.me(allProductPermissions),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-price')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-stock')), findsOneWidget);
  });

  testWidgets('a product with sizes cannot be edited here (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer()..type = 'variable';
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-price')), findsNothing);
    expect(find.byKey(const ValueKey('edit-stock')), findsNothing);
    expect(
      find.text('This product has sizes. Change the price and stock of each size on the website for now.'),
      findsOneWidget,
    );
  });

  testWidgets('stock that is not counted by quantity has no stock button (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer()
      ..manageStock = false
      ..stock = null;
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-price')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-stock')), findsNothing);
    expect(
      find.text('Stock for this product is not counted by quantity, so it cannot be edited here.'),
      findsOneWidget,
    );
  });

  testWidgets('a 403 on the read shows the no-access state (en)', (tester) async {
    final server = FakeProductServer()..loadError = const ApiError(status: 403, code: 'yazan_forbidden');
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();
    expect(find.text('No access'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-stock')), findsNothing);
  });

  testWidgets('a failed read offers Try again (en)', (tester) async {
    _tallView(tester);
    final server = FakeProductServer()..loadError = Exception('offline');
    await tester.pumpWidget(_host(const Locale('en'), server));
    await tester.pumpAndSettle();
    expect(find.text('Could not load the product details.'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-stock')), findsNothing);

    server.loadError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load the product details.'), findsNothing);
    expect(find.byKey(const ValueKey('edit-stock')), findsOneWidget);
  });
}
