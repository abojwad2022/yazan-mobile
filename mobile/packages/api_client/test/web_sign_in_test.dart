import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

/// Answers every request with [status] and [body], and records what was sent.
class _Server implements HttpClientAdapter {
  _Server(this.status, this.body);

  final int status;
  final Object body;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    seen.add(options);
    return ResponseBody.fromString(jsonEncode(body), status);
  }

  @override
  void close({bool force = false}) {}
}

/// The auth browser stand-in: records what was opened and answers with [answer] (null = closed).
class _Browser implements AuthBrowser {
  _Browser(this.answer);

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

final _token = RegExp(r'^[A-Za-z0-9_-]{43}$');

const _session = {'access_token': 'yzm_w', 'refresh_token': 'yzr_w', 'expires_in': 900};

YazanApiClient _client(AppScope scope, _Server server, MemoryTokenStore tokens) => YazanApiClient(
      baseUrl: 'https://example.test',
      scope: scope,
      deviceId: 'dev-1',
      tokens: tokens,
      dio: Dio()..httpClientAdapter = server,
    );

String? Function(Uri) _returns(String scheme, String code) =>
    (opened) => '$scheme://auth?code=$code&state=${opened.queryParameters['state']}';

void main() {
  group('PKCE', () {
    test('verifier and state are 32 random bytes, base64url without padding', () {
      final a = WebSignIn.randomToken(Random.secure());
      final b = WebSignIn.randomToken(Random.secure());
      expect(a, matches(_token));
      expect(b, matches(_token));
      expect(a, isNot(b));
    });

    test('the S256 challenge matches the RFC 7636 example', () {
      expect(WebSignIn.challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
          'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });
  });

  group('start page and answer', () {
    test('each app has its own client id, redirect URI and scheme', () {
      expect(WebSignIn.schemeFor(AppScope.store), 'com.yazanus.store');
      expect(WebSignIn.schemeFor(AppScope.admin), 'com.yazanus.admin');
      for (final base in ['https://yazanus.com', 'https://yazanus.com/']) {
        final store =
            WebSignIn.startUrl(baseUrl: base, scope: AppScope.store, state: 'S', codeChallenge: 'C');
        expect(store.scheme, 'https');
        expect(store.host, 'yazanus.com');
        expect(store.path, '/yazan-auth/app/start');
        expect(store.queryParameters, {
          'client': 'store',
          'redirect_uri': 'com.yazanus.store://auth',
          'state': 'S',
          'code_challenge': 'C',
          'code_challenge_method': 'S256',
        });
        final admin =
            WebSignIn.startUrl(baseUrl: base, scope: AppScope.admin, state: 'S', codeChallenge: 'C');
        expect(admin.path, '/yazan-auth/app/start');
        expect(admin.queryParameters['client'], 'admin');
        expect(admin.queryParameters['redirect_uri'], 'com.yazanus.admin://auth');
      }
    });

    test("only the app's own address with the same state and a code is accepted", () {
      expect(
          WebSignIn.codeFrom('com.yazanus.store://auth?code=abc&state=S',
              scope: AppScope.store, state: 'S'),
          'abc');
      expect(
          WebSignIn.codeFrom('com.yazanus.admin://auth/?state=S&code=abc',
              scope: AppScope.admin, state: 'S'),
          'abc');
      for (final bad in [
        'com.yazanus.store://auth?code=abc&state=T',
        'com.yazanus.store://auth?code=abc',
        'com.yazanus.store://auth?state=S',
        'com.yazanus.store://auth?code=&state=S',
        'com.yazanus.store://auth?error=access_denied&state=S',
        'com.yazanus.store://auth?code=abc&state=S&error=x',
        'com.yazanus.store://other?code=abc&state=S',
        // The other app's scheme is not this app's answer.
        'com.yazanus.admin://auth?code=abc&state=S',
        'https://yazanus.com/auth?code=abc&state=S',
      ]) {
        expect(() => WebSignIn.codeFrom(bad, scope: AppScope.store, state: 'S'),
            throwsA(isA<WebSignInException>()),
            reason: bad);
      }
    });
  });

  group('the flow', () {
    for (final scope in AppScope.values) {
      test('${scope.wire}: opens its start page and swaps the code with the matching verifier',
          () async {
        final tokens = MemoryTokenStore();
        final server = _Server(200, _session);
        final client = _client(scope, server, tokens);
        final scheme = 'com.yazanus.${scope.wire}';
        final browser = _Browser(_returns(scheme, 'one-time-1'));

        final r = await WebSignIn.forClient(client, browser: browser)
            .signIn(client, platform: 'android');

        expect(r!.session!.accessToken, 'yzm_w');
        expect((await tokens.read())!.accessToken, 'yzm_w');
        expect(browser.schemes.single, scheme);
        final q = browser.opened.single.queryParameters;
        expect(browser.opened.single.host, 'example.test');
        expect(q['client'], scope.wire);
        expect(q['redirect_uri'], '$scheme://auth');
        expect(q['code_challenge_method'], 'S256');
        expect(q['state'], matches(_token));

        final sent = jsonDecode(server.seen.single.data as String) as Map;
        expect(server.seen.single.path, endsWith('/yazan-mobile/v1/auth/exchange'));
        expect(sent['client'], scope.wire);
        expect(sent['code'], 'one-time-1');
        expect(sent['code_verifier'], matches(_token));
        expect(sent['code_verifier'], isNot(q['state']));
        expect(WebSignIn.challengeFor(sent['code_verifier'] as String), q['code_challenge']);
        expect(sent['device_id'], 'dev-1');
        expect(sent['platform'], 'android');
      });
    }

    test('a closed browser resolves null and sends nothing', () async {
      final server = _Server(200, _session);
      final client = _client(AppScope.store, server, MemoryTokenStore());
      final browser = _Browser((_) => null);
      expect(await WebSignIn.forClient(client, browser: browser).signIn(client), isNull);
      expect(browser.opened, hasLength(1));
      expect(server.seen, isEmpty);
    });

    test('a different state is refused before any request', () async {
      final server = _Server(200, _session);
      final tokens = MemoryTokenStore();
      final client = _client(AppScope.admin, server, tokens);
      final browser = _Browser((_) => 'com.yazanus.admin://auth?code=x&state=forged');
      await expectLater(WebSignIn.forClient(client, browser: browser).signIn(client),
          throwsA(isA<WebSignInException>()));
      expect(server.seen, isEmpty);
      expect(await tokens.read(), isNull);
    });

    test('each try uses a new state and challenge', () async {
      final client = _client(AppScope.store, _Server(200, _session), MemoryTokenStore());
      final browser = _Browser((_) => null);
      final web = WebSignIn.forClient(client, browser: browser);
      await web.signIn(client);
      await web.signIn(client);
      expect(browser.opened[0].queryParameters['state'],
          isNot(browser.opened[1].queryParameters['state']));
      expect(browser.opened[0].queryParameters['code_challenge'],
          isNot(browser.opened[1].queryParameters['code_challenge']));
    });

    test('a client of the other app is refused without opening the browser', () async {
      final server = _Server(200, _session);
      final client = _client(AppScope.admin, server, MemoryTokenStore());
      final browser = _Browser((_) => null);
      final web = WebSignIn(baseUrl: 'https://example.test', scope: AppScope.store, browser: browser);
      await expectLater(web.signIn(client),
          throwsA(isA<ApiError>().having((e) => e.code, 'code', 'yazan_mobile_wrong_app')));
      expect(browser.opened, isEmpty);
      expect(server.seen, isEmpty);
    });

    test('an expired code is the server 400 bad_code, nothing stored', () async {
      final server = _Server(400, {'code': 'yazan_mobile_bad_code', 'message': 'x'});
      final tokens = MemoryTokenStore();
      final client = _client(AppScope.store, server, tokens);
      final browser = _Browser(_returns('com.yazanus.store', 'old'));
      await expectLater(WebSignIn.forClient(client, browser: browser).signIn(client),
          throwsA(isA<ApiError>().having((e) => e.code, 'code', 'yazan_mobile_bad_code')));
      expect(await tokens.read(), isNull);
    });
  });

  group('sign-in errors', () {
    RequestOptions o() => RequestOptions(path: '/x');

    test('a missing route means the website is not updated for the app', () {
      expect(signInTrouble(const ApiError(status: 404, code: 'rest_no_route')),
          SignInTrouble.websiteNotUpdated);
      expect(signInTrouble(const ApiError(status: 400, code: 'rest_no_route')),
          SignInTrouble.websiteNotUpdated);
    });

    test('no connection and timeouts are connection trouble', () {
      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(signInTrouble(DioException(requestOptions: o(), type: type)),
            SignInTrouble.connection,
            reason: type.name);
      }
      expect(signInTrouble(TimeoutException('slow')), SignInTrouble.connection);
      // Dio wraps an adapter's own timeout as an unknown DioException.
      expect(signInTrouble(DioException(requestOptions: o(), error: TimeoutException('slow'))),
          SignInTrouble.connection);
    });

    test('anything else is other, with a short code to report', () {
      const invalid = ApiError(status: 400, code: 'rest_invalid_param');
      expect(signInTrouble(invalid), SignInTrouble.other);
      expect(signInErrorCode(invalid), 'code: rest_invalid_param, 400');
      expect(signInTrouble(const ApiError(status: 500, code: 'unknown')), SignInTrouble.other);
      final cert = DioException(requestOptions: o(), type: DioExceptionType.badCertificate);
      expect(signInTrouble(cert), SignInTrouble.other);
      expect(signInErrorCode(cert), 'code: network_badCertificate');
      expect(signInTrouble(const FormatException('x')), SignInTrouble.other);
      expect(signInErrorCode(const FormatException('x')), 'code: FormatException');
    });
  });
}
