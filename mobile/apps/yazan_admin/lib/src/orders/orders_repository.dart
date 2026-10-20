import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'order_summary.dart';

typedef OrdersFetch = Future<DeltaPage> Function(String cursor);

/// Reads the orders delta feed into a [FeedStore] and exposes it newest first.
///
/// On start the list is seeded from [FeedStore.readAll], so the cache shows after a restart
/// before any network round trip. A failed refresh keeps whatever is cached and sets
/// [lastRefreshFailed]; a 403 (`ErrorAction.hideFeature`) sets [noAccess].
class OrdersRepository extends ChangeNotifier {
  OrdersRepository({required OrdersFetch fetch, FeedStore? store})
      : _fetch = fetch,
        _store = store ?? MemoryFeedStore() {
    _ready = _reload();
  }

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
  final FeedStore _store;
  late final Future<void> _ready;

  List<Map<String, dynamic>> _rows = const [];
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  bool _disposed = false;
  ApiError? _error;

  /// Completes once the cached rows have been read.
  Future<void> get ready => _ready;

  bool get loading => _loading;

  /// True once a refresh has finished, successfully or not.
  bool get loaded => _loaded;
  bool get lastRefreshFailed => _failed;
  ApiError? get lastError => _error;
  bool get noAccess => _error?.action == ErrorAction.hideFeature;

  /// Newest first (created date, then id).
  List<OrderSummary> get orders {
    final list = [for (final r in _rows) OrderSummary.fromJson(r)];
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

  /// Drops every cached row and the cursor, in memory and in the store. Called when the server
  /// stops letting this account see the feed, so the data does not linger on the phone. A later
  /// refresh starts from scratch.
  Future<void> purge() async {
    _rows = const [];
    try {
      await _store.apply(upserts: const [], deletedIds: const [], cursor: '', initial: true);
    } on Exception {
      // The rows are gone from memory either way; the sign-out wipe removes the file content.
    }
    _notify();
  }

  Future<void> _reload() async {
    try {
      _rows = await _store.readAll();
    } on Exception {
      // An unreadable cache shows as empty; the next pull fills it.
    }
    _notify();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _notify();
    await _ready;
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
      // Pages saved before a failure are kept, so read the store back either way.
      await _reload();
      _loading = false;
      _loaded = true;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
