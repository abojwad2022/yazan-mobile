import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:yazan_domain/yazan_domain.dart';

import 'client.dart';

/// Opens a page in the phone's auth browser and resolves with the address the site sent back to
/// [callbackScheme], or null when the person closed the browser (not an error).
///
/// The apps implement it over `flutter_web_auth_2`; tests use a fake and never open a browser.
abstract class AuthBrowser {
  Future<String?> authenticate({required Uri url, required String callbackScheme});
}

/// What came back from the website was not a usable answer (no code, a different `state`, an
/// `error` parameter, another address). Nothing was sent to the server.
class WebSignInException implements Exception {
  const WebSignInException(this.reason);

  final String reason;

  @override
  String toString() => 'WebSignInException($reason)';
}

/// Signing in through the website's own sign-in page, shared by both apps.
///
/// 1. A fresh PKCE verifier and `state` (32 random bytes each, base64url without padding).
/// 2. The auth browser opens the site's `/yazan-auth/app/start` page ([startUrl]: the app's client
///    id, its redirect URI, the state and the S256 challenge). The person signs in there exactly as
///    on the website (the Store page or the dashboard login, second factor included) or creates an
///    account.
/// 3. The site redirects to `com.yazanus.<app>://auth?code=...&state=...`; only that address with
///    the same `state` and a non-empty code is accepted, else nothing is sent.
/// 4. `POST /auth/exchange` swaps the code and the verifier for the app's usual session
///    ([YazanApiClient.exchangeAppCode]), stored exactly like a password sign-in.
///
/// Per app: the client id is the scope's wire name (`store` / `admin`) and the callback scheme is
/// `com.yazanus.store` / `com.yazanus.admin` (the applicationId / bundle id of each app).
class WebSignIn {
  WebSignIn({
    required this.baseUrl,
    required this.scope,
    required this.browser,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// The website and the app of [client].
  factory WebSignIn.forClient(YazanApiClient client, {required AuthBrowser browser, Random? random}) =>
      WebSignIn(baseUrl: client.baseUrl, scope: client.scope, browser: browser, random: random);

  /// The website (the same base URL the API client talks to).
  final String baseUrl;

  /// Which app is signing in: decides the client id and the callback scheme.
  final AppScope scope;
  final AuthBrowser browser;
  final Random _random;

  /// The app's custom scheme: `com.yazanus.store` or `com.yazanus.admin`.
  static String schemeFor(AppScope scope) => 'com.yazanus.${scope.wire}';

  /// Where the site sends the code: `com.yazanus.<app>://auth`.
  static String redirectUriFor(AppScope scope) => '${schemeFor(scope)}://auth';

  String get callbackScheme => schemeFor(scope);

  /// 32 random bytes, base64url without padding (43 characters).
  static String randomToken(Random random) =>
      _b64(List<int>.generate(32, (_) => random.nextInt(256)));

  /// The S256 PKCE challenge: base64url(sha256(ascii(verifier))) without padding.
  static String challengeFor(String verifier) => _b64(sha256.convert(ascii.encode(verifier)).bytes);

  static String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  /// The page the browser opens.
  static Uri startUrl({
    required String baseUrl,
    required AppScope scope,
    required String state,
    required String codeChallenge,
  }) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base/yazan-auth/app/start').replace(queryParameters: {
      'client': scope.wire,
      'redirect_uri': redirectUriFor(scope),
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });
  }

  /// The one-time code from the address the site sent back. Throws [WebSignInException] unless it
  /// is the app's own `<scheme>://auth` address with the expected [state] and a non-empty `code`.
  static String codeFrom(String returned, {required AppScope scope, required String state}) {
    final Uri uri;
    try {
      uri = Uri.parse(returned);
    } on FormatException {
      throw const WebSignInException('unreadable');
    }
    if (uri.scheme != schemeFor(scope) || uri.host != 'auth') {
      throw const WebSignInException('wrong_address');
    }
    final query = uri.queryParameters;
    if (query['state'] != state) throw const WebSignInException('state');
    if (query.containsKey('error')) throw const WebSignInException('error');
    final code = query['code'];
    if (code == null || code.isEmpty) throw const WebSignInException('no_code');
    return code;
  }

  /// Runs the whole flow. Resolves null when the person closed the browser.
  ///
  /// Throws [WebSignInException] for an unusable answer (no request is made), an [ApiError] when
  /// the server refuses the code (400 `yazan_mobile_bad_code`: expired or already used) or when
  /// [client] belongs to the other app (`yazan_mobile_wrong_app`, no browser opened), and lets any
  /// browser failure other than closing it through.
  Future<LoginResult?> signIn(YazanApiClient client, {String? platform}) async {
    if (client.scope != scope) {
      throw const ApiError(status: 403, code: 'yazan_mobile_wrong_app');
    }
    final verifier = randomToken(_random);
    final state = randomToken(_random);
    final url = startUrl(
      baseUrl: baseUrl,
      scope: scope,
      state: state,
      codeChallenge: challengeFor(verifier),
    );
    final returned = await browser.authenticate(url: url, callbackScheme: callbackScheme);
    if (returned == null) return null;
    final code = codeFrom(returned, scope: scope, state: state);
    return client.exchangeAppCode(code: code, codeVerifier: verifier, platform: platform);
  }
}
