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
}

/// Talks to `yazan-mobile/v1` and the existing REST namespaces with a device session.
///
/// * Adds the bearer; on 401 `yazan_mobile_bad_token` refreshes ONCE (single-flight) and retries.
/// * A refresh that fails with `yazan_mobile_bad_refresh` clears the session and calls [onSignedOut].
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
        'platform': platform,
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
    } on ApiError {
      // The local session is ended either way.
    }
    await tokens.clear();
    _etags.clear();
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

  Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) =>
      _send<Map<String, dynamic>>('GET', path, query: query);

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

  Future<DeltaPage> syncCatalog({String cursor = '', int limit = 50}) async =>
      DeltaPage.fromJson(await getJson('$_ns/sync/catalog', query: {'cursor': cursor, 'limit': limit}));

  Future<T> _send<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool auth = true,
    bool retried = false,
    void Function(String? etag)? onEtag,
  }) async {
    final extra = <String, String>{...?headers};
    final session = auth ? await tokens.read() : null;
    if (auth && session == null) {
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
    if (auth && !retried && error.action == ErrorAction.refreshThenRetry) {
      await _refresh(session!);
      return _send<T>(method, path,
          data: data, query: query, headers: headers, auth: auth, retried: true, onEtag: onEtag);
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
    final current = await tokens.read();
    // Someone else already refreshed while we waited.
    if (current != null && current.accessToken != stale.accessToken) {
      return current;
    }
    try {
      final body = await _send<Map<String, dynamic>>(
        'POST',
        '$_ns/auth/refresh',
        data: {'refresh_token': stale.refreshToken},
        auth: false,
      );
      final s = Session.fromJson(body);
      await tokens.write(s);
      return s;
    } on ApiError catch (e) {
      if (e.action == ErrorAction.signIn || e.status == 401) {
        await tokens.clear();
        _etags.clear();
        onSignedOut?.call();
      }
      rethrow;
    }
  }
}

class _Cached {
  _Cached(this.etag, this.body);
  final String etag;
  final Map<String, dynamic> body;
}
