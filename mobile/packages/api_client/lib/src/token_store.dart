import 'package:yazan_domain/yazan_domain.dart';

/// Where the session lives. The apps back this with the Keystore/Keychain
/// (flutter_secure_storage); tests use [MemoryTokenStore]. Never plain preferences.
abstract class TokenStore {
  Future<Session?> read();
  Future<void> write(Session session);
  Future<void> clear();
}

class MemoryTokenStore implements TokenStore {
  Session? _session;

  @override
  Future<Session?> read() async => _session;

  @override
  Future<void> write(Session session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
