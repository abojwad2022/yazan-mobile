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

  /// When the last refresh succeeded, or null if none has in this session.
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Future<void> refresh() async {
    await pullFeed(fetch: _fetch, store: _store);
    _lastSyncedAt = _clock();
  }

  /// Cached products sorted by name. Only the in-memory store exposes rows directly;
  /// other stores should be wrapped by a store that implements [CatalogueRows].
  Future<List<Product>> products() async {
    final Object store = _store;
    final List<Map<String, dynamic>> rows;
    if (store is CatalogueRows) {
      rows = await store.readRows();
    } else if (store is MemoryFeedStore) {
      rows = store.rows.values.toList();
    } else {
      rows = <Map<String, dynamic>>[];
    }
    final list = [for (final r in rows) Product.fromRecord(r)];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}

/// Optional capability for a [FeedStore] backed by something other than memory
/// (e.g. encrypted SQLite) so the repository can read its rows.
abstract interface class CatalogueRows {
  Future<List<Map<String, dynamic>>> readRows();
}
