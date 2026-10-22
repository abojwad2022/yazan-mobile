import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/src/app.dart';
import 'package:yazan_store/src/cart/store_api.dart';
import 'package:yazan_store/src/login_page.dart';
import 'package:yazan_store/src/web_sign_in/web_sign_in.dart';

import 'fixtures/account_fakes.dart';
import 'fixtures/catalogue_fixtures.dart';
import 'fixtures/scripted_client.dart';
import 'fixtures/store_cart.dart';

/// The auth browser stand-in: records what was opened and answers with [answer] (null = the
/// customer closed it; it may also throw, like a real platform failure).
class FakeAuthBrowser implements AuthBrowser {
  FakeAuthBrowser(this.answer);

  final String? Function(Uri opened) answer;
  final List<Uri> opened = [];
  final List<String> schemes = [];

  @override
  Future<String?> authenticate({required Uri url, required String callbackScheme}) async {
    opened.add(url);
    schemes.add(callbackScheme);
    return answer(url);
  }
}

/// What a well-behaved site sends back: the one-time code and the state it was given.
String? Function(Uri) _returns(String code) =>
    (opened) => 'com.yazanus.store://auth?code=$code&state=${opened.queryParameters['state']}';

String? _closed(Uri _) => null;

final _token = RegExp(r'^[A-Za-z0-9_-]{43}$');

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
  required FakeAuthBrowser browser,
  FakeWishlistApi? wishlist,
  String accountTooltip = 'Account',
}) async {
  await tester.pumpWidget(YazanApp(
    client: client,
    tokens: tokens,
    repository: catalogueOf(const []),
    storeApi: StoreApi(FakeTransport((r) => ok(storeCart(images: false))).call),
    accountApi: FakeAccountApi(),
    wishlistApi: wishlist ?? FakeWishlistApi(),
    webSignIn: WebSignIn.forClient(client, browser: browser),
  ));
  await _steps(tester);
  await tester.tap(find.byTooltip(accountTooltip));
  await _steps(tester);
  expect(find.byType(LoginPage), findsOneWidget);
}

Future<void> _tapWebSignIn(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('web-sign-in'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _steps(tester);
}

Finder _onSignIn(Finder matching) =>
    find.descendant(of: find.byType(LoginPage), matching: matching);

void main() {
  group('the system browser adapter', () {
    test('passes the start page and the scheme to flutter_web_auth_2 and returns its answer',
        () async {
      final calls = <String>[];
      final browser = SystemAuthBrowser(launch: ({required url, required callbackUrlScheme}) async {
        calls.add('$url|$callbackUrlScheme');
        return 'com.yazanus.store://auth?code=c&state=s';
      });
      final answer = await browser.authenticate(
          url: Uri.parse('https://example.test/yazan-auth/app/start?client=store'),
          callbackScheme: 'com.yazanus.store');
      expect(answer, 'com.yazanus.store://auth?code=c&state=s');
      expect(calls, ['https://example.test/yazan-auth/app/start?client=store|com.yazanus.store']);
    });

    test('a closed browser (CANCELED) is null; any other failure is passed on', () async {
      final cancelled = SystemAuthBrowser(
          launch: ({required url, required callbackUrlScheme}) async =>
              throw PlatformException(code: 'CANCELED', message: 'User canceled login'));
      expect(
          await cancelled.authenticate(url: Uri.parse('https://example.test'), callbackScheme: 'x'),
          isNull);
      final broken = SystemAuthBrowser(
          launch: ({required url, required callbackUrlScheme}) async =>
              throw PlatformException(code: 'EUNKNOWN'));
      await expectLater(
          broken.authenticate(url: Uri.parse('https://example.test'), callbackScheme: 'x'),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'EUNKNOWN')));
    });

    test('only android and ios are sent as the platform', () {
      expect(platformWire(TargetPlatform.android), 'android');
      expect(platformWire(TargetPlatform.iOS), 'ios');
      expect(platformWire(TargetPlatform.windows), isNull);
    });

    test('the small print names the code, the platform code or the type', () {
      expect(signInErrorDetail(const ApiError(status: 400, code: 'rest_invalid_param')),
          'code: rest_invalid_param, 400');
      expect(signInErrorDetail(PlatformException(code: 'EUNKNOWN')), 'code: EUNKNOWN');
      expect(signInErrorDetail(const FormatException('x')), 'code: FormatException');
    });
  });

  group('the sign-in screen', () {
    testWidgets('the website is the small "Other ways to sign in" link under the email step',
        (tester) async {
      final tokens = MemoryTokenStore();
      final browser = FakeAuthBrowser(_closed);
      final client = ScriptedClient(tokens);
      await _openSignIn(tester, client: client, tokens: tokens, browser: browser);

      expect(find.widgetWithText(TextButton, 'Other ways to sign in'), findsOneWidget);
      // The native email step leads: one field, no password yet.
      expect(_onSignIn(find.byType(TextField)), findsOneWidget);
      expect(find.text('Password'), findsNothing);
      // No Google / Apple buttons without a provider in this build.
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.text('Continue with Apple'), findsNothing);
      expect(browser.opened, isEmpty);
    });

    testWidgets('opens the start page with a fresh state and an S256 challenge, then signs in',
        (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens);
      final wishlist = FakeWishlistApi();
      final browser = FakeAuthBrowser(_returns('one-time-1'));
      await _openSignIn(tester,
          client: client, tokens: tokens, browser: browser, wishlist: wishlist);

      await _tapWebSignIn(tester);

      final url = browser.opened.single;
      expect(browser.schemes.single, 'com.yazanus.store');
      expect(url.scheme, 'https');
      expect(url.host, 'example.test');
      expect(url.path, '/yazan-auth/app/start');
      final q = url.queryParameters;
      expect(q.keys.toSet(),
          {'client', 'redirect_uri', 'state', 'code_challenge', 'code_challenge_method'});
      expect(q['client'], 'store');
      expect(q['redirect_uri'], 'com.yazanus.store://auth');
      expect(q['code_challenge_method'], 'S256');
      expect(q['state'], matches(_token));

      // The code was swapped with the verifier the challenge was made from.
      final parts = client.exchanges.single.split(':');
      expect(parts[0], 'one-time-1');
      final verifier = parts[1];
      expect(verifier, matches(_token));
      expect(verifier, isNot(q['state']));
      expect(WebSignIn.challengeFor(verifier), q['code_challenge']);
      expect(parts[2], 'android');
      expect(client.logins, isEmpty);

      // Signed in like a password sign-in: session stored, screen closed, favourites loaded.
      expect((await tokens.read())!.accessToken, 'yzm_w');
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byTooltip('Account'), findsOneWidget);
      expect(wishlist.calls, contains('list'));
    });

    testWidgets('a different state shows an error and sends nothing', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens);
      final browser =
          FakeAuthBrowser((_) => 'com.yazanus.store://auth?code=one-time-1&state=someone-else');
      await _openSignIn(tester, client: client, tokens: tokens, browser: browser);

      await _tapWebSignIn(tester);

      expect(browser.opened, hasLength(1));
      expect(client.exchanges, isEmpty);
      expect(find.text('Sign-in did not finish. Please try again.'), findsOneWidget);
      expect(await tokens.read(), isNull);
      expect(find.byType(LoginPage), findsOneWidget);
      final button = tester.widget<TextButton>(find.byKey(const ValueKey('web-sign-in')));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('an answer without a code shows an error and sends nothing', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens);
      final browser = FakeAuthBrowser(
          (opened) => 'com.yazanus.store://auth?state=${opened.queryParameters['state']}');
      await _openSignIn(tester, client: client, tokens: tokens, browser: browser);

      await _tapWebSignIn(tester);

      expect(client.exchanges, isEmpty);
      expect(find.text('Sign-in did not finish. Please try again.'), findsOneWidget);
      expect(await tokens.read(), isNull);
    });

    testWidgets('closing the browser does nothing: no request, no error', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens);
      final browser = FakeAuthBrowser(_closed);
      await _openSignIn(tester, client: client, tokens: tokens, browser: browser);

      await _tapWebSignIn(tester);

      expect(browser.opened, hasLength(1));
      expect(client.exchanges, isEmpty);
      expect(find.byKey(const ValueKey('sign-in-error')), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(await tokens.read(), isNull);

      // A second try starts over with a new state and a new challenge.
      await _tapWebSignIn(tester);
      expect(browser.opened, hasLength(2));
      expect(browser.opened[1].queryParameters['state'],
          isNot(browser.opened[0].queryParameters['state']));
      expect(browser.opened[1].queryParameters['code_challenge'],
          isNot(browser.opened[0].queryParameters['code_challenge']));
    });

    testWidgets('an expired or used code says so and stores nothing', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)
        ..exchangeError = const ApiError(status: 400, code: 'yazan_mobile_bad_code');
      await _openSignIn(tester,
          client: client, tokens: tokens, browser: FakeAuthBrowser(_returns('old-code')));

      await _tapWebSignIn(tester);

      expect(client.exchanges, hasLength(1));
      expect(find.text('Sign-in expired, please try again.'), findsOneWidget);
      expect(find.byKey(const ValueKey('sign-in-error-code')), findsNothing);
      expect(await tokens.read(), isNull);
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('a site without the app route says the website is not updated yet',
        (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)
        ..exchangeError = const ApiError(status: 404, code: 'rest_no_route');
      await _openSignIn(tester,
          client: client, tokens: tokens, browser: FakeAuthBrowser(_returns('c')));

      await _tapWebSignIn(tester);

      expect(find.text('The website is not updated for the app yet. Please try again later.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('sign-in-error-code')), findsNothing);
    });

    testWidgets('an unexpected answer shows the generic message and its code', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)
        ..exchangeError = const ApiError(status: 400, code: 'rest_invalid_param');
      await _openSignIn(tester,
          client: client, tokens: tokens, browser: FakeAuthBrowser(_returns('c')));

      await _tapWebSignIn(tester);

      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('(code: rest_invalid_param, 400)'), findsOneWidget);
    });

    testWidgets('a browser failure shows the generic message and the platform code',
        (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens);
      await _openSignIn(tester,
          client: client,
          tokens: tokens,
          browser: FakeAuthBrowser((_) => throw PlatformException(code: 'EUNKNOWN')));

      await _tapWebSignIn(tester);

      expect(client.exchanges, isEmpty);
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('(code: EUNKNOWN)'), findsOneWidget);
    });

    testWidgets('the Arabic screen reads right-to-left with its own labels', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ar')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final tokens = MemoryTokenStore();
      await _openSignIn(tester,
          client: ScriptedClient(tokens),
          tokens: tokens,
          browser: FakeAuthBrowser(_closed),
          accountTooltip: 'الحساب');

      expect(find.text('طرق أخرى لتسجيل الدخول'), findsOneWidget);
      final dir = Directionality.of(tester.element(find.text('طرق أخرى لتسجيل الدخول')));
      expect(dir, TextDirection.rtl);
    });
  });
}
