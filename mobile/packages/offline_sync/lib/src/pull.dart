import 'package:yazan_domain/yazan_domain.dart';

/// Local read model for one feed. Implemented over encrypted SQLite in the apps.
abstract class FeedStore {
  Future<String> readCursor();
  Future<void> apply({
    required List<Map<String, dynamic>> upserts,
    required List<int> deletedIds,
    required String cursor,
    required bool initial,
  });
}

class MemoryFeedStore implements FeedStore {
  String cursor = '';
  final Map<int, Map<String, dynamic>> rows = {};

  @override
  Future<String> readCursor() async => cursor;

  @override
  Future<void> apply({
    required List<Map<String, dynamic>> upserts,
    required List<int> deletedIds,
    required String cursor,
    required bool initial,
  }) async {
    if (initial) {
      // A first sync replaces whatever an older install left behind.
      rows.clear();
    }
    for (final r in upserts) {
      rows[r['id'] as int] = r;
    }
    deletedIds.forEach(rows.remove);
    this.cursor = cursor;
  }
}

/// Pulls delta pages until the server says there is no more.
///
/// The cursor is saved with each page, so an interrupted pull resumes where it stopped instead of
/// starting over (this is what keeps a 3G sync cheap). [maxPages] bounds one run.
Future<int> pullFeed({
  required Future<DeltaPage> Function(String cursor) fetch,
  required FeedStore store,
  int maxPages = 50,
}) async {
  var cursor = await store.readCursor();
  var pages = 0;
  while (pages < maxPages) {
    final page = await fetch(cursor);
    pages++;
    await store.apply(
      upserts: page.upserts,
      deletedIds: page.deletedIds,
      cursor: page.cursor,
      initial: page.initial && cursor.isEmpty,
    );
    cursor = page.cursor;
    if (!page.hasMore) break;
  }
  return pages;
}
