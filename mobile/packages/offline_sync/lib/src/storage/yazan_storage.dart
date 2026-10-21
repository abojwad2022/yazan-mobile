import 'dart:math';

import '../pull.dart';
import 'schema.dart';
import 'sql.dart';
import 'sql_feed_store.dart';
import 'sql_outbox_store.dart';

/// Where the database key lives: Android Keystore / iOS Keychain in the apps
/// (`FlutterSecureSecretStore` in `yazan_storage`), a map in tests.
abstract class SecretStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);
}

/// Generates the database passphrase once per install and keeps it in the [SecretStore].
///
/// The passphrase is 256 random bits (64 hex characters) from a cryptographically secure source;
/// nothing derives it from a password or an account id, and it never leaves the secure store except
/// to be handed to the database driver.
class DatabaseKeyManager {
  DatabaseKeyManager(this._secrets, {Random? random, this.name = 'yazan.db.key.v1'})
      : _random = random ?? Random.secure();

  final SecretStore _secrets;
  final Random _random;
  final String name;

  /// The existing key, or a freshly generated and stored one.
  Future<String> obtain() async {
    final existing = await _secrets.read(name);
    if (existing != null && existing.length >= 32) return existing;
    return _generate();
  }

  /// Replaces the key (used only when the old database file is unreadable and is being recreated).
  Future<String> regenerate() => _generate();

  Future<String> _generate() async {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final key = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _secrets.write(name, key);
    return key;
  }
}

/// Opens (and creates) the encrypted database file with [key]. The adapter in `yazan_storage` does
/// this with SQLCipher. It throws [StorageUnreadableException] when the file exists but the key does
/// not open it; any other error propagates unchanged.
abstract class EncryptedDatabaseOpener {
  Future<SqlDatabase> open(String key);

  /// Deletes the database file (and its journal files).
  Future<void> deleteDatabase();
}

/// The durable, encrypted, per-account local storage of an app: one database holding the outbox and
/// every feed cache, each row tagged with its account id.
///
/// ```dart
/// final storage = await YazanStorage.open(opener: opener, secrets: secrets);
/// final outbox  = storage.outbox;                          // OutboxStore
/// final orders  = storage.feed(accountId, 'orders');       // FeedStore
/// await storage.wipe(accountId);                           // sign-out / revoked access
/// ```
class YazanStorage {
  YazanStorage(this.db, {this.recreated = false, DateTime Function()? clock})
      : outbox = SqlOutboxStore(db, clock: clock),
        _clock = clock;

  /// Opens, migrates and recovers. If the file cannot be read with our key it is deleted and
  /// created again with a new key ([recreated] is then true: the cache is refilled by the next pull;
  /// ops that were still queued in the old file are lost, which the caller should tell the person).
  static Future<YazanStorage> open({
    required EncryptedDatabaseOpener opener,
    required SecretStore secrets,
    SchemaMigrator? migrator,
    DatabaseKeyManager? keys,
    DateTime Function()? clock,
  }) async {
    final keyManager = keys ?? DatabaseKeyManager(secrets);
    final schema = migrator ?? SchemaMigrator(yazanSchemaMigrations);

    Future<YazanStorage> openWith(String key, bool recreated) async {
      final db = await opener.open(key);
      try {
        await schema.migrate(db);
        final storage = YazanStorage(db, recreated: recreated, clock: clock);
        await storage.outbox.recoverInterrupted();
        return storage;
      } on Object {
        await db.close();
        rethrow;
      }
    }

    try {
      return await openWith(await keyManager.obtain(), false);
    } on StorageUnreadableException {
      await opener.deleteDatabase();
      return openWith(await keyManager.regenerate(), true);
    }
  }

  final SqlDatabase db;

  /// True when the previous file was unreadable and has been replaced by an empty one.
  final bool recreated;

  /// All accounts' queues; every [OutboxStore] method already takes the account id.
  final SqlOutboxStore outbox;
  final DateTime Function()? _clock;

  /// The cache of feed [name] (e.g. `orders`, `products`) for [accountId]. Use
  /// [SqlFeedStore.guestAccountId] for the public catalogue before sign-in.
  FeedStore feed(String accountId, String name) =>
      SqlFeedStore(db, accountId: accountId, feed: name, clock: _clock);

  /// Removes EVERYTHING stored for [accountId]: queued ops, cached rows and cursors, atomically.
  /// Call on sign-out and when the server revokes the session. Other accounts are untouched.
  Future<void> wipe(String accountId) {
    return db.transaction((txn) async {
      await txn.execute(OutboxSql.deleteAccount, [accountId]);
      await txn.execute(FeedSql.deleteAccountRows, [accountId]);
      await txn.execute(FeedSql.deleteAccountCursors, [accountId]);
      await txn.execute(FeedSql.deleteAccountMeta, [accountId]);
    });
  }

  Future<void> close() => db.close();
}
