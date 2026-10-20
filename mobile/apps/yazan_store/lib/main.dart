import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';
import 'package:yazan_storage/yazan_storage.dart';

import 'src/app.dart';
import 'src/cart/secure_cart_token_store.dart';
import 'src/cart/store_api.dart';
import 'src/config.dart';
import 'src/secure_token_store.dart';
import 'src/storage/local_data.dart';
import 'src/wishlist/secure_wishlist_mirror.dart';

/// Opens the encrypted database once for the whole run. A lost key or unreadable file is recovered
/// inside `YazanStorage.open` (and reported through `recreated`); a failure it cannot recover from
/// (a platform error) must not take the shop down, so the app then runs with the catalogue in
/// memory only.
Future<StoreLocalData?> _openLocalData() async {
  try {
    final storage = await YazanStorage.open(
      opener: SqlCipherOpener(fileName: 'yazan_store.db'),
      secrets: FlutterSecureSecretStore(),
    );
    return DurableLocalData(storage);
  } catch (_) {
    return null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tokens = SecureTokenStore();
  final client = YazanApiClient(
    baseUrl: AppConfig.baseUrl,
    scope: AppConfig.scope,
    deviceId: await tokens.deviceId(),
    tokens: tokens,
  );
  // Cart and checkout go through the WooCommerce Store API with a Cart-Token, so they work for a
  // guest with no account. `fetchTokenFirst` makes the first write read the cart (and so get a
  // token) when the app was opened offline.
  final storeApi = StoreApi(client.raw, tokens: SecureCartTokenStore(), fetchTokenFirst: true);
  final localData = await _openLocalData();
  runApp(YazanApp(
    client: client,
    tokens: tokens,
    storeApi: storeApi,
    wishlistMirror: SecureWishlistMirror(),
    localData: localData,
  ));
}
