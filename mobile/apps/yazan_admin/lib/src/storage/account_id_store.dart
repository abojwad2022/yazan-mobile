import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers WHICH staff account the durable data on this phone belongs to, so the cache can be
/// shown on a cold start before (or without) any network call, and so leftovers of an account that
/// was never wiped (app killed during sign-out) can be found and removed.
///
/// The value is only an identifier, never a credential.
abstract class AccountIdStore {
  Future<String?> read();
  Future<void> write(String accountId);
  Future<void> clear();
}

class MemoryAccountIdStore implements AccountIdStore {
  MemoryAccountIdStore([this._value]);

  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String accountId) async => _value = accountId;

  @override
  Future<void> clear() async => _value = null;
}

/// In the Keystore / Keychain next to the session, so it goes away with the same things.
class SecureAccountIdStore implements AccountIdStore {
  SecureAccountIdStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _key = 'yazan.admin.account.v1';

  @override
  Future<String?> read() async {
    try {
      final v = await _s.read(key: _key);
      return (v == null || v.isEmpty) ? null : v;
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> write(String accountId) => _s.write(key: _key, value: accountId);

  @override
  Future<void> clear() => _s.delete(key: _key);
}
