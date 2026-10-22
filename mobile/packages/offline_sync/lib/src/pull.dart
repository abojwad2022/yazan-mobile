import 'package:yazan_domain/yazan_domain.dart';

/// Local read model for one feed. Implemented over encrypted SQLite in the apps.
abstract class FeedStore {
  Future<String> readCursor();

  /// Every cached record, so the UI can show the cache after a restart without a network round trip.
  Future<List<Map<String, dynamic>>> readAll();
  Future<void> apply({
    required List<Map<String, dynamic>> upserts,
    required List<int> deletedIds,
    required String cursor,
    required bool initial,
  });
}

/// Optional small per-feed key/value slot (e.g. a last-synced stamp), kept next to the rows so it
/// is wiped with them. A separate interface so existing [FeedStore] implementations (fakes in app
/// tests) keep compiling; use the [FeedMeta] extension, which degrades to "nothing stored" for a
/// store that does not implement it.
abstract class FeedMetaStore {
  Future<String?> readMeta(String key);

  /// A null [value] removes the key.
  Future<void> writeMeta(String key, String? value);
}

extension FeedMeta on FeedStore {
  /// True when this store can keep metadata.
  bool get supportsMeta => this is FeedMetaStore;

  /// The stored value, or null (also null when the store has no metadata support).
  Future<String?> readMeta(String key) async {
    // The explicit cast keeps the call on the interface: on the promoted type this extension would
    // call itself.
    return supportsMeta ? (this as FeedMetaStore).readMeta(key) : null;
  }

  /// Stores [value] under [key]; a no-op when the store has no metadata support.
  Future<void> writeMeta(String key, String? value) async {
    if (supportsMeta) await (this as FeedMetaStore).writeMeta(key, value);
  }
}

class MemoryFeedStore implements FeedStore, FeedMetaStore {
  String cursor = '';
  final Map<int, Map<String, dynamic>> rows = {};
  final Map<String, String> meta = {};

  @override
  Future<String?> readMeta(String key) async => meta[key];

  @override
  Future<void> writeMeta(String key, String? value) async {
    if (value == null) {
      meta.remove(key);
    } else {
      meta[key] = value;
    }
  }

  @override
  Future<String> readCursor() async => cursor;

  @override
  Future<List<Map<String, dynamic>>> readAll() async => rows.values.toList();

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

/// What one [pullFeedResult] run did.
class PullResult {
  const PullResult({required this.pages, required this.complete});

  /// Pages fetched in this run.
  final int pages;

  /// True when the server's last page said there is no more (`has_more: false`). False when the run
  /// stopped at `maxPages` first: a delta pull has saved its cursor and the next run resumes there; a
  /// staged (replace) pull has applied nothing.
  final bool complete;

  @override
  String toString() => 'PullResult(pages: $pages, complete: $complete)';
}

/// Pulls delta pages until the server says there is no more.
///
/// The cursor is saved with each page, so an interrupted pull resumes where it stopped instead of
/// starting over (this is what keeps a 3G sync cheap). [maxPages] bounds one run.
///
/// Replace modes (both buffer pages in memory and make ONE atomic `apply(initial: true)` after the
/// last page, so a stale cache is never emptied before the network has fully answered; a failure or
/// a [maxPages] cut-off leaves the cache and cursor untouched):
/// * [replaceOnFirstSuccess]: only when the store has no cursor yet (first sync, or an older install
///   whose rows have no cursor).
/// * [fullResync]: always start from an empty cursor and replace everything.
/// Use for catalogue-sized feeds; the buffer holds the whole feed. Returns the pages fetched.
///
/// The page count alone does not say whether the feed was read to its end; use [pullFeedResult]
/// when that matters (for example before stamping a "last synced" time).
Future<int> pullFeed({
  required Future<DeltaPage> Function(String cursor) fetch,
  required FeedStore store,
  int maxPages = 50,
  bool replaceOnFirstSuccess = false,
  bool fullResync = false,
}) async =>
    (await pullFeedResult(
      fetch: fetch,
      store: store,
      maxPages: maxPages,
      replaceOnFirstSuccess: replaceOnFirstSuccess,
      fullResync: fullResync,
    ))
        .pages;

/// [pullFeed], reporting whether the pull reached the end of the feed ([PullResult.complete]) as
/// well as how many pages it fetched. Same modes, same guarantees.
Future<PullResult> pullFeedResult({
  required Future<DeltaPage> Function(String cursor) fetch,
  required FeedStore store,
  int maxPages = 50,
  bool replaceOnFirstSuccess = false,
  bool fullResync = false,
}) async {
  var cursor = fullResync ? '' : await store.readCursor();
  final staged = fullResync || (replaceOnFirstSuccess && cursor.isEmpty);
  if (staged) return _pullStaged(fetch, store, maxPages);
  var pages = 0;
  var complete = false;
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
    if (!page.hasMore) {
      complete = true;
      break;
    }
  }
  return PullResult(pages: pages, complete: complete);
}

Future<PullResult> _pullStaged(
  Future<DeltaPage> Function(String cursor) fetch,
  FeedStore store,
  int maxPages,
) async {
  final rows = <int, Map<String, dynamic>>{};
  var cursor = '';
  var pages = 0;
  while (pages < maxPages) {
    final page = await fetch(cursor);
    pages++;
    for (final r in page.upserts) {
      rows[r['id'] as int] = r;
    }
    page.deletedIds.forEach(rows.remove);
    cursor = page.cursor;
    if (!page.hasMore) {
      await store.apply(
        upserts: rows.values.toList(),
        deletedIds: const [],
        cursor: cursor,
        initial: true,
      );
      return PullResult(pages: pages, complete: true);
    }
  }
  // Cut off by maxPages: nothing was applied, so the cache and cursor are as they were.
  return PullResult(pages: pages, complete: false);
}
