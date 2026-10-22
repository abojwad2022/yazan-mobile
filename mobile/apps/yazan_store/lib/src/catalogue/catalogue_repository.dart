import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'product.dart';

/// Fetches one catalogue delta page for a cursor (normally `client.syncCatalog`).
typedef CatalogueFetch = Future<DeltaPage> Function(String cursor);

/// Local catalogue: a [FeedStore] cache refreshed by delta pulls.
///
/// A failed refresh rethrows and leaves the cache untouched, so the UI keeps showing
/// the last good products and marks them stale.
class CatalogueRepository {
  CatalogueRepository({required CatalogueFetch fetch, FeedStore? store, DateTime Function()? clock})
      : _fetch = fetch,
        _store = store ?? MemoryFeedStore(),
        _clock = clock ?? DateTime.now;

  final CatalogueFetch _fetch;
  final FeedStore _store;
  final DateTime Function() _clock;

  DateTime? _lastSyncedAt;

  /// The feed metadata key the time of the last successful refresh is stored under (UTC, ISO 8601).
  static const syncedAtKey = 'synced_at';

  /// When the last complete refresh finished, or null if none has in this session.
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// A first sync (no cursor yet) is staged and swapped in whole once the last page arrived, so an
  /// older install's rows stay on screen until the new catalogue is complete.
  ///
  /// Returns true when the feed was read to its end. A pull cut off by the page limit returns false
  /// and stamps nothing ([lastSyncedAt] and [syncedAtKey] keep the last complete refresh): a delta
  /// pull resumes from its saved cursor next time, a staged first sync has applied nothing yet.
  Future<bool> refresh() async {
    final result = await pullFeedResult(fetch: _fetch, store: _store, replaceOnFirstSuccess: true);
    if (!result.complete) return false;
    final now = _clock();
    _lastSyncedAt = now;
    try {
      await _store.writeMeta(syncedAtKey, now.toUtc().toIso8601String());
    } on Exception {
      // The products are already saved; without the stamp only the stored sync time is missing.
    }
    return true;
  }

  /// Cached products sorted by name, read straight from the store (works after a restart).
  Future<List<Product>> products() async {
    final rows = await _store.readAll();
    final list = [for (final r in rows) Product.fromRecord(r)];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}
