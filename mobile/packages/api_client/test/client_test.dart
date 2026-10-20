import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

/// Scripted server: each handler gets the request and returns (status, body, headers).
typedef Handler = (int, Object?, Map<String, String>) Function(RequestOptions o);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final Handler handler;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    seen.add(options);
    final (status, body, headers) = handler(options);
    final text = body == null ? '' : jsonEncode(body);
    return ResponseBody.fromString(text, status, headers: {
      for (final e in headers.entries) e.key: [e.value],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> pair(String a, String r) =>
    {'access_token': a, 'refresh_token': r, 'expires_in': 900};

YazanApiClient make(FakeAdapter adapter, MemoryTokenStore store, {void Function()? onOut}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return YazanApiClient(
    baseUrl: 'https://example.test',
    scope: AppScope.store,
    deviceId: 'dev-1',
    tokens: store,
    dio: dio,
    onSignedOut: onOut,
  );
}

void main() {
  test('login stores the session and returns it', () async {
    final store = MemoryTokenStore();
    final a = FakeAdapter((o) => (200, pair('yzm_1', 'yzr_1'), {}));
    final r = await make(a, store).login(login: 'a', password: 'b');
    expect(r.session!.accessToken, 'yzm_1');
    expect((await store.read())!.refreshToken, 'yzr_1');
    final sent = jsonDecode(a.seen.single.data as String) as Map;
    expect(sent['scope'], 'store');
    expect(sent['device_id'], 'dev-1');
    expect(a.seen.single.headers.containsKey('Authorization'), isFalse);
  });

  test('login returns a challenge and stores nothing', () async {
    final store = MemoryTokenStore();
    final a = FakeAdapter((o) => (200, {'challenge': 'yzc_x', 'methods': ['totp']}, {}));
    final r = await make(a, store).login(login: 'a', password: 'b');
    expect(r.challenge!.token, 'yzc_x');
    expect(await store.read(), isNull);
  });

  test('401 bad token refreshes once and retries with the new token', () async {
    final store = MemoryTokenStore();
    await store.write(Session.fromJson(pair('yzm_old', 'yzr_old')));
    var me = 0;
    final a = FakeAdapter((o) {
      if (o.path.endsWith('/auth/refresh')) return (200, pair('yzm_new', 'yzr_new'), {});
      me++;
      return me == 1
          ? (401, {'code': 'yazan_mobile_bad_token', 'message': 'x'}, {})
          : (200, {'ok': true}, {});
    });
    final out = await make(a, store).getJson('/yazan-mobile/v1/me');
    expect(out['ok'], true);
    expect(a.seen.last.headers['Authorization'], 'Bearer yzm_new');
    expect(a.seen.where((o) => o.path.endsWith('/auth/refresh')).length, 1);
  });

  test('concurrent 401s share one refresh (the token is single use)', () async {
    final store = MemoryTokenStore();
    await store.write(Session.fromJson(pair('yzm_old', 'yzr_old')));
    var refreshes = 0;
    final a = FakeAdapter((o) {
      if (o.path.endsWith('/auth/refresh')) {
        refreshes++;
        return (200, pair('yzm_new', 'yzr_new'), {});
      }
      return o.headers['Authorization'] == 'Bearer yzm_new'
          ? (200, {'ok': true}, {})
          : (401, {'code': 'yazan_mobile_bad_token'}, {});
    });
    final c = make(a, store);
    await Future.wait([c.getJson('/a'), c.getJson('/b'), c.getJson('/c')]);
    expect(refreshes, 1);
  });

  test('a dead refresh token signs the user out', () async {
    final store = MemoryTokenStore();
    await store.write(Session.fromJson(pair('yzm_old', 'yzr_old')));
    var out = false;
    final a = FakeAdapter((o) => o.path.endsWith('/auth/refresh')
        ? (401, {'code': 'yazan_mobile_bad_refresh'}, {})
        : (401, {'code': 'yazan_mobile_bad_token'}, {}));
    final c = make(a, store, onOut: () => out = true);
    await expectLater(c.getJson('/x'), throwsA(isA<ApiError>()));
    expect(out, isTrue);
    expect(await store.read(), isNull);
  });

  test('ETag is replayed as If-None-Match and 304 returns the cached body', () async {
    final store = MemoryTokenStore();
    await store.write(Session.fromJson(pair('yzm_1', 'yzr_1')));
    final a = FakeAdapter((o) => o.headers['If-None-Match'] == '"v1"'
        ? (304, null, {})
        : (200, {'items': [1]}, {'etag': '"v1"'}));
    final c = make(a, store);
    final first = await c.getJson('/feed');
    final second = await c.getJson('/feed');
    expect(second, first);
    expect(c.meter.notModified, 1);
  });

  test('writes carry Idempotency-Key and If-Match; errors expose the conflict', () async {
    final store = MemoryTokenStore();
    await store.write(Session.fromJson(pair('yzm_1', 'yzr_1')));
    final a = FakeAdapter((o) =>
        (412, {'code': 'yazan_precondition_failed', 'data': {'current': 'zzz'}}, {}));
    final c = make(a, store);
    final key = YazanApiClient.newIdempotencyKey();
    expect(RegExp(r'^[A-Za-z0-9_\-]{8,64}$').hasMatch(key), isTrue);
    try {
      await c.sendJson('PUT', '/yazan/v1/products/5',
          data: {'name': 'n'}, idempotencyKey: key, ifMatch: 'abc');
      fail('should throw');
    } on ApiError catch (e) {
      expect(e.action, ErrorAction.showConflict);
      expect(e.current, 'zzz');
    }
    expect(a.seen.single.headers['Idempotency-Key'], key);
    expect(a.seen.single.headers['If-Match'], '"abc"');
  });

  test('traffic meter counts bytes both ways', () async {
    final store = MemoryTokenStore();
    final a = FakeAdapter((o) => (200, pair('yzm_1', 'yzr_1'), {}));
    final c = make(a, store);
    await c.login(login: 'a', password: 'b');
    expect(c.meter.sentBytes, greaterThan(0));
    expect(c.meter.receivedBytes, greaterThan(0));
  });

  test('getJsonWithVersion returns the ETag without quotes', () async {
    final store = MemoryTokenStore();
    await store.write(Session.fromJson(pair('yzm_1', 'yzr_1')));
    final a = FakeAdapter((o) => (200, {'id': 5}, {'etag': '"abc123"'}));
    final r = await make(a, store).getJsonWithVersion('/yazan/v1/orders/5');
    expect(r.body['id'], 5);
    expect(r.version, 'abc123');
  });
}
