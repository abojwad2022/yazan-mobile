import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'order_summary.dart';

typedef OrdersFetch = Future<DeltaPage> Function(String cursor);

/// Reads the orders delta feed into a [FeedStore] and exposes it newest first.
///
/// A failed refresh keeps whatever is cached and sets [lastRefreshFailed]; a 403
/// (`ErrorAction.hideFeature`) sets [noAccess].
class OrdersRepository extends ChangeNotifier {
  OrdersRepository({required OrdersFetch fetch, FeedStore? store})
      : _fetch = fetch,
        _store = _MirrorStore(store ?? MemoryFeedStore());

  /// The production wiring: `GET /yazan-mobile/v1/sync/orders`.
  factory OrdersRepository.forClient(YazanApiClient client, {FeedStore? store, int limit = 50}) {
    return OrdersRepository(
      store: store,
      fetch: (cursor) async => DeltaPage.fromJson(
        await client.getJson(
          '/yazan-mobile/v1/sync/orders',
          query: {'cursor': cursor, 'limit': limit},
        ),
      ),
    );
  }

  final OrdersFetch _fetch;
  final _MirrorStore _store;

  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  ApiError? _error;

  bool get loading => _loading;

  /// True once a refresh has finished, successfully or not.
  bool get loaded => _loaded;
  bool get lastRefreshFailed => _failed;
  ApiError? get lastError => _error;
  bool get noAccess => _error?.action == ErrorAction.hideFeature;

  /// Newest first (created date, then id).
  List<OrderSummary> get orders {
    final list = [for (final r in _store.rows.values) OrderSummary.fromJson(r)];
    list.sort((a, b) {
      final ad = a.created;
      final bd = b.created;
      if (ad != null && bd != null) {
        final c = bd.compareTo(ad);
        if (c != 0) return c;
      } else if (ad != null) {
        return -1;
      } else if (bd != null) {
        return 1;
      }
      return b.id.compareTo(a.id);
    });
    return list;
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      await pullFeed(fetch: _fetch, store: _store);
      _failed = false;
      _error = null;
    } on ApiError catch (e) {
      _failed = true;
      _error = e;
    } on Exception {
      _failed = true;
      _error = null;
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }
}

/// Wraps the injected store and keeps a readable copy of the rows, since [FeedStore]
/// only exposes the cursor.
class _MirrorStore implements FeedStore {
  _MirrorStore(this.inner) {
    final i = inner;
    if (i is MemoryFeedStore) rows.addAll(i.rows);
  }

  final FeedStore inner;
  final Map<int, Map<String, dynamic>> rows = {};

  @override
  Future<String> readCursor() => inner.readCursor();

  @override
  Future<void> apply({
    required List<Map<String, dynamic>> upserts,
    required List<int> deletedIds,
    required String cursor,
    required bool initial,
  }) async {
    await inner.apply(
      upserts: upserts,
      deletedIds: deletedIds,
      cursor: cursor,
      initial: initial,
    );
    if (initial) rows.clear();
    for (final r in upserts) {
      final id = r['id'];
      if (id is int) rows[id] = r;
    }
    deletedIds.forEach(rows.remove);
  }
}
