/// The only door to the database. Everything the durable stores need from SQLite is these few
/// methods, so the logic above them runs in plain Dart tests against an in-memory fake, and the
/// real driver (SQLCipher, in `yazan_storage`) is a thin adapter.
///
/// Arguments are limited to what every SQLite binding accepts: `null`, `int`, `double`, `String`.
abstract class SqlExecutor {
  Future<void> execute(String sql, [List<Object?> args = const []]);

  /// Rows as column name -> value. Callers never rely on the order of unrelated rows.
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?> args = const []]);

  /// `PRAGMA user_version`: the schema version stored in the database file itself.
  Future<int> userVersion();
  Future<void> setUserVersion(int version);
}

abstract class SqlDatabase extends SqlExecutor {
  /// Runs [action] atomically: if it throws, nothing it did is kept.
  ///
  /// Inside [action] use only the executor it is given, never the outer database (drivers
  /// deadlock on that).
  Future<T> transaction<T>(Future<T> Function(SqlExecutor txn) action);

  Future<void> close();
}

/// The file is readable but written by a NEWER app version, or the schema list is malformed.
/// Not recoverable by deleting data: the person has to update the app.
class StorageSchemaException implements Exception {
  const StorageSchemaException(this.message);
  final String message;

  @override
  String toString() => 'StorageSchemaException: $message';
}

/// The database file cannot be opened with our key (wrong key, damaged, or restored from a backup
/// taken on another device). The opener adapter throws this; [YazanStorage.open] then recreates it.
class StorageUnreadableException implements Exception {
  const StorageUnreadableException([this.cause]);
  final Object? cause;

  @override
  String toString() => 'StorageUnreadableException: $cause';
}

/// One step of the schema. [version] is the `user_version` the database has AFTER it ran.
class SchemaMigration {
  const SchemaMigration(this.version, this.statements, {this.hook});

  final int version;

  /// Plain DDL / DML, run in order.
  final List<String> statements;

  /// Optional Dart step for data changes SQL alone cannot express. Runs after [statements], in the
  /// same transaction.
  final Future<void> Function(SqlExecutor txn)? hook;
}

/// Brings a database file up to the latest schema.
///
/// * Each migration runs in its own transaction together with the version bump, so a crash leaves
///   the database at the previous, consistent version and the next launch simply retries.
/// * A file from a newer app (version above the latest known) is refused, never "fixed".
class SchemaMigrator {
  SchemaMigrator(List<SchemaMigration> steps) : migrations = List.unmodifiable(steps) {
    for (var i = 0; i < steps.length; i++) {
      if (steps[i].version != i + 1) {
        throw ArgumentError(
          'Migrations must be numbered 1..n without gaps; got ${steps[i].version} '
          'at position ${i + 1}.',
        );
      }
    }
  }

  final List<SchemaMigration> migrations;

  int get latest => migrations.length;

  /// Returns the version the database is at afterwards.
  Future<int> migrate(SqlDatabase db) async {
    final current = await db.userVersion();
    if (current > latest) {
      throw StorageSchemaException(
        'Database is at schema $current but this app only knows up to $latest. '
        'Update the app.',
      );
    }
    for (final m in migrations) {
      if (m.version <= current) continue;
      await db.transaction((txn) async {
        for (final s in m.statements) {
          await txn.execute(s);
        }
        await m.hook?.call(txn);
        await txn.setUserVersion(m.version);
      });
    }
    return latest;
  }
}
