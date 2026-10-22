import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/src/app.dart';
import 'package:yazan_store/src/cart/store_api.dart';
import 'package:yazan_store/src/wishlist/wishlist_mirror.dart';

import 'fixtures/account_fakes.dart';
import 'fixtures/catalogue_fixtures.dart';
import 'fixtures/scripted_client.dart';
import 'fixtures/sign_in_steps.dart';
import 'fixtures/store_cart.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ScriptedClient client,
  required TokenStore tokens,
  required FakeWishlistApi wishlist,
  WishlistMirror? mirror,
}) async {
  final cartServer = FakeTransport((r) => ok(storeCart(images: false)));
  await tester.pumpWidget(YazanApp(
    client: client,
    tokens: tokens,
    repository: catalogueOf(const []),
    storeApi: StoreApi(cartServer.call),
    accountApi: FakeAccountApi(),
    wishlistApi: wishlist,
    wishlistMirror: mirror,
  ));
  await tester.pumpAndSettle();
}

/// A guest reaches the (optional) sign-in screen through the Account entry in the app bar.
Future<void> _openSignIn(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Account'));
  await tester.pumpAndSettle();
}

/// Email, Continue (the scripted lookup finds the account), password, Sign in.
Future<void> _signInAs(WidgetTester tester, String email) =>
    signInWithEmail(tester, email: email);

void main() {
  group('sign-in', () {
    testWidgets('a wrong password gets a polite generic message', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)
        ..loginError = const ApiError(status: 401, code: 'yazan_mobile_bad_login');
      await _pump(tester, client: client, tokens: tokens, wishlist: FakeWishlistApi());

      await _openSignIn(tester);
      await _signInAs(tester, 'noor@yazan.test');
      expect(client.logins, ['noor@yazan.test']);
      expect(find.text('The details are not right. Please try again.'), findsOneWidget);
      // Still on the sign-in form, and still a guest.
      expect(find.text('Password'), findsOneWidget);
      expect(await tokens.read(), isNull);
    });

    testWidgets('too many attempts and an unexpected answer each get their own message', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)
        ..loginError = const ApiError(status: 429, code: 'yazan_rate_limited', retryAfter: 30);
      await _pump(tester, client: client, tokens: tokens, wishlist: FakeWishlistApi());

      await _openSignIn(tester);
      await _signInAs(tester, 'noor@yazan.test');
      expect(find.text('Too many attempts. Please wait and try again.'), findsOneWidget);

      client.loginError = const ApiError(status: 403, code: 'yazan_mobile_wrong_app');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('This is not available in the app.'), findsOneWidget);

      // An answer the screen has no message for: generic text plus the code, for the owner to report.
      client.loginError = const ApiError(status: 500, code: 'boom');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('(code: boom, 500)'), findsOneWidget);

      // The route missing on the server: the website is not updated for the app yet (no code shown).
      client.loginError = const ApiError(status: 404, code: 'rest_no_route');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('The website is not updated for the app yet. Please try again later.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('sign-in-error-code')), findsNothing);
    });

    testWidgets('no connection and a timeout get the connection message', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)
        ..loginException = DioException(
            requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError);
      await _pump(tester, client: client, tokens: tokens, wishlist: FakeWishlistApi());

      await _openSignIn(tester);
      await _signInAs(tester, 'noor@yazan.test');
      expect(find.text('Could not reach the website. Check your connection and try again.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('sign-in-error-code')), findsNothing);

      client.loginException = TimeoutException('slow');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the website. Check your connection and try again.'),
          findsOneWidget);
      expect(await tokens.read(), isNull);
    });

    testWidgets('a good sign-in returns to the shop, loads the favourites and opens the account next time',
        (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens);
      final wishlist = FakeWishlistApi([ring(1, 'Alpha ring')]);
      await _pump(tester, client: client, tokens: tokens, wishlist: wishlist);
      expect(wishlist.calls, isEmpty, reason: 'no favourites are fetched for a guest');

      await _openSignIn(tester);
      await _signInAs(tester, 'noor@yazan.test');
      // The sign-in form closed itself; the shop is on screen and the favourites were fetched.
      expect(find.text('Password'), findsNothing);
      expect(find.byTooltip('Account'), findsOneWidget);
      expect(wishlist.calls, ['list']);

      // The Account entry now opens the account, not the sign-in form.
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(find.text('Noor Ali'), findsOneWidget);
    });
  });

  group('sign-out', () {
    testWidgets('from the account page: ends the session, returns to the shop as a guest, forgets the favourites',
        (tester) async {
      final tokens = MemoryTokenStore();
      await tokens.write(Session.fromJson(
          {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
      final client = ScriptedClient(tokens);
      final mirror = MemoryWishlistMirror();
      await _pump(
        tester,
        client: client,
        tokens: tokens,
        wishlist: FakeWishlistApi([ring(1, 'Alpha ring')]),
        mirror: mirror,
      );
      // Signed in: the favourites were fetched and copied to the phone.
      expect(mirror.items, isNotNull);
      expect(mirror.items!.length, 1);

      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(find.text('Noor Ali'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(client.loggedOut, isTrue);
      expect(await tokens.read(), isNull);
      expect(mirror.items, isNull);
      // Back on the shop, not on a sign-in wall; the app keeps working as a guest.
      expect(find.text('Sign out'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsNothing);
      expect(find.byTooltip('Cart'), findsOneWidget);
      await tester.tap(find.byTooltip('Favourites'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to use this'), findsOneWidget);
    });

    testWidgets('a sign-out the client could not finish still ends the session through the client',
        (tester) async {
      final tokens = MemoryTokenStore();
      await tokens.write(Session.fromJson(
          {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
      final client = ScriptedClient(tokens)..logoutError = StateError('no connection');
      await _pump(
        tester,
        client: client,
        tokens: tokens,
        wishlist: FakeWishlistApi([ring(1, 'Alpha ring')]),
      );

      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(client.loggedOut, isTrue);
      // Cleared by the client (so a refresh in flight cannot write it back), not the store directly.
      expect(client.clearedSessions, 1);
      expect(await tokens.read(), isNull);
      expect(find.text('Sign out'), findsNothing);
      expect(find.byTooltip('Cart'), findsOneWidget);
    });
  });

  testWidgets('favourites reachable from the app bar and the account page', (tester) async {
    final tokens = MemoryTokenStore();
    await tokens.write(Session.fromJson(
        {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
    await _pump(
      tester,
      client: ScriptedClient(tokens),
      tokens: tokens,
      wishlist: FakeWishlistApi([ring(1, 'Alpha ring')]),
    );

    await tester.tap(find.byTooltip('Favourites'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha ring'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favourites'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha ring'), findsOneWidget);
  });
}
