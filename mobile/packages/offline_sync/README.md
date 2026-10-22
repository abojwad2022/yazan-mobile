# yazan_offline_sync

Outbox, backoff and delta-pull engine, plus a **durable, encrypted, per-account** local store.
Pure Dart: every database call goes through the small `SqlDatabase` / `SqlExecutor` interface, so
the logic is unit tested here against an in-memory fake. The native SQLCipher adapter and the
Keystore-backed key live in the sibling package `yazan_storage`.

## What is stored

One database file per app, every row tagged with its account id:

| table | content |
|---|---|
| `outbox_ops` | uuid `id`, `idempotency_key` (fixed per op, reused on every retry), `kind`, `entity`, `method`, `path`, `body` (field-level patch, JSON), `base_version`, `state` (`pending/sending/failed/conflict`), `attempts`, `next_attempt_at`, `last_error`, `server_version`; `seq` gives the queue order |
| `feed_rows` | `(account_id, feed, id) -> json` |
| `feed_cursors` | `(account_id, feed) -> cursor` |

The schema version is `PRAGMA user_version`. `yazanSchemaMigrations` (in `schema.dart`) is the
history: **never edit a released step, append the next number**. `SchemaMigrator` runs each missing
step (SQL statements + an optional Dart `hook`) in its own transaction with the version bump, and
refuses a file written by a newer app (`StorageSchemaException`).

## Usage

```dart
// Once per app start (after the user is known or as guest).
final storage = await YazanStorage.open(
  opener: SqlCipherOpener(fileName: 'yazan_admin.db'), // from yazan_storage
  secrets: FlutterSecureSecretStore(),                 // from yazan_storage
);
if (storage.recreated) { /* file was unreadable and was replaced: tell the person queued edits were lost */ }

final OutboxStore outbox = storage.outbox;                        // all accounts; methods take accountId
final FeedStore orders   = storage.feed(session.userId, 'orders'); // cache for this account + feed
final FeedStore catalog  = storage.feed(SqlFeedStore.guestAccountId, 'products');

final engine = SyncEngine(store: outbox, send: sendOp);
await pullFeed(fetch: fetchOrdersPage, store: orders);
// Same pull, plus whether it reached the feed's end (false when cut off by maxPages):
final r = await pullFeedResult(fetch: fetchCatalogPage, store: catalog, replaceOnFirstSuccess: true);
if (r.complete) { /* only now stamp a "last synced" time */ }
await engine.run(session.userId);

// Sign-out or revoked access: queue, cached rows and cursors of that account, atomically.
await storage.wipe(session.userId);
```

Existing code keeps working: `OutboxStore`, `FeedStore`, `MemoryOutboxStore`, `MemoryFeedStore`
are unchanged (`OutboxOp` only gained the optional `entity`).

## Behaviour worth knowing

* Reads return fresh `OutboxOp` objects; `update` writes state, attempts, next attempt, error and
  server version (the engine already calls it after every change).
* Queue order is insertion order (`seq`), stable across restarts.
* Ops left `sending` by a killed process are reset to `pending` on `open`; the fixed idempotency key
  makes the resend execute once.
* `FeedStore.apply` is one transaction: rows and cursor move together.
* Key: 256 random bits, generated once, stored under `yazan.db.key.v1`. If the file cannot be opened
  with it (key lost, backup restored on another device), the file is deleted and recreated empty.
* Rows this version cannot decode are skipped, not fatal.

## Not covered by the unit tests

The fake checks the store logic, not the SQL text. The SQL is plain (`CREATE TABLE`, `INSERT OR
IGNORE/REPLACE`, `UPDATE`, `DELETE`, `SELECT ... ORDER BY`), but it has not been executed against a
real SQLite/SQLCipher; run an on-device or `sqflite_common_ffi` smoke test before relying on it.
