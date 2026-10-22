import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:yazan_admin/src/storage/admin_stores.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

/// [AccountStorage] in memory, with the same account isolation and wipe contract as the encrypted
/// database (whose SQL is tested in `yazan_offline_sync`).
class FakeAccountStorage implements AccountStorage {
  final Map<String, MemoryFeedStore> _feeds = {};
  final MemoryOutboxStore _outbox = MemoryOutboxStore();

  /// Accounts passed to [wipe], in order.
  final List<String> wiped = [];

  /// When true, [wipe] throws (disk error) and deletes nothing.
  bool failWipe = false;

  MemoryFeedStore raw(String account, String name) =>
      _feeds.putIfAbsent('$account|$name', MemoryFeedStore.new);

  @override
  FeedStore feed(String accountId, String name) => raw(accountId, name);

  @override
  OutboxStore get outbox => _outbox;

  @override
  Future<void> wipe(String accountId) async {
    if (failWipe) throw StateError('disk error');
    wiped.add(accountId);
    for (final e in _feeds.entries) {
      if (e.key.startsWith('$accountId|')) {
        e.value.rows.clear();
        e.value.cursor = '';
        e.value.meta.clear();
      }
    }
    await _outbox.clearAccount(accountId);
  }

  /// Rows cached for [account] across all feeds.
  int rowCount(String account) => _feeds.entries
      .where((e) => e.key.startsWith('$account|'))
      .fold(0, (n, e) => n + e.value.rows.length);

  /// Gives [account] one cached row in each feed and one queued note.
  Future<void> seed(
    String account, {
    Map<String, dynamic>? order,
    List<Map<String, dynamic>> customers = const [],
  }) async {
    final orderRow = order ??
        {
          'id': 5,
          'number': '5',
          'status': 'processing',
          'total': '10.00',
          'currency': 'USD',
          'items': 1,
          'name': 'Buyer of $account',
          'created': '2026-10-01 10:00:00',
          'modified': '2026-10-01 10:00:00',
          'version': 'v1',
        };
    await raw(account, AdminFeeds.orders).apply(
      upserts: [orderRow],
      deletedIds: const [],
      cursor: 'orders-cursor',
      initial: true,
    );
    await raw(account, AdminFeeds.products).apply(
      upserts: [
        {'id': 21, 'name': 'Ring of $account'},
      ],
      deletedIds: const [],
      cursor: 'products-cursor',
      initial: true,
    );
    if (customers.isNotEmpty) {
      await raw(account, AdminFeeds.customers).apply(
        upserts: customers,
        deletedIds: const [],
        cursor: 'customers-cursor',
        initial: true,
      );
    }
    await _outbox.add(OutboxOp(
      id: 'op-$account',
      accountId: account,
      kind: QueueableKind.orderNote,
      method: 'POST',
      path: '/yazan/v1/orders/5/notes',
      entity: 'order:5',
      idempotencyKey: 'key-$account',
      body: {'note': 'private note of $account'},
    ));
  }
}

/// A scripted `GET /yazan-mobile/v1/me`.
class FakeMe {
  Map<String, dynamic> answer = {'id': 7, 'scope': 'admin', 'permissions': <String, dynamic>{}};

  /// Thrown instead of answering (offline, or an [ApiError]).
  Object? error;
  int calls = 0;

  Future<Map<String, dynamic>> call() async {
    calls++;
    final e = error;
    if (e != null) throw e;
    return answer;
  }
}

const forbidden = ApiError(status: 403, code: 'yazan_forbidden');

/// Dio adapter that answers by path, so the real [YazanApiClient] and the real repositories run in
/// widget tests without a network.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.route);

  /// Returns `(status, body)` for a request path.
  final (int, Object?) Function(RequestOptions o) route;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    final (status, body) = route(options);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

YazanApiClient scriptedClient(
  TokenStore tokens,
  ScriptedAdapter adapter, {
  void Function()? onSignedOut,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return YazanApiClient(
    baseUrl: 'https://shop.test',
    scope: AppScope.admin,
    deviceId: 'test-device',
    tokens: tokens,
    dio: dio,
    onSignedOut: onSignedOut,
  );
}

Future<MemoryTokenStore> signedInTokens() async {
  final tokens = MemoryTokenStore();
  await tokens.write(Session.fromJson(
      {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
  return tokens;
}

/// An empty, finished delta page.
const emptyPage = {'items': <Object>[], 'cursor': 'next', 'has_more': false, 'initial': false};
