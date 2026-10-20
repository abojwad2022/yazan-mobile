import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

/// The database key in the Android Keystore / iOS Keychain, via flutter_secure_storage (the same
/// mechanism the apps already use for tokens).
class FlutterSecureSecretStore implements SecretStore {
  FlutterSecureSecretStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String name) => _s.read(key: name);

  @override
  Future<void> write(String name, String value) => _s.write(key: name, value: value);

  @override
  Future<void> delete(String name) => _s.delete(key: name);
}
