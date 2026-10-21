import 'dart:convert';

import '../pull.dart';
import 'schema.dart';
import 'sql.dart';

/// [FeedStore] over SQLite (SQLCipher in the apps) for ONE feed of ONE account.
///
/// Rows and the cursor are namespaced by `account_id` + [feed], so two accounts on one phone, or
/// the catalogue and the orders feed, never see each other. Use [guestAccountId] for the signed-out
/// public catalogue.
///
/// [apply] is a single transaction: a crash mid-page leaves the previous rows AND the previous
/// cursor, never new rows with an old cursor (or the reverse), so the next pull is still correct.
class SqlFeedStore implements FeedStore, FeedMetaStore {
  SqlFeedStore(
    this._db, {
    required this.accountId,
    required this.feed,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  /// Account id used for data that exists before anyone signs in (the public catalogue).
  static const guestAccountId = 'guest';

  final SqlDatabase _db;
  final String accountId;
  final String feed;
  final DateTime Function() _clock;

  @override
  Future<String> readCursor() async {
    final rows = await _db.query(FeedSql.readCursor, [accountId, feed]);
    if (rows.isEmpty) return '';
    return (rows.first['cursor_value'] as String?) ?? '';
  }

  @override
  Future<String?> readMeta(String key) async {
    final rows = await _db.query(FeedSql.readMeta, [accountId, feed, key]);
    return rows.isEmpty ? null : rows.first['meta_value'] as String?;
  }

  @override
  Future<void> writeMeta(String key, String? value) => value == null
      ? _db.execute(FeedSql.deleteMeta, [accountId, feed, key])
      : _db.execute(FeedSql.upsertMeta, [accountId, feed, key, value]);

  @override
  Future<List<Map<String, dynamic>>> readAll() async {
    final rows = await _db.query(FeedSql.readAll, [accountId, feed]);
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final row = _decode(r['json']);
      if (row != null) out.add(row);
    }
    return out;
  }

  /// A row this version cannot decode is skipped; the next delta pull rewrites it.
  static Map<String, dynamic>? _decode(Object? json) {
    try {
      return Map<String, dynamic>.from(jsonDecode(json! as String) as Map);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> apply({
    required List<Map<String, dynamic>> upserts,
    required List<int> deletedIds,
    required String cursor,
    required bool initial,
  }) {
    return _db.transaction((txn) async {
      if (initial) {
        // A first sync replaces whatever an older install left behind.
        await txn.execute(FeedSql.clearFeed, [accountId, feed]);
      }
      for (final r in upserts) {
        await txn.execute(FeedSql.upsertRow, [accountId, feed, r['id'] as int, jsonEncode(r)]);
      }
      for (final id in deletedIds) {
        await txn.execute(FeedSql.deleteRow, [accountId, feed, id]);
      }
      await txn.execute(FeedSql.upsertCursor, [
        accountId,
        feed,
        cursor,
        _clock().millisecondsSinceEpoch,
      ]);
    });
  }
}
