import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/src/app.dart';
import 'package:yazan_store/src/cart/store_api.dart';
import 'package:yazan_store/src/login_page.dart';
import 'package:yazan_store/src/social/social_sign_in.dart';

import 'fixtures/account_fakes.dart';
import 'fixtures/catalogue_fixtures.dart';
import 'fixtures/scripted_client.dart';
import 'fixtures/store_cart.dart';

/// A provider SDK stand-in: hands back [token] (null = the customer cancelled).
class FakeSocialTokens implements SocialTokenSource {
  FakeSocialTokens([this.token]);

  final SocialToken? token;
  final List<String> calls = [];

  @override
  Future<SocialToken?> google() async {
    calls.add('google');
    return token;
  }

  @override
  Future<SocialToken?> apple() async {
    calls.add('apple');
    return token;
  }
}

const _token = SocialToken(idToken: 'id-token-1', nonce: 'nonce-1');
const _googleOnly = SocialSignInConfig(googleServerClientId: 'server-client.apps.example');

/// Fixed steps, never pumpAndSettle: enough for a route transition, cannot hang on a spinner.
Future<void> _steps(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the app as a guest and goes to the sign-in screen from the account entry.
Future<void> _openSignIn(
  WidgetTester tester, {
  required ScriptedClient client,
  required MemoryTokenStore tokens,
  FakeWishlistApi? wishlist,
  SocialSignInConfig? config,
  SocialTokenSource? source,
}) async {
  await tester.pumpWidget(YazanApp(
    client: client,
    tokens: tokens,
    repository: catalogueOf(const []),
    storeApi: StoreApi(FakeTransport((r) => ok(storeCart(images: false))).call),
    accountApi: FakeAccountApi(),
    wishlistApi: wishlist ?? FakeWishlistApi(),
    socialConfig: config,
    socialTokens: source,
  ));
  await _steps(tester);
  await tester.tap(find.byTooltip('Account'));
  await _steps(tester);
  expect(find.text('Password'), findsOneWidget);
}

/// [matching] inside the sign-in screen only (the shop behind it is not part of the check).
Finder _onSignIn(Finder matching) =>
    find.descendant(of: find.byType(LoginPage), matching: matching);

Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(OutlinedButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _steps(tester);
}

void main() {
  test('with no build flags no provider is on (the CI default)', () {
    expect(SocialSignInConfig.fromEnvironment().any, isFalse);
    expect(SocialSignInConfig.fromEnvironment(platform: TargetPlatform.iOS).apple, isFalse);
    expect(SocialSignInConfig.none.any, isFalse);
    expect(_googleOnly.google, isTrue);
    expect(_googleOnly.apple, isFalse);
  });

  test('only android and ios are sent as the platform', () {
    expect(socialPlatformWire(TargetPlatform.android), 'android');
    expect(socialPlatformWire(TargetPlatform.iOS), 'ios');
    expect(socialPlatformWire(TargetPlatform.windows), isNull);
  });

  test('the default token source has no provider wired', () async {
    const source = UnconfiguredSocialTokenSource();
    expect(await source.google(), isNull);
    expect(await source.apple(), isNull);
  });

  testWidgets('by default the sign-in screen has no social buttons', (tester) async {
    final tokens = MemoryTokenStore();
    await _openSignIn(tester, client: ScriptedClient(tokens), tokens: tokens);

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.text('or'), findsNothing);
    expect(_onSignIn(find.byType(OutlinedButton)), findsNothing);
    expect(_onSignIn(find.byType(Divider)), findsNothing);
  });

  testWidgets('with Google configured, Continue with Google signs the customer in', (tester) async {
    final tokens = MemoryTokenStore();
    final client = ScriptedClient(tokens);
    final source = FakeSocialTokens(_token);
    final wishlist = FakeWishlistApi();
    await _openSignIn(tester,
        client: client, tokens: tokens, wishlist: wishlist, config: _googleOnly, source: source);

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.text('or'), findsOneWidget);

    await _tapButton(tester, 'Continue with Google');

    expect(source.calls, ['google']);
    expect(client.socialLogins, ['google:id-token-1:nonce-1']);
    expect(client.logins, isEmpty);
    expect((await tokens.read())!.accessToken, 'yzm_s');
    // Back on the shop, signed in: the sign-in screen closed and the favourites were loaded.
    expect(find.text('Password'), findsNothing);
    expect(find.byTooltip('Account'), findsOneWidget);
    expect(wishlist.calls, contains('list'));
  });

  testWidgets('a 404 from the server says the method is not available yet', (tester) async {
    final tokens = MemoryTokenStore();
    final client = ScriptedClient(tokens)
      ..socialError = const ApiError(status: 404, code: 'yazan_mobile_social_unavailable');
    await _openSignIn(tester,
        client: client, tokens: tokens, config: _googleOnly, source: FakeSocialTokens(_token));

    await _tapButton(tester, 'Continue with Google');

    expect(client.socialLogins, hasLength(1));
    expect(
        find.text(
            'Signing in this way is not available yet. Please use your email and password.'),
        findsOneWidget);
    // Still on the sign-in screen, nothing stored, and the button can be used again.
    expect(find.text('Password'), findsOneWidget);
    expect(await tokens.read(), isNull);
    final button =
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Continue with Google'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('a refused token shows the generic social failure', (tester) async {
    final tokens = MemoryTokenStore();
    final client = ScriptedClient(tokens)
      ..socialError = const ApiError(status: 401, code: 'yazan_mobile_social_failed');
    await _openSignIn(tester,
        client: client, tokens: tokens, config: _googleOnly, source: FakeSocialTokens(_token));

    await _tapButton(tester, 'Continue with Google');

    expect(
        find.text('That sign-in did not work. Please try again or use your email and password.'),
        findsOneWidget);
    expect(await tokens.read(), isNull);
  });

  testWidgets('cancelling the provider sheet calls nothing and shows no error', (tester) async {
    final tokens = MemoryTokenStore();
    final client = ScriptedClient(tokens);
    final source = FakeSocialTokens();
    await _openSignIn(tester, client: client, tokens: tokens, config: _googleOnly, source: source);

    await _tapButton(tester, 'Continue with Google');

    expect(source.calls, ['google']);
    expect(client.socialLogins, isEmpty);
    expect(find.text('Password'), findsOneWidget);
    expect(_onSignIn(find.textContaining('try again')), findsNothing);
  });

  testWidgets('with Apple configured, Continue with Apple uses the Apple token', (tester) async {
    final tokens = MemoryTokenStore();
    final client = ScriptedClient(tokens);
    final source = FakeSocialTokens(_token);
    await _openSignIn(tester,
        client: client,
        tokens: tokens,
        config: const SocialSignInConfig(apple: true),
        source: source);

    expect(find.text('Continue with Google'), findsNothing);
    await _tapButton(tester, 'Continue with Apple');

    expect(source.calls, ['apple']);
    expect(client.socialLogins, ['apple:id-token-1:nonce-1']);
    expect(find.text('Password'), findsNothing);
  });
}
