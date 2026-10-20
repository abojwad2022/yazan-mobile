# yazan_storage

Native adapters that let `yazan_offline_sync` keep its outbox and feed caches in an **encrypted
SQLite file** (SQLCipher via `sqflite_sqlcipher`), with the key generated once and kept in the
Android Keystore / iOS Keychain (`flutter_secure_storage`).

All storage logic lives in the pure-Dart `yazan_offline_sync` package (see its README for the design
and usage). This package only contains the parts that need native code:

* `SqlCipherOpener` / `SqfliteSqlDatabase` - `EncryptedDatabaseOpener` + `SqlDatabase` over sqflite.
* `FlutterSecureSecretStore` - `SecretStore` over flutter_secure_storage.
* `looksLikeWrongKey` - classifies the SQLCipher "file is not a database" error (unit tested).

```dart
final storage = await YazanStorage.open(
  opener: SqlCipherOpener(fileName: 'yazan_store.db'),
  secrets: FlutterSecureSecretStore(),
);
```
