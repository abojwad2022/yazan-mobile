import 'package:flutter/foundation.dart';

import 'cart.dart';
import 'store_api.dart';

/// The app's view of the server cart. Every change goes to the server and the cart it returns
/// replaces the local one; nothing is totalled on the device.
class CartController extends ChangeNotifier {
  CartController(this.api);

  final StoreApi api;

  Cart? _cart;
  bool _busy = false;
  StoreApiException? _error;
  bool _disposed = false;

  /// Last cart the server returned, or null before the first successful load.
  Cart? get cart => _cart;
  bool get busy => _busy;

  /// The last failure, cleared by the next request.
  StoreApiException? get error => _error;

  int get count => _cart?.itemsCount ?? 0;

  Future<bool> refresh() => _run(api.getCart);

  /// Adds a product; for a variation pass its id and attributes (see [StoreApi.addItem]).
  Future<bool> add(
    int productId, {
    int quantity = 1,
    List<({String attribute, String value})> variation = const [],
  }) =>
      _run(() => api.addItem(productId, quantity: quantity, variation: variation));

  Future<bool> setQuantity(CartItem item, int quantity) =>
      quantity <= 0 ? remove(item) : _run(() => api.updateItem(item.key, quantity));

  Future<bool> remove(CartItem item) => _run(() => api.removeItem(item.key));

  /// Places the order; throws [StoreApiException] on failure. On success the server cart is empty.
  Future<PlacedOrder> placeOrder(CheckoutDetails details) async {
    final order = await api.checkout(details);
    _cart = Cart.empty;
    _error = null;
    _notify();
    return order;
  }

  /// Drops the cart and its token (sign-out).
  Future<void> forget() async {
    _cart = null;
    _error = null;
    _notify();
    await api.forgetCartToken();
  }

  Future<bool> _run(Future<Cart> Function() action) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      _cart = await action();
      return true;
    } on StoreApiException catch (e) {
      _error = e;
      return false;
    } catch (_) {
      _error = const StoreApiException.network();
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
