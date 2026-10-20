import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_store/src/app.dart';
import 'package:yazan_store/src/cart/store_api.dart';

import 'fixtures/account_fakes.dart';
import 'fixtures/catalogue_fixtures.dart';
import 'fixtures/scripted_client.dart';
import 'fixtures/store_cart.dart';

/// Serves the fixture cart (and the checkout success) and always hands out the same Cart-Token.
StoreResponse _serve(SentRequest r) {
  final headers = {'Cart-Token': 'tok-1'};
  if (r.path.endsWith('/checkout')) return ok(checkoutSuccess(), headers: headers);
  return ok(storeCart(images: false), headers: headers);
}

typedef _Harness = ({
  FakeTransport cart,
  ScriptedClient client,
  MemoryTokenStore tokens,
  FakeWishlistApi wishlist,
  FakeAccountApi account,
  MemoryCartTokenStore cartTokens,
});

/// Opens the whole app with NO account: nothing is stored, nothing is signed in.
Future<_Harness> _openAsGuest(
  WidgetTester tester, {
  List<Map<String, dynamic>>? records,
}) async {
  // A tall screen keeps the buttons clear of the snack bars these flows raise.
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final tokens = MemoryTokenStore();
  final client = ScriptedClient(tokens);
  final cart = FakeTransport(_serve);
  final wishlist = FakeWishlistApi([ring(1, 'Alpha ring')]);
  final account = FakeAccountApi();
  final cartTokens = MemoryCartTokenStore();
  await tester.pumpWidget(YazanApp(
    client: client,
    tokens: tokens,
    repository: catalogueOf(records ?? [simpleRecord()]),
    storeApi: StoreApi(cart.call, tokens: cartTokens),
    accountApi: account,
    wishlistApi: wishlist,
  ));
  await tester.pumpAndSettle();
  return (
    cart: cart,
    client: client,
    tokens: tokens,
    wishlist: wishlist,
    account: account,
    cartTokens: cartTokens,
  );
}

Future<void> _openProduct(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> _tapAddToCart(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Add to cart'), 200);
  await tester.tap(find.text('Add to cart'));
  await tester.pumpAndSettle();
}

/// Signs in through the form that is on screen (the customer chose to).
Future<void> _fillSignIn(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'noor@yazan.test');
  await tester.enterText(find.byType(TextField).at(1), 'secret-password');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  group('a guest with no account', () {
    testWidgets('browses, adds to the cart and pays cash on delivery without ever signing in',
        (tester) async {
      final app = await _openAsGuest(tester);
      expect(find.text('Carnelian ring'), findsOneWidget);

      await _openProduct(tester, 'Carnelian ring');
      await _tapAddToCart(tester);
      expect(find.text('Added to your cart'), findsOneWidget);
      // Launch read the cart (and got the device's Cart-Token); the add used that token.
      expect(app.cart.requests.map((r) => '${r.method} ${r.path}').toList(),
          ['GET /wc/store/v1/cart', 'POST /wc/store/v1/cart/add-item']);
      final add = app.cart.requests.last;
      expect(add.body, {'id': 13, 'quantity': 1});
      expect(add.headers['Cart-Token'], 'tok-1');
      expect(app.cartTokens.token, 'tok-1');

      // View cart -> Checkout -> Place order, all as a guest.
      await tester.tap(find.text('View cart'));
      await tester.pumpAndSettle();
      expect(find.text('Carnelian & Silver Ring'), findsOneWidget);
      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Place order'));
      await tester.pumpAndSettle();
      expect(find.text('Order number 1042'), findsOneWidget);

      final checkout = app.cart.requests.last;
      expect(checkout.path, '/wc/store/v1/checkout');
      expect(checkout.headers['Cart-Token'], 'tok-1');
      expect(checkout.headers['Idempotency-Key'], isNotNull);
      // Nobody signed in at any point.
      expect(await app.tokens.read(), isNull);
      expect(app.client.logins, isEmpty);
      expect(app.wishlist.calls, isEmpty);
      expect(app.account.calls, isEmpty);
    });

    testWidgets('tapping Favourites asks to sign in and "Not now" leaves everything as it was',
        (tester) async {
      final app = await _openAsGuest(tester);

      await tester.tap(find.byTooltip('Favourites'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to use this'), findsOneWidget);
      expect(find.text('Favourites and your orders are kept in your account. You can browse and buy without one.'),
          findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to use this'), findsNothing);
      expect(find.text('Carnelian ring'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(app.wishlist.calls, isEmpty);
    });

    testWidgets('tapping My orders asks to sign in and fetches nothing', (tester) async {
      final app = await _openAsGuest(tester);

      await tester.tap(find.byTooltip('My orders'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to use this'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to use this'), findsNothing);
      expect(app.account.calls, isEmpty);
    });

    testWidgets('the heart on a product page asks to sign in too', (tester) async {
      final app = await _openAsGuest(tester);
      await _openProduct(tester, 'Carnelian ring');

      await tester.tap(find.byTooltip('Save to favourites'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to use this'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Save to favourites'), findsOneWidget);
      expect(app.wishlist.calls, isEmpty);
    });

    testWidgets('the prompt offers sign-in: signing in opens the favourites and keeps the cart',
        (tester) async {
      final app = await _openAsGuest(tester);
      expect(app.cartTokens.token, 'tok-1', reason: 'the guest cart token is held');

      await tester.tap(find.byTooltip('Favourites'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      await _fillSignIn(tester);

      // Signed in: the favourites page opened with the account's list.
      expect(app.client.logins, ['noor@yazan.test']);
      expect(find.text('Alpha ring'), findsOneWidget);
      // The cart token survived the sign-in and was used to reload the same cart.
      expect(app.cartTokens.token, 'tok-1');
      final reload = app.cart.requests.last;
      expect(reload.method, 'GET');
      expect(reload.headers['Cart-Token'], 'tok-1');
    });

    testWidgets('signing in and out leaves the cart working as a guest', (tester) async {
      final app = await _openAsGuest(tester);

      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await _fillSignIn(tester);
      expect(find.text('Password'), findsNothing);

      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      // Signing out dropped the cart token so the next customer starts clean ...
      expect(app.cartTokens.token, isNull);

      // ... and the guest cart still works: a fresh token is asked for and then kept.
      await _openProduct(tester, 'Carnelian ring');
      await _tapAddToCart(tester);
      expect(find.text('Added to your cart'), findsOneWidget);
      final add = app.cart.requests.last;
      expect(add.path, '/wc/store/v1/cart/add-item');
      expect(add.headers.containsKey('Cart-Token'), isFalse);
      expect(app.cartTokens.token, 'tok-1');
    });
  });

  group('size picker', () {
    Future<void> showChip(WidgetTester tester, int id) => tester.scrollUntilVisible(
        find.byKey(ValueKey<String>('variation-$id')), 200);

    testWidgets('a variable product asks for a size and sends the chosen variation', (tester) async {
      final app = await _openAsGuest(tester, records: [sizedRecord()]);
      await _openProduct(tester, 'Aqeeq Signet');

      await showChip(tester, 211);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('7.5'), findsOneWidget);
      expect(find.text('9 - Sold'), findsOneWidget);
      // A sold-out size is shown but cannot be picked.
      final soldChip = tester.widget<ChoiceChip>(find.byKey(const ValueKey<String>('variation-213')));
      expect(soldChip.onSelected, isNull);

      // No size chosen yet: nothing is sent, and the customer is told why.
      final before = app.cart.requests.length;
      await _tapAddToCart(tester);
      expect(find.text('Please choose a size first.'), findsOneWidget);
      expect(app.cart.requests.length, before);

      await showChip(tester, 212);
      await tester.tap(find.byKey(const ValueKey<String>('variation-212')));
      await tester.pumpAndSettle();
      expect(find.text('USD 130.00'), findsOneWidget); // the size's own price
      await _tapAddToCart(tester);

      final add = app.cart.requests.last;
      expect(add.path, '/wc/store/v1/cart/add-item');
      expect(add.body, {
        'id': 212,
        'quantity': 1,
        'variation': [
          {'attribute': 'pa_size', 'value': '7-5'},
        ],
      });
      expect(find.text('Added to your cart'), findsOneWidget);
    });

    testWidgets('Arabic: the picker is right-to-left with a translated heading', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ar')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await _openAsGuest(tester, records: [sizedRecord()]);
      await _openProduct(tester, 'Aqeeq Signet');

      await showChip(tester, 211);
      expect(find.text('المقاس'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('المقاس'))), TextDirection.rtl);
    });

    testWidgets('a variable product with a single size selects it by itself', (tester) async {
      final record = sizedRecord();
      record['variations'] = [(record['variations'] as List<Object?>).first];
      final app = await _openAsGuest(tester, records: [record]);
      await _openProduct(tester, 'Aqeeq Signet');
      await _tapAddToCart(tester);
      expect(app.cart.requests.last.body, {
        'id': 211,
        'quantity': 1,
        'variation': [
          {'attribute': 'pa_size', 'value': '7'},
        ],
      });
    });
  });
}
