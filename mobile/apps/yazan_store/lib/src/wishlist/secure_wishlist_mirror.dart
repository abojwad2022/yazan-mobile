import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'wishlist_mirror.dart';
import 'wishlist_models.dart';

/// The favourites copy in the Keystore/Keychain store, next to the session. At most 100 small
/// cards, and it belongs to one customer, so it stays out of plain preferences.
class SecureWishlistMirror implements WishlistMirror {
  SecureWishlistMirror([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _key = 'yazan.wishlist.v1';

  @override
  Future<List<WishlistItem>?> read() async {
    final raw = await _s.read(key: _key);
    if (raw == null) return null;
    try {
      return parseWishlistItems(jsonDecode(raw));
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(List<WishlistItem> items) =>
      _s.write(key: _key, value: jsonEncode([for (final i in items) i.toJson()]));

  @override
  Future<void> clear() => _s.delete(key: _key);
}
