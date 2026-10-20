import 'sql.dart';

/// Table and statement text. Public so tests (and the in-memory fake) can key on the exact string;
/// application code should go through the stores, not use these directly.
abstract final class OutboxSql {
  static const table = 'outbox_ops';

  /// `seq` is the queue order: AUTOINCREMENT never reuses a number, so "oldest first" survives
  /// deletes and restarts. `next_attempt_at` / `created_at` are UTC epoch milliseconds.
  static const create = '''
CREATE TABLE outbox_ops (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  account_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  entity TEXT,
  method TEXT NOT NULL,
  path TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  body TEXT,
  base_version TEXT,
  state TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  server_version TEXT,
  created_at INTEGER NOT NULL
)''';
  static const createIndex =
      'CREATE INDEX outbox_ops_account ON outbox_ops (account_id, state, next_attempt_at)';

  static const insert = 'INSERT OR IGNORE INTO outbox_ops '
      '(id, account_id, kind, entity, method, path, idempotency_key, body, base_version, '
      'state, attempts, next_attempt_at, last_error, server_version, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
  static const update = 'UPDATE outbox_ops SET state = ?, attempts = ?, next_attempt_at = ?, '
      'last_error = ?, server_version = ? WHERE id = ?';
  static const remove = 'DELETE FROM outbox_ops WHERE id = ?';
  static const due = 'SELECT * FROM outbox_ops WHERE account_id = ? AND state = ? '
      'AND next_attempt_at <= ? ORDER BY seq';
  static const all = 'SELECT * FROM outbox_ops WHERE account_id = ? ORDER BY seq';
  static const deleteAccount = 'DELETE FROM outbox_ops WHERE account_id = ?';

  /// A process killed mid-send leaves ops in `sending`. They are sent again on the next run; the
  /// idempotency key (fixed per op) makes that safe.
  static const recoverInterrupted = 'UPDATE outbox_ops SET state = ? WHERE state = ?';
}

abstract final class FeedSql {
  static const createRows = '''
CREATE TABLE feed_rows (
  account_id TEXT NOT NULL,
  feed TEXT NOT NULL,
  id INTEGER NOT NULL,
  json TEXT NOT NULL,
  PRIMARY KEY (account_id, feed, id)
) WITHOUT ROWID''';
  static const createCursors = '''
CREATE TABLE feed_cursors (
  account_id TEXT NOT NULL,
  feed TEXT NOT NULL,
  cursor_value TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (account_id, feed)
) WITHOUT ROWID''';

  static const readCursor = 'SELECT cursor_value FROM feed_cursors WHERE account_id = ? AND feed = ?';
  static const readAll = 'SELECT json FROM feed_rows WHERE account_id = ? AND feed = ? ORDER BY id';
  static const clearFeed = 'DELETE FROM feed_rows WHERE account_id = ? AND feed = ?';
  static const upsertRow =
      'INSERT OR REPLACE INTO feed_rows (account_id, feed, id, json) VALUES (?, ?, ?, ?)';
  static const deleteRow = 'DELETE FROM feed_rows WHERE account_id = ? AND feed = ? AND id = ?';
  static const upsertCursor = 'INSERT OR REPLACE INTO feed_cursors '
      '(account_id, feed, cursor_value, updated_at) VALUES (?, ?, ?, ?)';
  static const deleteAccountRows = 'DELETE FROM feed_rows WHERE account_id = ?';
  static const deleteAccountCursors = 'DELETE FROM feed_cursors WHERE account_id = ?';
}

/// The schema history. NEVER edit a released entry: add the next numbered one.
///
/// To change a table later: append `SchemaMigration(2, ['ALTER TABLE ...'])`; databases already at
/// version 1 run only that step, new installs run both. [SchemaMigrator] refuses a database that
/// is newer than the list (app downgrade).
final List<SchemaMigration> yazanSchemaMigrations = List.unmodifiable([
  const SchemaMigration(1, [
    OutboxSql.create,
    OutboxSql.createIndex,
    FeedSql.createRows,
    FeedSql.createCursors,
  ]),
]);
