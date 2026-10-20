import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_store/src/app.dart';
import 'package:yazan_store/src/cart/store_api.dart';
import 'package:yazan_store/src/verify/verify_page.dart';

import 'fixtures/account_fakes.dart';
import 'fixtures/catalogue_fixtures.dart';
import 'fixtures/scripted_client.dart';
import 'fixtures/store_cart.dart';

/// The whole app as a guest: the More menu is in the app bar next to favourites, orders and the cart.
Future<void> _openApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final tokens = MemoryTokenStore();
  final cartServer = FakeTransport((r) => ok(storeCart(images: false)));
  await tester.pumpWidget(YazanApp(
    client: ScriptedClient(tokens),
    tokens: tokens,
    repository: catalogueOf([simpleRecord()]),
    storeApi: StoreApi(cartServer.call),
    accountApi: FakeAccountApi(),
    wishlistApi: FakeWishlistApi(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the shop has a More menu with ring verification and rewards', (tester) async {
    await _openApp(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Verify a ring'), findsOneWidget);
    expect(find.text('Rewards'), findsOneWidget);
  });

  testWidgets('a guest can open the ring check without signing in', (tester) async {
    await _openApp(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify a ring'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyPage), findsOneWidget);
    expect(find.text('Sign in to use this'), findsNothing);
    // No camera plugin is part of the app yet: typing is the way in.
    expect(find.text('Scan QR code'), findsNothing);
  });

  testWidgets('a guest tapping Rewards gets the same "Sign in to use this" prompt as favourites', (tester) async {
    await _openApp(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rewards'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to use this'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to use this'), findsNothing);
    expect(find.text('Carnelian ring'), findsOneWidget);
  });
}
