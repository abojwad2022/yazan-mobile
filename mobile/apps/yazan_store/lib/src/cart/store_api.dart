import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import 'cart.dart';

/// One raw HTTP exchange: status, decoded JSON object body and response headers.
typedef StoreResponse = ({int status, Map<String, dynamic> body, Map<String, String> headers});

/// Sends one request to a path relative to `/wp-json` and returns the raw response.
///
/// It must NOT throw on a non-2xx status (the status is returned); it may throw on a network
/// failure. Header lookups in the response are case-insensitive.
typedef StoreTransport = Future<StoreResponse> Function(
  String method,
  String path, {
  Object? body,
  Map<String, String> headers,
});

/// A Store API failure. [status] is 0 when the request never got an answer (offline).
class StoreApiException implements Exception {
  const StoreApiException({required this.status, required this.code, this.message = ''});

  const StoreApiException.network()
      : status = 0,
        code = 'network',
        message = '';

  factory StoreApiException.fromBody(int status, Map<String, dynamic> body) {
    final code = body['code'];
    final message = body['message'];
    return StoreApiException(
      status: status,
      code: code is String && code.isNotEmpty ? code : 'unknown',
      message: message is String ? plainText(message) : '',
    );
  }

  final int status;
  final String code;

  /// Server message, already stripped of HTML (e.g. "not enough stock").
  final String message;

  bool get isNetwork => status == 0;

  /// The server is still working on the same idempotency key.
  bool get isBusy => status == 409 || code == 'yazan_idempotency_busy';

  /// The server answered and definitely did not do the work, so a new attempt is safe.
  /// Network failures, timeouts, 409 and 5xx are ambiguous: the order may exist.
  bool get isDefiniteRejection => status >= 400 && status < 500 && status != 408 && !isBusy;

  @override
  String toString() => 'StoreApiException($status $code)';
}

/// Where the Store API `Cart-Token` lives between launches.
abstract class CartTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class MemoryCartTokenStore implements CartTokenStore {
  MemoryCartTokenStore([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  @override
  Future<void> clear() async => token = null;
}

/// Cart and cash-on-delivery checkout over the WooCommerce Store API (`/wc/store/v1`).
///
/// * Every response's `Cart-Token` header is persisted and sent back on every call, so a cart
///   survives restarts and the Store API skips its cookie nonce check.
/// * The server decides every price, tax, shipping cost and stock level; nothing is computed here.
/// * [checkout] carries one `Idempotency-Key` per attempt: reused on retries (network failure,
///   5xx, 409) and on a double tap (single-flight), replaced only after success or a definite
///   rejection, so a retry can never create a second order.
class StoreApi {
  StoreApi(
    this._transport, {
    CartTokenStore? tokens,
    String Function()? newKey,
    bool fetchTokenFirst = false,
  })  : _tokens = tokens ?? MemoryCartTokenStore(),
        _newKey = newKey ?? YazanApiClient.newIdempotencyKey,
        _fetchTokenFirst = fetchTokenFirst;

  final StoreTransport _transport;
  final CartTokenStore _tokens;
  final String Function() _newKey;

  /// A guest has no session to vouch for a write, so the Store API wants either a nonce or a
  /// `Cart-Token`. With this on, a write made before any token is held first reads the cart (which
  /// hands out a token), so the very first "add to cart" works for a guest who opened the app offline.
  final bool _fetchTokenFirst;

  static const _base = '/wc/store/v1';

  String? _cartToken;
  bool _tokenLoaded = false;
  String? _checkoutKey;
  Future<PlacedOrder>? _checkoutInFlight;

  Future<Cart> getCart() async => Cart.fromJson(await _call('GET', '/cart'));

  /// Adds a product, or a variation of a variable product: pass the variation's id as [productId]
  /// and its attributes (attribute key and value) as [variation].
  Future<Cart> addItem(
    int productId, {
    int quantity = 1,
    List<({String attribute, String value})> variation = const [],
  }) async =>
      Cart.fromJson(
        await _call('POST', '/cart/add-item', body: {
          'id': productId,
          'quantity': quantity,
          if (variation.isNotEmpty)
            'variation': [
              for (final v in variation) {'attribute': v.attribute, 'value': v.value},
            ],
        }),
      );

  Future<Cart> updateItem(String key, int quantity) async => Cart.fromJson(
        await _call('POST', '/cart/update-item', body: {'key': key, 'quantity': quantity}),
      );

  Future<Cart> removeItem(String key) async =>
      Cart.fromJson(await _call('POST', '/cart/remove-item', body: {'key': key}));

  /// Places a cash-on-delivery order. A second call while one is in flight joins the first.
  Future<PlacedOrder> checkout(CheckoutDetails details) =>
      _checkoutInFlight ??= _checkout(details).whenComplete(() => _checkoutInFlight = null);

  /// Forgets the cart (on sign-out), so the next customer on this device starts clean.
  Future<void> forgetCartToken() async {
    _cartToken = null;
    _tokenLoaded = true;
    _checkoutKey = null;
    await _tokens.clear();
  }

  Future<PlacedOrder> _checkout(CheckoutDetails details) async {
    final key = _checkoutKey ??= _newKey();
    try {
      final body = await _call(
        'POST',
        '/checkout',
        body: details.toJson(),
        headers: {'Idempotency-Key': key},
      );
      final order = PlacedOrder.fromJson(body);
      _checkoutKey = null;
      final payment = order.paymentStatus;
      if (payment == 'failure' || payment == 'error') {
        throw const StoreApiException(status: 402, code: 'payment_failed');
      }
      return order;
    } on StoreApiException catch (e) {
      if (e.isDefiniteRejection) _checkoutKey = null;
      rethrow;
    }
  }

  Future<String?> _token() async {
    if (!_tokenLoaded) {
      _cartToken = await _tokens.read();
      _tokenLoaded = true;
    }
    return _cartToken;
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    if (_fetchTokenFirst && method != 'GET' && await _token() == null) {
      try {
        await _call('GET', '/cart');
      } on StoreApiException {
        // The write below reports the real problem (offline, server error...).
      }
    }
    final token = await _token();
    final res = await _send(method, '$_base$path', body: body, headers: {
      if (token != null) 'Cart-Token': token,
      ...headers,
    });
    final fresh = _header(res.headers, 'cart-token');
    if (fresh != null && fresh.isNotEmpty && fresh != token) {
      _cartToken = fresh;
      _tokenLoaded = true;
      await _tokens.write(fresh);
    }
    if (res.status >= 200 && res.status < 300) return res.body;
    throw StoreApiException.fromBody(res.status, res.body);
  }

  Future<StoreResponse> _send(
    String method,
    String path, {
    Object? body,
    required Map<String, String> headers,
  }) async {
    try {
      return await _transport(method, path, body: body, headers: headers);
    } catch (_) {
      throw const StoreApiException.network();
    }
  }

  static String? _header(Map<String, String> headers, String lowerName) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == lowerName) return e.value;
    }
    return null;
  }
}

/// Fallback transport over the package's `getJson` / `sendJson` (bearer auth, no custom headers).
///
/// Limitation: it cannot send or read `Cart-Token` (nor the Store API `Nonce`), so the cart only
/// works if the server resolves it from the signed-in customer's bearer session, and Store API
/// POSTs are refused with `woocommerce_rest_missing_nonce` unless the server waives the nonce for
/// bearer-authenticated requests. Replace it with a raw transport from the API client
/// (`StoreApi(client.raw)`) once the package exposes one. Success statuses are reported as 200.
StoreTransport clientStoreTransport(YazanApiClient client) {
  return (String method, String path, {Object? body, Map<String, String> headers = const {}}) async {
    try {
      final Map<String, dynamic> res;
      if (method == 'GET') {
        res = await client.getJson(path);
      } else {
        res = await client.sendJson(
          method,
          path,
          data: body,
          idempotencyKey: headers['Idempotency-Key'],
        );
      }
      return (status: 200, body: res, headers: const <String, String>{});
    } on ApiError catch (e) {
      return (
        status: e.status,
        body: <String, dynamic>{'code': e.code, 'message': e.message},
        headers: const <String, String>{},
      );
    }
  };
}
