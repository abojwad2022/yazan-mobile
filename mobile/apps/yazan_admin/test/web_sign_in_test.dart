import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/app.dart';
import 'package:yazan_admin/src/login_page.dart';
import 'package:yazan_admin/src/web_sign_in/web_sign_in.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import 'storage/fakes.dart';

/// The auth browser stand-in: records what was opened and answers with [answer] (null = closed).
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

String? Function(Uri) _returns(String code) =>
    (opened) => 'com.yazanus.admin://auth?code=$code&state=${opened.queryParameters['state']}';

final _token = RegExp(r'^[A-Za-z0-9_-]{43}$');

const _adminSession = {
  'access_token': 'yzm_admin',
  'refresh_token': 'yzr_admin',
  'expires_in': 900,
  'user': {'id': 7, 'name': 'Sara Seven', 'email': 's@shop.test', 'scope': 'admin'},
};

/// A scripted server: `/auth/exchange` and `/auth/login` answer with [exchange] / [login] (status,
/// body); everything else (the home screen's reads after a sign-in) gets a plain 400.
class _Server {
  (int, Object?) exchange = (200, _adminSession);
  (int, Object?) login = (200, _adminSession);

  /// Thrown instead of answering `/auth/login` (a network failure).
  Object? loginFailure;

  (int, Object?) route(RequestOptions o) {
    if (o.path.endsWith('/auth/exchange')) return exchange;
    if (o.path.endsWith('/auth/login')) {
      final failure = loginFailure;
      if (failure != null) throw failure;
      return login;
    }
    return (400, {'code': 'test_unscripted'});
  }
}

/// Fixed steps, never pumpAndSettle: the sign-in screen and a route change, no spinner can hang it.
Future<void> _steps(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Rig {
  _Rig(String? Function(Uri) answer) : browser = FakeAuthBrowser(answer) {
    adapter = ScriptedAdapter(server.route);
    client = scriptedClient(tokens, adapter);
  }

  final _Server server = _Server();
  final MemoryTokenStore tokens = MemoryTokenStore();
  final FakeAuthBrowser browser;
  late final ScriptedAdapter adapter;
  late final YazanApiClient client;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(YazanApp(
      client: client,
      tokens: tokens,
      webSignIn: WebSignIn.forClient(client, browser: browser),
    ));
    await _steps(tester);
    expect(find.byType(LoginPage), findsOneWidget);
  }

  List<RequestOptions> sent(String suffix) =>
      [for (final o in adapter.seen) if (o.path.endsWith(suffix)) o];
}

Future<void> _tap(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _steps(tester);
}

final _webButton = find.byKey(const ValueKey('web-sign-in'));

Future<void> _signInHere(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'sara');
  await tester.enterText(find.byType(TextField).at(1), 'secret-password');
  await _tap(tester, find.widgetWithText(FilledButton, 'Sign in'));
}

void main() {
  test('the system browser adapter treats a closed browser as null and passes the scheme on',
      () async {
    final schemes = <String>[];
    final closed = SystemAuthBrowser(launch: ({required url, required callbackUrlScheme}) async {
      schemes.add(callbackUrlScheme);
      throw const PlatformException(code: 'CANCELED');
    });
    expect(
        await closed.authenticate(
            url: Uri.parse('https://shop.test/yazan-auth/app/start'),
            callbackScheme: 'com.yazanus.admin'),
        isNull);
    expect(schemes, ['com.yazanus.admin']);
    expect(platformWire(TargetPlatform.iOS), 'ios');
  });

  group('the Admin sign-in screen', () {
    testWidgets('leads with the dashboard login on the website and keeps the form below it',
        (tester) async {
      final rig = _Rig((_) => null);
      await rig.pump(tester);

      expect(find.widgetWithText(FilledButton, 'Sign in with the website (dashboard login)'),
          findsOneWidget);
      expect(find.text('Or sign in here'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(rig.browser.opened, isEmpty);
    });

    testWidgets('opens the admin start page, swaps the code with its verifier and signs in',
        (tester) async {
      final rig = _Rig(_returns('admin-code-1'));
      await rig.pump(tester);

      await _tap(tester, _webButton);

      final url = rig.browser.opened.single;
      expect(rig.browser.schemes.single, 'com.yazanus.admin');
      expect(url.scheme, 'https');
      expect(url.host, 'shop.test');
      expect(url.path, '/yazan-auth/app/start');
      final q = url.queryParameters;
      expect(q.keys.toSet(),
          {'client', 'redirect_uri', 'state', 'code_challenge', 'code_challenge_method'});
      expect(q['client'], 'admin');
      expect(q['redirect_uri'], 'com.yazanus.admin://auth');
      expect(q['code_challenge_method'], 'S256');
      expect(q['state'], matches(_token));

      final exchange = rig.sent('/yazan-mobile/v1/auth/exchange').single;
      expect(exchange.headers.containsKey('Authorization'), isFalse);
      final body = jsonDecode(exchange.data as String) as Map;
      expect(body['client'], 'admin');
      expect(body['code'], 'admin-code-1');
      expect(body['device_id'], 'test-device');
      expect(body['platform'], 'android');
      final verifier = body['code_verifier'] as String;
      expect(verifier, matches(_token));
      expect(WebSignIn.challengeFor(verifier), q['code_challenge']);
      expect(rig.sent('/auth/login'), isEmpty);

      final stored = (await rig.tokens.read())!;
      expect(stored.accessToken, 'yzm_admin');
      expect(stored.user!.scope, 'admin');
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets('a different state shows an error and sends nothing', (tester) async {
      final rig = _Rig((_) => 'com.yazanus.admin://auth?code=x&state=forged');
      await rig.pump(tester);

      await _tap(tester, _webButton);

      expect(rig.sent('/auth/exchange'), isEmpty);
      expect(find.text('Sign-in did not finish. Please try again.'), findsOneWidget);
      expect(await rig.tokens.read(), isNull);
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets("the Store app's scheme is not accepted by the Admin app", (tester) async {
      final rig = _Rig((opened) =>
          'com.yazanus.store://auth?code=x&state=${opened.queryParameters['state']}');
      await rig.pump(tester);

      await _tap(tester, _webButton);

      expect(rig.sent('/auth/exchange'), isEmpty);
      expect(find.text('Sign-in did not finish. Please try again.'), findsOneWidget);
    });

    testWidgets('closing the browser does nothing', (tester) async {
      final rig = _Rig((_) => null);
      await rig.pump(tester);

      await _tap(tester, _webButton);

      expect(rig.browser.opened, hasLength(1));
      expect(rig.adapter.seen, isEmpty);
      expect(find.byKey(const ValueKey('sign-in-error')), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('an expired code says so', (tester) async {
      final rig = _Rig(_returns('old'));
      rig.server.exchange = (400, {'code': 'yazan_mobile_bad_code', 'message': 'x'});
      await rig.pump(tester);

      await _tap(tester, _webButton);

      expect(find.text('Sign-in expired, please try again.'), findsOneWidget);
      expect(await rig.tokens.read(), isNull);
    });

    testWidgets('a browser failure shows the generic message with the platform code',
        (tester) async {
      final rig = _Rig((_) => throw const PlatformException(code: 'EUNKNOWN'));
      await rig.pump(tester);

      await _tap(tester, _webButton);

      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('(code: EUNKNOWN)'), findsOneWidget);
    });
  });

  group('Admin sign-in error messages', () {
    testWidgets('a site without the app routes (404 rest_no_route) is "not updated yet"',
        (tester) async {
      final rig = _Rig((_) => null);
      rig.server.login = (404, {'code': 'rest_no_route', 'message': 'No route', 'data': {'status': 404}});
      await rig.pump(tester);

      await _signInHere(tester);

      expect(find.text('The website is not updated for the app yet. Please try again later.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('sign-in-error-code')), findsNothing);
    });

    testWidgets('the website sign-in reads the same when the exchange route is missing',
        (tester) async {
      final rig = _Rig(_returns('c'));
      rig.server.exchange = (404, {'code': 'rest_no_route'});
      await rig.pump(tester);

      await _tap(tester, _webButton);

      expect(find.text('The website is not updated for the app yet. Please try again later.'),
          findsOneWidget);
    });

    testWidgets('no connection and a timeout get the connection message', (tester) async {
      final rig = _Rig((_) => null);
      rig.server.loginFailure = DioException(
          requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError);
      await rig.pump(tester);

      await _signInHere(tester);
      expect(find.text('Could not reach the website. Check your connection and try again.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('sign-in-error-code')), findsNothing);

      rig.server.loginFailure = TimeoutException('slow');
      await _tap(tester, find.widgetWithText(FilledButton, 'Sign in'));
      expect(find.text('Could not reach the website. Check your connection and try again.'),
          findsOneWidget);
    });

    testWidgets('any other answer is the generic message plus its code', (tester) async {
      final rig = _Rig((_) => null);
      rig.server.login = (400, {'code': 'rest_invalid_param', 'message': 'Invalid parameter(s)'});
      await rig.pump(tester);

      await _signInHere(tester);

      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('(code: rest_invalid_param, 400)'), findsOneWidget);
      expect(await rig.tokens.read(), isNull);
    });

    testWidgets('a wrong password and too many attempts keep their own messages', (tester) async {
      final rig = _Rig((_) => null);
      rig.server.login = (401, {'code': 'yazan_mobile_bad_login'});
      await rig.pump(tester);

      await _signInHere(tester);
      expect(find.text('The details are not right. Please try again.'), findsOneWidget);
      expect(find.byKey(const ValueKey('sign-in-error-code')), findsNothing);

      rig.server.login = (429, {'code': 'yazan_rate_limited'});
      await _tap(tester, find.widgetWithText(FilledButton, 'Sign in'));
      expect(find.text('Too many attempts. Please wait and try again.'), findsOneWidget);
    });
  });
}
