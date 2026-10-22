import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_admin/src/secure_token_store.dart';

const _sessionKey = 'yazan.session.v1';

/// [FlutterSecureStorage] in memory. The token store only reads, writes and deletes by key; the
/// calls are matched by name so the fake does not depend on the plugin's per-platform options.
class _MemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.namedArguments[#key];
    final name = invocation.memberName;
    if (key is! String) return super.noSuchMethod(invocation);
    if (name == #read) return Future<String?>.value(values[key]);
    if (name == #write) {
      final value = invocation.namedArguments[#value] as String?;
      if (value == null) {
        values.remove(key);
      } else {
        values[key] = value;
      }
      return Future<void>.value();
    }
    if (name == #delete) {
      values.remove(key);
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  final expiresAt = DateTime.utc(2026, 10, 22, 12);

  test('a session with a user round-trips, user included', () async {
    final storage = _MemorySecureStorage();
    final store = SecureTokenStore(storage);
    await store.write(Session(
      accessToken: 'yzm_a',
      refreshToken: 'yzr_b',
      expiresAt: expiresAt,
      user: const SessionUser(id: 42, name: 'Amal', email: 'amal@example.test', scope: 'admin'),
    ));

    final read = await store.read();
    expect(read!.accessToken, 'yzm_a');
    expect(read.refreshToken, 'yzr_b');
    expect(read.expiresAt, expiresAt);
    expect(read.userId, 42);
    expect(read.user!.name, 'Amal');
    expect(read.user!.email, 'amal@example.test');
    expect(read.user!.scope, 'admin');
  });

  test('a session without a user is stored without one', () async {
    final storage = _MemorySecureStorage();
    final store = SecureTokenStore(storage);
    await store.write(Session(accessToken: 'yzm_a', refreshToken: 'yzr_b', expiresAt: expiresAt));

    final raw = jsonDecode(storage.values[_sessionKey]!) as Map<String, dynamic>;
    expect(raw.containsKey('u'), isFalse);
    expect((await store.read())!.user, isNull);
  });

  test('a value written before the user was kept still loads, without a user', () async {
    final storage = _MemorySecureStorage()
      ..values[_sessionKey] = jsonEncode({'a': 'yzm_old', 'r': 'yzr_old', 'e': expiresAt.toIso8601String()});

    final read = await SecureTokenStore(storage).read();
    expect(read!.accessToken, 'yzm_old');
    expect(read.expiresAt, expiresAt);
    expect(read.user, isNull);
    expect(storage.values.containsKey(_sessionKey), isTrue);
  });

  test('an unreadable user keeps the session and drops only the user', () async {
    final storage = _MemorySecureStorage()
      ..values[_sessionKey] = jsonEncode({
        'a': 'yzm_a',
        'r': 'yzr_b',
        'e': expiresAt.toIso8601String(),
        'u': {'id': 'not a number'},
      });

    final read = await SecureTokenStore(storage).read();
    expect(read!.accessToken, 'yzm_a');
    expect(read.user, isNull);
  });

  test('a corrupt session is cleared', () async {
    final storage = _MemorySecureStorage()..values[_sessionKey] = '{not json';

    expect(await SecureTokenStore(storage).read(), isNull);
    expect(storage.values.containsKey(_sessionKey), isFalse);
  });
}
