import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../products/product_permissions.dart' show PermissionsLoader;
import 'customer_api.dart';
import 'customer_permissions.dart';
import 'customer_summary.dart';

/// Reads the customer feed into a [FeedStore] and exposes it for browsing and search.
///
/// Same shape as `ProductsRepository`: on start the list is seeded from [FeedStore.readAll], so
/// the cache shows before any network round trip; a failed refresh keeps what is cached and sets
/// [lastRefreshFailed]; a 403 (`ErrorAction.hideFeature`) sets [noAccess].
///
/// Permission to see customers comes from the `/me` permission map ([loadPermissions]); when it
/// says no, the list is hidden and nothing is pulled. The store defaults to memory, so the personal
/// data lives only as long as the signed-in screen that owns this repository and is gone on
/// sign-out.
class CustomersRepository extends ChangeNotifier {
  CustomersRepository({
    required CustomersFetch fetch,
    FeedStore? store,
    PermissionsLoader? loadPermissions,
  })  : _fetch = fetch,
        _store = store ?? MemoryFeedStore(),
        _permissionsLoader = loadPermissions {
    _ready = _reload();
  }

  /// The production wiring: the customers list over `GET /yazan/v1/customers` presented as a feed
  /// (see [pagedCustomersFetch]) and `GET /yazan-mobile/v1/me`.
  factory CustomersRepository.forClient(YazanApiClient client, {FeedStore? store, int limit = 50}) {
    return CustomersRepository(
      store: store,
      loadPermissions: () => client.getJson('/yazan-mobile/v1/me'),
      fetch: pagedCustomersFetch(customersPageGet(client), limit: limit),
    );
  }

  final CustomersFetch _fetch;
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
  CustomerPermissions _permissions = const CustomerPermissions.unknown();

  /// Completes once the cached rows have been read.
  Future<void> get ready => _ready;

  bool get loading => _loading;

  /// True once a refresh has finished, successfully or not.
  bool get loaded => _loaded;
  bool get lastRefreshFailed => _failed;
  ApiError? get lastError => _error;
  CustomerPermissions get permissions => _permissions;

  /// The server denied customers to this account (403, or the permission map has no
  /// `customers.view`).
  bool get noAccess => _error?.action == ErrorAction.hideFeature || !_permissions.canView;

  String get query => _query;

  /// Every cached customer, by name (then id).
  List<CustomerSummary> get all {
    final list = [for (final r in _rows) CustomerSummary.fromJson(r)];
    list.sort((a, b) {
      final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return list;
  }

  /// [all] narrowed by the search text (name, email or phone).
  List<CustomerSummary> get customers {
    final q = _query;
    final list = all;
    if (q.trim().isEmpty) return list;
    return [
      for (final c in list)
        if (c.matches(q)) c,
    ];
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
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
      _permissions = CustomerPermissions.fromMe(await loader());
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
