import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/src/app.dart';
import 'package:yazan_store/src/cart/store_api.dart';
import 'package:yazan_store/src/catalogue/catalogue_repository.dart';
import 'package:yazan_store/src/wishlist/wishlist_mirror.dart';

import 'fixtures/account_fakes.dart';
import 'fixtures/store_cart.dart';

/// A client that never touches the network: sign-in and sign-out are scripted.
class _ScriptedClient extends YazanApiClient {
  _ScriptedClient(TokenStore t)
      : super(
          baseUrl: 'https://example.test',
          scope: AppScope.store,
          deviceId: 'test-device',
          tokens: t,
        );

  ApiError? loginError;
  bool loggedOut = false;
  final List<String> logins = [];

  @override
  Future<LoginResult> login({
    required String login,
    required String password,
    String? deviceName,
    String platform = 'unknown',
  }) async {
    logins.add(login);
    final error = loginError;
    if (error != null) throw error;
    final session = Session.fromJson(
        {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900});
    await tokens.write(session);
    return LoginResult.session(session);
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
    await tokens.clear();
  }
}

CatalogueRepository _emptyCatalogue() => CatalogueRepository(
      fetch: (cursor) async =>
          const DeltaPage(items: [], cursor: 'c', hasMore: false, initial: true),
    );

Future<void> _pump(
  WidgetTester tester, {
  required _ScriptedClient client,
  required TokenStore tokens,
  required FakeWishlistApi wishlist,
  WishlistMirror? mirror,
}) async {
  final cartServer = FakeTransport((r) => ok(storeCart(images: false)));
  await tester.pumpWidget(YazanApp(
    client: client,
    tokens: tokens,
    repository: _emptyCatalogue(),
    storeApi: StoreApi(cartServer.call),
    accountApi: FakeAccountApi(),
    wishlistApi: wishlist,
    wishlistMirror: mirror,
  ));
  await tester.pumpAndSettle();
}

Future<void> _signInAs(WidgetTester tester, String email) async {
  await tester.enterText(find.byType(TextField).at(0), email);
  await tester.enterText(find.byType(TextField).at(1), 'secret-password');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  group('sign-in', () {
    testWidgets('a wrong password gets a polite generic message', (tester) async {
      final tokens = MemoryTokenStore();
      final client = _ScriptedClient(tokens)
        ..loginError = const ApiError(status: 401, code: 'yazan_mobile_bad_login');
      await _pump(tester, client: client, tokens: tokens, wishlist: FakeWishlistApi());

      await _signInAs(tester, 'noor@yazan.test');
      expect(client.logins, ['noor@yazan.test']);
      expect(find.text('The details are not right. Please try again.'), findsOneWidget);
      expect(find.byTooltip('Account'), findsNothing);
    });

    testWidgets('too many attempts and an unexpected answer each get their own message', (tester) async {
      final tokens = MemoryTokenStore();
      final client = _ScriptedClient(tokens)
        ..loginError = const ApiError(status: 429, code: 'yazan_rate_limited', retryAfter: 30);
      await _pump(tester, client: client, tokens: tokens, wishlist: FakeWishlistApi());

      await _signInAs(tester, 'noor@yazan.test');
      expect(find.text('Too many attempts. Please wait and try again.'), findsOneWidget);

      client.loginError = const ApiError(status: 403, code: 'yazan_mobile_wrong_app');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('This is not available in the app.'), findsOneWidget);

      client.loginError = const ApiError(status: 500, code: 'boom');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong. Check your connection and try again.'), findsOneWidget);
    });

    testWidgets('a good sign-in opens the shop and loads the favourites', (tester) async {
      final tokens = MemoryTokenStore();
      final client = _ScriptedClient(tokens);
      final wishlist = FakeWishlistApi([ring(1, 'Alpha ring')]);
      await _pump(tester, client: client, tokens: tokens, wishlist: wishlist);

      await _signInAs(tester, 'noor@yazan.test');
      expect(find.byTooltip('Account'), findsOneWidget);
      expect(wishlist.calls, ['list']);
    });
  });

  group('sign-out', () {
    testWidgets('from the account page: ends the session, shows sign-in, forgets the favourites', (tester) async {
      final tokens = MemoryTokenStore();
      await tokens.write(Session.fromJson(
          {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
      final client = _ScriptedClient(tokens);
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
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
    });
  });

  testWidgets('favourites reachable from the app bar and the account page', (tester) async {
    final tokens = MemoryTokenStore();
    await tokens.write(Session.fromJson(
        {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
    await _pump(
      tester,
      client: _ScriptedClient(tokens),
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
