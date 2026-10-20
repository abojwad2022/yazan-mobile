import 'package:yazan_api_client/yazan_api_client.dart';

import '../json_read.dart';
import 'wishlist_models.dart';

/// The customer's favourites on the server (`/yazan/v1/wishlist`).
///
/// Methods throw `ApiError` for a server answer and any other exception for a network problem.
abstract class WishlistApi {
  Future<List<WishlistItem>> list();

  /// The server only offers a toggle (add if absent, remove if present), so callers must know the
  /// server's current state before they call it (see `WishlistController.setSaved`).
  Future<WishlistToggle> toggle(int productId);
}

class ClientWishlistApi implements WishlistApi {
  ClientWishlistApi(this._client);

  final YazanApiClient _client;

  static const _base = '/yazan/v1/wishlist';

  @override
  Future<List<WishlistItem>> list() async {
    final body = await _client.getJson(_base);
    return parseWishlistItems(asMap(body)['items']);
  }

  @override
  Future<WishlistToggle> toggle(int productId) async => WishlistToggle.fromJson(
        await _client.sendJson('POST', '$_base/toggle', data: {'product_id': productId}),
      );
}
