import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/src/app.dart';
import 'package:yazan_store/src/cart/store_api.dart';

import 'fixtures/account_fakes.dart';
import 'fixtures/catalogue_fixtures.dart';
import 'fixtures/scripted_client.dart';
import 'fixtures/store_cart.dart';

void main() {
  testWidgets('with no account the app opens on the catalogue, not on a sign-in form',
      (tester) async {
    final tokens = MemoryTokenStore();
    final cartServer = FakeTransport((r) => ok(storeCart(images: false)));
    await tester.pumpWidget(YazanApp(
      client: ScriptedClient(tokens),
      tokens: tokens,
      repository: catalogueOf([simpleRecord(name: 'Carnelian ring')]),
      storeApi: StoreApi(cartServer.call),
      accountApi: FakeAccountApi(),
      wishlistApi: FakeWishlistApi(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Carnelian ring'), findsOneWidget);
    expect(
          find.byWidgetPredicate((w) => w is TextField && w.obscureText),
          findsNothing);
    expect(find.text('Password'), findsNothing);
    // The app bar offers the account entry and the cart even though nobody is signed in.
    expect(find.byTooltip('Account'), findsOneWidget);
    expect(find.byTooltip('Cart'), findsOneWidget);
    // The guest's cart (the device's Cart-Token) is loaded at launch; no favourites without an account.
    expect(cartServer.requests.single.path, '/wc/store/v1/cart');
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('Arabic locale renders the catalogue right-to-left', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ar')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final tokens = MemoryTokenStore();
    await tester.pumpWidget(YazanApp(
      client: ScriptedClient(tokens),
      tokens: tokens,
      repository: catalogueOf([simpleRecord(name: 'Carnelian ring')]),
      storeApi: StoreApi(FakeTransport((r) => ok(storeCart(images: false))).call),
      accountApi: FakeAccountApi(),
      wishlistApi: FakeWishlistApi(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('يزن'), findsOneWidget);
    expect(find.byTooltip('الحساب'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.text('يزن')));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('the account entry opens the sign-in form, which says signing in is optional',
      (tester) async {
    final tokens = MemoryTokenStore();
    await tester.pumpWidget(YazanApp(
      client: ScriptedClient(tokens),
      tokens: tokens,
      repository: catalogueOf(const []),
      storeApi: StoreApi(FakeTransport((r) => ok(storeCart(images: false))).call),
      accountApi: FakeAccountApi(),
      wishlistApi: FakeWishlistApi(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Signing in is optional. You can browse and order without an account.'),
        findsOneWidget);

    // Back returns to the shop; nothing was required.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Password'), findsNothing);
    expect(find.byTooltip('Account'), findsOneWidget);
  });

  testWidgets('a stored session also opens the catalogue, with favourites loaded and the cart badge',
      (tester) async {
    final tokens = MemoryTokenStore();
    await tokens.write(Session.fromJson(
        {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
    final cartServer = FakeTransport((r) => ok(storeCart(images: false)));
    final wishlist = FakeWishlistApi();
    await tester.pumpWidget(YazanApp(
      client: ScriptedClient(tokens),
      tokens: tokens,
      repository: catalogueOf(const []),
      storeApi: StoreApi(cartServer.call),
      accountApi: FakeAccountApi(),
      wishlistApi: wishlist,
    ));
    await tester.pumpAndSettle();
    // Account and favourites are reachable from the app bar; sign-out lives on the account page.
    expect(find.byTooltip('Account'), findsOneWidget);
    expect(find.byTooltip('Favourites'), findsOneWidget);
    // The cart loads once at launch and its count shows on the app bar badge.
    expect(cartServer.requests.single.path, '/wc/store/v1/cart');
    expect(find.byTooltip('Cart'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(wishlist.calls, ['list']);
  });
}
