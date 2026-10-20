import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'product_permissions.dart';
import 'product_summary.dart';

typedef ProductsFetch = Future<DeltaPage> Function(String cursor);

/// Reads the catalogue delta feed into a [FeedStore] and exposes it for browsing and search.
///
/// Same shape as `OrdersRepository`: on start the list is seeded from [FeedStore.readAll], so the
/// cache shows before any network round trip; a failed refresh keeps what is cached and sets
/// [lastRefreshFailed]; a 403 (`ErrorAction.hideFeature`) sets [noAccess].
///
/// The feed itself is open to any app session, so permission to see products comes from the
/// `/me` permission map ([loadPermissions]); when it says no, the list is hidden and the feed is
/// not even pulled.
class ProductsRepository extends ChangeNotifier {
  ProductsRepository({
    required ProductsFetch fetch,
    FeedStore? store,
    PermissionsLoader? loadPermissions,
  })  : _fetch = fetch,
        _store = store ?? MemoryFeedStore(),
        _permissionsLoader = loadPermissions {
    _ready = _reload();
  }

  /// The production wiring: `GET /yazan-mobile/v1/sync/catalog` and `GET /yazan-mobile/v1/me`.
  factory ProductsRepository.forClient(YazanApiClient client, {FeedStore? store, int limit = 50}) {
    return ProductsRepository(
      store: store,
      loadPermissions: () => client.getJson('/yazan-mobile/v1/me'),
      fetch: (cursor) async => DeltaPage.fromJson(
        await client.getJson(
          '/yazan-mobile/v1/sync/catalog',
          query: {'cursor': cursor, 'limit': limit},
        ),
      ),
    );
  }

  final ProductsFetch _fetch;
  final FeedStore _store;
  final PermissionsLoader? _permissionsLoader;
  late final Future<void> _ready;

  List<Map<String, dynamic>> _rows = const [];
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  bool _disposed = false;
  ApiError? _error;
  String _query = '';
  ProductPermissions _permissions = const ProductPermissions.unknown();

  /// Completes once the cached rows have been read.
  Future<void> get ready => _ready;

  bool get loading => _loading;

  /// True once a refresh has finished, successfully or not.
  bool get loaded => _loaded;
  bool get lastRefreshFailed => _failed;
  ApiError? get lastError => _error;
  ProductPermissions get permissions => _permissions;

  /// The server denied products to this account (403, or the permission map has no `products.view`).
  bool get noAccess => _error?.action == ErrorAction.hideFeature || !_permissions.canView;

  String get query => _query;

  /// Every cached product, most recently changed first (then highest id).
  List<ProductSummary> get all {
    final list = [for (final r in _rows) ProductSummary.fromJson(r)];
    list.sort((a, b) {
      final ad = a.modifiedAt;
      final bd = b.modifiedAt;
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

  /// [all] narrowed by the search text (name or SKU).
  List<ProductSummary> get products {
    final q = _query;
    final list = all;
    if (q.trim().isEmpty) return list;
    return [
      for (final p in list)
        if (p.matches(q)) p,
    ];
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _notify();
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
    await _refreshPermissions();
    if (!noAccess) {
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
      }
    }
    // Pages saved before a failure are kept, so read the store back either way.
    await _reload();
    _loading = false;
    _loaded = true;
    _notify();
  }

  Future<void> _refreshPermissions() async {
    final loader = _permissionsLoader;
    if (loader == null) return;
    try {
      _permissions = ProductPermissions.fromMe(await loader());
    } on Exception {
      // Offline or refused: keep what was known.
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
