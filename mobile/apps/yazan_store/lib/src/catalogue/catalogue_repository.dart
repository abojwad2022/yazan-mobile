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

  /// Cached products sorted by name, read straight from the store (works after a restart).
  Future<List<Product>> products() async {
    final rows = await _store.readAll();
    final list = [for (final r in rows) Product.fromRecord(r)];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}
