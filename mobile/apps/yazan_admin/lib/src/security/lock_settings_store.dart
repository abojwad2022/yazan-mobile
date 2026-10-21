import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The owner's "Require unlock" choice. null = never chosen (the default then follows whether the
/// phone can check at all).
abstract class LockSettingsStore {
  Future<bool?> read();
  Future<void> write(bool enabled);
}

class MemoryLockSettingsStore implements LockSettingsStore {
  MemoryLockSettingsStore([this._value]);

  bool? _value;

  @override
  Future<bool?> read() async => _value;

  @override
  Future<void> write(bool enabled) async => _value = enabled;
}

/// Keystore / Keychain, next to the session.
class SecureLockSettingsStore implements LockSettingsStore {
  SecureLockSettingsStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _key = 'yazan.admin.lock.v1';

  @override
  Future<bool?> read() async {
    try {
      final v = await _s.read(key: _key);
      if (v == 'on') return true;
      if (v == 'off') return false;
      return null;
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> write(bool enabled) async {
    try {
      await _s.write(key: _key, value: enabled ? 'on' : 'off');
    } on Exception {
      // The choice then only lasts for this run; never block the person over it.
    }
  }
}
