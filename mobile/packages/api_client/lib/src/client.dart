import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:yazan_domain/yazan_domain.dart';

import 'token_store.dart';
import 'traffic.dart';

/// Result of a sign-in step: either a session or a second-step challenge.
class LoginResult {
  const LoginResult.session(Session this.session) : challenge = null;
  const LoginResult.challenge(Challenge this.challenge) : session = null;

  final Session? session;
  final Challenge? challenge;

  /// The signed-in user's id when the response carried `user`, else null.
  int? get userId => session?.userId;

  /// The signed-in user's basic profile (id, name, email, scope) when present.
  SessionUser? get user => session?.user;
}

/// Talks to `yazan-mobile/v1` and the existing REST namespaces with a device session.
///
/// * Adds the bearer; on 401 `yazan_mobile_bad_token` refreshes ONCE (single-flight) and retries.
/// * A refresh that fails with `yazan_mobile_bad_refresh` clears the session and calls [onSignedOut].
/// * A refresh still in flight when the session ends ([logout], [clearSession], or the stored session
///   cleared or replaced) is discarded: it never writes the renewed pair back.
/// * Writes can carry an `Idempotency-Key`; retries must reuse the same key ([newIdempotencyKey]).
/// * GETs with an ETag are revalidated with `If-None-Match`; 304 returns the cached body.
class YazanApiClient {
  YazanApiClient({
    required this.baseUrl,
    required this.scope,
    required this.deviceId,
    required this.tokens,
    this.onSignedOut,
    Dio? dio,
    TrafficMeter? meter,
  })  : meter = meter ?? TrafficMeter(),
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = _join(baseUrl, '/wp-json')
      ..validateStatus = ((int? _) => true)
      ..responseType = ResponseType.plain
      ..headers['Accept'] = 'application/json';
  }

  final String baseUrl;
  final AppScope scope;
  final String deviceId;
  final TokenStore tokens;
  final void Function()? onSignedOut;
  final TrafficMeter meter;
  final Dio _dio;

  final Map<String, _Cached> _etags = {};
  Future<Session>? _refreshing;

  /// Bumped every time the session is ended on purpose ([clearSession], hence [logout]). A refresh
  /// that started under an older generation does not write its result back.
  int _generation = 0;

  static const _ns = '/yazan-mobile/v1';

  static String _join(String a, String b) =>
      a.endsWith('/') ? a.substring(0, a.length - 1) + b : a + b;

  /// 16 random bytes, url-safe: fits the server's `^[A-Za-z0-9_\-]{8,64}$`.
  static String newIdempotencyKey([Random? rng]) {
    final r = rng ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  // ---- sign-in -------------------------------------------------------------

  /// Password sign-in (`POST /auth/login`).
  ///
  /// [platform] is sent only when it is `android` or `ios`: the route's `platform` argument is an
  /// enum of those two, and WordPress refuses the whole request (400 `rest_invalid_param`) for any
  /// other value, the old default `unknown` included.
  Future<LoginResult> login({
    required String login,
    required String password,
    String? deviceName,
    String platform = 'unknown',
  }) async {
    final body = await _send<Map<String, dynamic>>(
      'POST',
      '$_ns/auth/login',
      data: {
        'login': login,
        'password': password,
        'scope': scope.wire,
        'device_id': deviceId,
        if (deviceName != null) 'device_name': deviceName,
        if (_knownPlatform(platform)) 'platform': platform,
      },
      auth: false,
    );
    return _loginResult(body);
  }

  /// Finishes a sign-in (or a new account) made on the website's own sign-in page
  /// (`POST /auth/exchange`).
  ///
  /// The app opened `/yazan-auth/app/start` in the phone's auth browser with a PKCE challenge; the
  /// site sent a one-time [code] back to the app's custom scheme. This swaps that code, with the
  /// [codeVerifier] the challenge was made from, for the same session pair and `user` payload as
  /// [login], stored the same way. Sent without a bearer.
  ///
  /// * Both apps: `client` is this client's scope (`store` / `admin`), the same id the start page
  ///   was opened with; an admin code gives an admin-scope session (the dashboard login, second
  ///   factor included, happened on the website).
  /// * [platform] is sent only when it is `android` or `ios`.
  /// * A code that is unknown, used, expired or does not match the verifier is a 400
  ///   `yazan_mobile_bad_code`.
  /// * The flow around it (PKCE, state, the browser) is `WebSignIn`.
  Future<LoginResult> exchangeAppCode({
    required String code,
    required String codeVerifier,
    String? deviceName,
    String? platform,
  }) async {
    final body = await _send<Map<String, dynamic>>(
      'POST',
      '$_ns/auth/exchange',
      data: {
        'client': scope.wire,
        'code': code,
        'code_verifier': codeVerifier,
        'device_id': deviceId,
        if (deviceName != null) 'device_name': deviceName,
        if (_knownPlatform(platform)) 'platform': platform,
      },
      auth: false,
    );
    return _loginResult(body);
  }

  /// The only `platform` values the sign-in routes accept.
  static bool _knownPlatform(String? platform) => platform == 'android' || platform == 'ios';

  /// Sign in with an OpenID Connect ID token from the phone's Google or Apple SDK
  /// (`POST /auth/social`). Same session pair and `user` payload as [login], stored the same way.
  ///
  /// * [provider] is `google` or `apple`.
  /// * [nonce] is the RAW nonce the app gave the provider SDK (the server accepts a token carrying
  ///   the nonce itself or its sha256, Apple's usual pattern); omit it when none was used.
  /// * [firstName] / [lastName]: Apple shares the name with the app once, never in the token.
  /// * [platform] is sent only when it is `android` or `ios` (the only values the route accepts).
  ///
  /// The route is store-only: an admin-scope client is refused here without a network call
  /// (`yazan_mobile_wrong_app`). While a provider is not configured on the server the call fails
  /// with a 404 (`yazan_mobile_social_unavailable`); every token or account refusal is one generic
  /// 401 (`yazan_mobile_social_failed`); a missing or unverified email is a 400.
  Future<LoginResult> socialLogin({
    required String provider,
    required String idToken,
    String? nonce,
    String? firstName,
    String? lastName,
    String? deviceName,
    String? platform,
  }) async {
    if (scope != AppScope.store) {
      throw const ApiError(status: 403, code: 'yazan_mobile_wrong_app');
    }
    final body = await _send<Map<String, dynamic>>(
      'POST',
      '$_ns/auth/social',
      data: {
        'provider': provider,
        'id_token': idToken,
        'scope': scope.wire,
        'device_id': deviceId,
        if (deviceName != null) 'device_name': deviceName,
        if (_knownPlatform(platform)) 'platform': platform,
        if (nonce != null && nonce.isNotEmpty) 'nonce': nonce,
        if (firstName != null && firstName.isNotEmpty) 'first_name': firstName,
        if (lastName != null && lastName.isNotEmpty) 'last_name': lastName,
      },
      auth: false,
    );
    return _loginResult(body);
  }

  Future<Session> verifySecondStep({required String challenge, required String code}) async {
    final body = await _send<Map<String, dynamic>>(
      'POST',
      '$_ns/auth/2fa',
      data: {'challenge': challenge, 'code': code},
      auth: false,
    );
    final s = Session.fromJson(body);
    await tokens.write(s);
    return s;
  }

  Future<void> logout() async {
    try {
      await _send<Map<String, dynamic>>('POST', '$_ns/auth/logout');
    } on Exception {
      // The local session is ended either way.
    }
    await clearSession();
  }

  /// Ends the session on this phone only (no server call): clears the stored pair and the ETag cache,
  /// and makes any refresh still in flight discard its result instead of writing it back. Prefer this
  /// over clearing the [TokenStore] directly.
  Future<void> clearSession() async {
    _generation++;
    _etags.clear();
    await tokens.clear();
  }

  Future<LoginResult> _loginResult(Map<String, dynamic> body) async {
    if (body.containsKey('challenge')) {
      return LoginResult.challenge(Challenge.fromJson(body));
    }
    final s = Session.fromJson(body);
    await tokens.write(s);
    return LoginResult.session(s);
  }

  // ---- requests ------------------------------------------------------------

  /// GET. With [optionalAuth] the call also works signed out: the bearer is sent when a session
  /// exists, nothing is sent (and nothing is thrown) when there is none, and when an expired bearer
  /// cannot be refreshed the call is retried once as a guest. A dead refresh token drops the session
  /// first; a refresh that merely failed for now (rate limited, server error) keeps the stored session
  /// for later calls and only this retry goes without the bearer. For public reads such as the store
  /// catalogue.
  Future<Map<String, dynamic>> getJson(String path,
          {Map<String, dynamic>? query, bool optionalAuth = false}) =>
      _send<Map<String, dynamic>>('GET', path, query: query, optionalAuth: optionalAuth);

  /// GET that also returns the record's version (the `ETag`, quotes stripped), for a later If-Match.
  Future<({Map<String, dynamic> body, String? version})> getJsonWithVersion(String path,
      {Map<String, dynamic>? query}) async {
    String? etag;
    final body = await _send<Map<String, dynamic>>('GET', path,
        query: query, onEtag: (e) => etag = e);
    final v = etag?.replaceFirst(RegExp(r'^W/'), '').replaceAll('"', '');
    return (body: body, version: v);
  }

  Future<Map<String, dynamic>> sendJson(
    String method,
    String path, {
    Object? data,
    String? idempotencyKey,
    String? ifMatch,
  }) =>
      _send<Map<String, dynamic>>(
        method,
        path,
        data: data,
        headers: {
          if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
          if (ifMatch != null) 'If-Match': '"$ifMatch"',
        },
      );

  /// A request that never throws on a non-2xx answer: returns the status, the decoded body (`{}` when it
  /// is not a JSON object) and the response headers (lower-case names). For callers that need headers
  /// both ways, such as the WooCommerce Store API (`Cart-Token`, `Idempotency-Key`).
  ///
  /// Sends the bearer when a session exists and works signed out too (guest carts). One refresh on an
  /// expired access token, exactly like the other calls. Only a network failure throws.
  Future<({int status, Map<String, dynamic> body, Map<String, String> headers})> raw(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
    bool retried = false,
  }) async {
    final extra = <String, String>{...headers};
    final session = await tokens.read();

    if (session != null) {
      extra['Authorization'] = 'Bearer ${session.accessToken}';
    }

    final encoded = body == null ? null : jsonEncode(body);

    if (encoded != null) {
      meter.sentBytes += utf8.encode(encoded).length;
      extra['Content-Type'] = 'application/json';
    }

    final res = await _dio.request<String>(
      path,
      data: encoded,
      options: Options(method: method, headers: extra),
    );
    final text = res.data ?? '';
    meter.receivedBytes += utf8.encode(text).length;

    Map<String, dynamic> decoded = <String, dynamic>{};

    if (text.isNotEmpty) {
      try {
        final value = jsonDecode(text);

        if (value is Map<String, dynamic>) {
          decoded = value;
        }
      } on FormatException {
        decoded = <String, dynamic>{};
      }
    }

    final status = res.statusCode ?? 0;

    if (session != null && !retried && status == 401 && ApiError.fromJson(status, decoded).action == ErrorAction.refreshThenRetry) {
      await _refresh(session);

      return raw(method, path, body: body, headers: headers, retried: true);
    }

    final out = <String, String>{};
    res.headers.forEach((name, values) => out[name.toLowerCase()] = values.join(', '));

    return (status: status, body: decoded, headers: out);
  }

  /// The catalogue feed is public (store catalogue only), so it works without a session.
  Future<DeltaPage> syncCatalog({String cursor = '', int limit = 50}) async =>
      DeltaPage.fromJson(await getJson('$_ns/sync/catalog',
          query: {'cursor': cursor, 'limit': limit}, optionalAuth: true));

  /// The store's taxonomy/terms feed (`sync/terms`). Public, so it works signed out.
  Future<Map<String, dynamic>> syncTerms() =>
      getJson('$_ns/sync/terms', optionalAuth: true);

  Future<T> _send<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool auth = true,
    bool optionalAuth = false,
    bool retried = false,
    bool guest = false,
    void Function(String? etag)? onEtag,
  }) async {
    final extra = <String, String>{...?headers};
    // [guest]: an optionalAuth retry after a failed refresh, sent without the (expired) bearer.
    final session = auth && !guest ? await tokens.read() : null;
    if (auth && session == null && !optionalAuth) {
      throw const ApiError(status: 401, code: 'yazan_mobile_bad_refresh');
    }
    if (session != null) {
      extra['Authorization'] = 'Bearer ${session.accessToken}';
    }

    final cacheKey = method == 'GET' ? _cacheKey(path, query) : null;
    final cached = cacheKey == null ? null : _etags[cacheKey];
    if (cached != null) {
      extra['If-None-Match'] = cached.etag;
    }

    final encoded = data == null ? null : jsonEncode(data);
    if (encoded != null) {
      meter.sentBytes += utf8.encode(encoded).length;
      extra['Content-Type'] = 'application/json';
    }

    final res = await _dio.request<String>(
      path,
      data: encoded,
      queryParameters: query,
      options: Options(method: method, headers: extra),
    );
    final status = res.statusCode ?? 0;
    final text = res.data ?? '';
    meter.receivedBytes += utf8.encode(text).length;

    if (status == 304 && cached != null) {
      meter.notModified++;
      onEtag?.call(cached.etag);
      return cached.body as T;
    }

    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
    }

    if (status >= 200 && status < 300) {
      final etag = res.headers.value('etag');
      onEtag?.call(etag);
      if (cacheKey != null && etag != null && decoded is Map<String, dynamic>) {
        _etags[cacheKey] = _Cached(etag, decoded);
      }
      return (decoded ?? <String, dynamic>{}) as T;
    }

    final error = ApiError.fromJson(status, decoded);
    if (auth && session != null && !retried && error.action == ErrorAction.refreshThenRetry) {
      var asGuest = false;
      try {
        await _refresh(session);
      } on ApiError {
        if (!optionalAuth) rethrow;
        // A public read carries on as a guest. Either the dead session has been cleared, or the
        // refresh failed for now (429/5xx) and the session stays stored for later calls; either way
        // re-sending the expired bearer would only earn another 401.
        asGuest = true;
      }
      return _send<T>(method, path,
          data: data,
          query: query,
          headers: headers,
          auth: auth,
          optionalAuth: optionalAuth,
          retried: true,
          guest: asGuest,
          onEtag: onEtag);
    }
    throw error;
  }

  static String _cacheKey(String path, Map<String, dynamic>? query) =>
      '$path?${(query ?? const {}).entries.map((e) => '${e.key}=${e.value}').join('&')}';

  /// Single-flight refresh: concurrent 401s share one call (the refresh token is single use).
  Future<Session> _refresh(Session stale) {
    return _refreshing ??= _doRefresh(stale).whenComplete(() => _refreshing = null);
  }

  Future<Session> _doRefresh(Session stale) async {
    final generation = _generation;
    final current = await tokens.read();
    // Signed out (or the store was cleared) after the request read its session: nothing to renew.
    if (current == null || _generation != generation) throw _sessionEnded;
    // Someone else already refreshed while we waited.
    if (current.accessToken != stale.accessToken) {
      return current;
    }
    final Map<String, dynamic> body;
    try {
      body = await _send<Map<String, dynamic>>(
        'POST',
        '$_ns/auth/refresh',
        data: {'refresh_token': stale.refreshToken},
        auth: false,
      );
    } on ApiError catch (e) {
      if (e.action == ErrorAction.signIn || e.status == 401) {
        // Only end the session this refresh was for: not one a sign-out already ended, nor a newer
        // sign-in that replaced it meanwhile.
        final stored = await tokens.read();
        if (_generation == generation &&
            stored != null &&
            stored.accessToken == stale.accessToken) {
          await clearSession();
          onSignedOut?.call();
        }
      }
      rethrow;
    }
    var s = Session.fromJson(body);
    // A refresh response has no `user`; keep the one we already knew.
    if (s.user == null && stale.user != null) s = s.copyWith(user: stale.user);
    // The session may have changed while the refresh was on the wire: re-read, then write only if
    // it is still the one we renewed and nobody ended it.
    final now = await tokens.read();
    if (now != null && now.accessToken != stale.accessToken) {
      // A new sign-in (or another refresh) replaced it: keep that one.
      return now;
    }
    if (now == null || _generation != generation) throw _sessionEnded;
    await tokens.write(s);
    return s;
  }

  /// What a refresh throws when the session ended while it ran (same code as "no session").
  static const _sessionEnded = ApiError(status: 401, code: 'yazan_mobile_bad_refresh');
}

class _Cached {
  _Cached(this.etag, this.body);
  final String etag;
  final Map<String, dynamic> body;
}
