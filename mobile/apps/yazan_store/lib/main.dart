import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import 'src/app.dart';
import 'src/cart/secure_cart_token_store.dart';
import 'src/cart/store_api.dart';
import 'src/config.dart';
import 'src/secure_token_store.dart';
import 'src/wishlist/secure_wishlist_mirror.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tokens = SecureTokenStore();
  final client = YazanApiClient(
    baseUrl: AppConfig.baseUrl,
    scope: AppConfig.scope,
    deviceId: await tokens.deviceId(),
    tokens: tokens,
  );
  // Cart and checkout go through the WooCommerce Store API. The package client cannot yet send or
  // read custom headers, so this fallback has no Cart-Token: it relies on the signed-in customer's
  // server-side cart (see clientStoreTransport). Once the client exposes a raw request, swap in:
  //   StoreApi(client.raw, tokens: SecureCartTokenStore())
  final storeApi = StoreApi(client.raw, tokens: SecureCartTokenStore());
  runApp(YazanApp(
    client: client,
    tokens: tokens,
    storeApi: storeApi,
    wishlistMirror: SecureWishlistMirror(),
  ));
}
