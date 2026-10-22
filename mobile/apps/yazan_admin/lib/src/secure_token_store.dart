import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

/// Session in the Android Keystore / iOS Keychain. Never SharedPreferences.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _key = 'yazan.session.v1';
  static const _deviceKey = 'yazan.device.v1';

  @override
  Future<Session?> read() async {
    final raw = await _s.read(key: _key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return Session(
        accessToken: m['a'] as String,
        refreshToken: m['r'] as String,
        expiresAt: DateTime.parse(m['e'] as String),
        // Absent in values written before the user was kept, and unreadable ones are dropped: the
        // session still loads, only without a user.
        user: SessionUser.tryFromJson(m['u']),
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(Session session) {
    final user = session.user;
    return _s.write(
      key: _key,
      value: jsonEncode({
        'a': session.accessToken,
        'r': session.refreshToken,
        'e': session.expiresAt.toIso8601String(),
        if (user != null) 'u': user.toJson(),
      }),
    );
  }

  @override
  Future<void> clear() => _s.delete(key: _key);

  /// A stable random id for this install; the server binds one live session per device.
  Future<String> deviceId() async {
    final existing = await _s.read(key: _deviceKey);
    if (existing != null) return existing;
    final r = Random.secure();
    final id = base64Url.encode(List<int>.generate(18, (_) => r.nextInt(256))).replaceAll('=', '');
    await _s.write(key: _deviceKey, value: id);
    return id;
  }
}
