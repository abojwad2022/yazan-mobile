import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_store/l10n/app_localizations.dart';
import 'package:yazan_store/src/cart/cart.dart';
import 'package:yazan_store/src/cart/cart_controller.dart';
import 'package:yazan_store/src/cart/cart_page.dart';
import 'package:yazan_store/src/cart/cart_scope.dart';
import 'package:yazan_store/src/cart/checkout_page.dart';
import 'package:yazan_store/src/cart/store_api.dart';
import 'package:yazan_store/src/catalogue/product.dart';
import 'package:yazan_store/src/catalogue/product_page.dart';

import 'fixtures/store_cart.dart';

Widget _app(Widget home, Locale locale, {CartController? scope}) {
  final app = MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
  return scope == null ? app : CartScope(controller: scope, child: app);
}

/// Serves the fixture cart; update-item answers with the new quantity on the first line.
FakeTransport _cartServer() => FakeTransport((r) {
      final cart = storeCart(images: false);
      if (r.path.endsWith('/cart/update-item')) {
        final body = r.body as Map<String, dynamic>;
        final items = cart['items'] as List<dynamic>;
        (items.first as Map<String, dynamic>)['quantity'] = body['quantity'];
      }
      return ok(cart, headers: {'Cart-Token': 'tok-1'});
    });

void main() {
  testWidgets('English cart: lines, server totals, quantity change and checkout', (tester) async {
    final fake = _cartServer();
    final controller = CartController(StoreApi(fake.call));
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(CartPage(controller: controller), const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Cart'), findsOneWidget);
    expect(find.text('Carnelian & Silver Ring'), findsOneWidget);
    expect(find.text('USD 240.00'), findsOneWidget);
    expect(find.text('USD 90.00'), findsOneWidget);
    expect(find.text('Checkout'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('USD 340.00'), 100);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('USD 330.00'), findsOneWidget); // subtotal
    expect(find.text('USD 10.00'), findsOneWidget); // shipping

    await tester.scrollUntilVisible(find.text('Carnelian & Silver Ring'), -100);
    await tester.tap(find.byTooltip('Increase quantity').first);
    await tester.pumpAndSettle();
    final update = fake.requests.last;
    expect(update.path, '/wc/store/v1/cart/update-item');
    expect(update.body, {'key': 'c51ce410c124a10e0db5e4b97fc2af39', 'quantity': 3});
    expect(update.headers['Cart-Token'], 'tok-1');
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('Arabic cart renders right-to-left with translated labels', (tester) async {
    final controller = CartController(StoreApi(_cartServer().call));
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(CartPage(controller: controller), const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.text('السلة'), findsOneWidget);
    expect(find.text('إتمام الطلب'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('الإجمالي'), 100);
    expect(find.text('الإجمالي'), findsOneWidget);
    expect(find.text('USD 340.00'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.text('السلة')));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('a server stock error is shown and the cart stays', (tester) async {
    final fake = _cartServer();
    final controller = CartController(StoreApi(fake.call));
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(CartPage(controller: controller), const Locale('en')));
    await tester.pumpAndSettle();

    fake.handler = (r) => failResponse(
          400,
          'woocommerce_rest_product_partially_out_of_stock',
          'Not enough units of Carnelian &amp; Silver Ring are available.',
        );
    await tester.tap(find.byTooltip('Increase quantity').first);
    await tester.pumpAndSettle();

    expect(find.text('Not enough units of Carnelian & Silver Ring are available.'), findsOneWidget);
    expect(find.text('Carnelian & Silver Ring'), findsOneWidget);
  });

  testWidgets('offline: the cart says it needs a connection and offers a retry', (tester) async {
    final fake = FakeTransport((r) => throw Exception('offline'));
    final controller = CartController(StoreApi(fake.call));
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(CartPage(controller: controller), const Locale('en')));
    await tester.pumpAndSettle();

    expect(
      find.text('You are offline. The cart and checkout need an internet connection.'),
      findsOneWidget,
    );
    fake.handler = (r) => ok(storeCart(images: false));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Carnelian & Silver Ring'), findsOneWidget);
  });

  testWidgets('checkout: offline message, then a retry with the same key places the order',
      (tester) async {
    var offline = true;
    final fake = FakeTransport((r) {
      if (offline) throw Exception('offline');
      return ok(checkoutSuccess());
    });
    final controller = CartController(StoreApi(fake.call));
    addTearDown(controller.dispose);
    final cart = Cart.fromJson(storeCart(images: false));
    await tester.pumpWidget(_app(
      CheckoutPage(controller: controller, cart: cart),
      const Locale('en'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Place order'), findsOneWidget);
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();
    expect(
      find.text('You are offline. Your details are kept; place the order when you are back online.'),
      findsOneWidget,
    );

    offline = false;
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();
    expect(find.text('Order number 1042'), findsOneWidget);

    expect(fake.requests, hasLength(2));
    final key = fake.requests[0].headers['Idempotency-Key'];
    expect(key, isNotNull);
    expect(fake.requests[1].headers['Idempotency-Key'], key);
    final body = fake.requests[1].body as Map<String, dynamic>;
    expect(body['payment_method'], 'cod');
    expect((body['billing_address'] as Map<String, dynamic>)['city'], 'Dearborn');
  });

  testWidgets('product page: add to cart sends the product to the server', (tester) async {
    final fake = _cartServer();
    final controller = CartController(StoreApi(fake.call));
    addTearDown(controller.dispose);
    const ring = Product(id: 13, name: 'Carnelian ring');
    await tester.pumpWidget(_app(
      const ProductPage(product: ring),
      const Locale('en'),
      scope: controller,
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Add to cart'), 200);
    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    expect(fake.requests.single.path, '/wc/store/v1/cart/add-item');
    expect(fake.requests.single.body, {'id': 13, 'quantity': 1});
    expect(find.text('Added to your cart'), findsOneWidget);
    expect(controller.count, 3);
  });

  testWidgets('product page: a sold-out product cannot be added', (tester) async {
    final controller = CartController(StoreApi(_cartServer().call));
    addTearDown(controller.dispose);
    const sold = Product(id: 14, name: 'Sold ring', stockStatus: 'outofstock');
    await tester.pumpWidget(_app(
      const ProductPage(product: sold),
      const Locale('en'),
      scope: controller,
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Add to cart'), 200);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add to cart'));
    expect(button.onPressed, isNull);
  });
}
