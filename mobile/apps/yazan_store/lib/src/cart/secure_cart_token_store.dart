import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'store_api.dart';

/// The Store API `Cart-Token` in the Keystore/Keychain: it grants access to the cart's session.
class SecureCartTokenStore implements CartTokenStore {
  SecureCartTokenStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _key = 'yazan.cart_token.v1';

  @override
  Future<String?> read() => _s.read(key: _key);

  @override
  Future<void> write(String token) => _s.write(key: _key, value: token);

  @override
  Future<void> clear() => _s.delete(key: _key);
}
