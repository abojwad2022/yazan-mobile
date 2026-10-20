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
///
/// The feed (`GET /yazan-mobile/v1/sync/customers`) answers `initial` only for an empty cursor and
/// keeps deleted-account tombstones for 90 days, so a phone that was offline longer, or whose
/// cursor the server refuses (400), would keep deleted customers forever. The repository therefore
/// starts over (empty cursor, rows replaced) when the last complete sync is older than
/// [staleAfter] or the server says the cursor is not valid. It also starts over when the server's
/// field policy changed under the cache: email/phone or the lifetime spend were granted since the
/// rows were stored, so the cached rows lack the key.
///
/// The time of the last complete sync lives in the same store as the rows, as a reserved row
/// (id [metaId]), so it is encrypted, per account and wiped with them.
class CustomersRepository extends ChangeNotifier {
  CustomersRepository({
    required CustomersFetch fetch,
    FeedStore? store,
    PermissionsLoader? loadPermissions,
    DateTime Function()? clock,
    this.staleAfter = const Duration(days: 80),
  })  : _fetch = fetch,
        _store = store ?? MemoryFeedStore(),
        _permissionsLoader = loadPermissions,
        _clock = clock ?? DateTime.now {
    _ready = _reload();
  }

  /// The production wiring: `GET /yazan-mobile/v1/sync/customers` and `GET /yazan-mobile/v1/me`.
  factory CustomersRepository.forClient(YazanApiClient client, {FeedStore? store, int limit = 50}) {
    return CustomersRepository(
      store: store,
      loadPermissions: () => client.getJson('/yazan-mobile/v1/me'),
      fetch: customersFeedFetch(customersFeedGet(client), limit: limit),
    );
  }

  /// The reserved row that records when the cache was last complete. Real customers have ids > 0.
  static const int metaId = -1;

  /// The server keeps tombstones 90 days; 10 days of margin for clock skew and slow retries.
  final Duration staleAfter;
  final DateTime Function() _clock;

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

  static bool _isCustomer(Map<String, dynamic> row) => row['id'] is int && (row['id'] as int) > 0;

  /// A cached row as this account may see it now: a permission lost since the row was stored hides
  /// the field at once (the server only stops sending it from then on).
  Map<String, dynamic> _visible(Map<String, dynamic> row) {
    final p = _permissions;
    if (!p.known || (p.canViewPii && p.canViewSpend)) return row;
    return {
      for (final e in row.entries)
        if (!((e.key == 'email' || e.key == 'phone') && !p.canViewPii) &&
            !(e.key == 'total_spent' && !p.canViewSpend))
          e.key: e.value,
    };
  }

  /// Every cached customer, by name (then id).
  List<CustomerSummary> get all {
    final list = [
      for (final r in _rows)
        if (_isCustomer(r)) CustomerSummary.fromJson(_visible(r)),
    ];
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

  /// Drops every cached row and the cursor, in memory and in the store. Called when the server
  /// stops letting this account see the feed, so the data does not linger on the phone. A later
  /// refresh starts from scratch.
  Future<void> purge() async {
    _rows = const [];
    await _reset();
    _notify();
  }

  /// Empties the store and the cursor, so the next pull is a first sync.
  Future<void> _reset() async {
    try {
      await _store.apply(upserts: const [], deletedIds: const [], cursor: '', initial: true);
    } on Exception {
      // The rows are gone from memory either way; the sign-out wipe removes the file content.
    }
  }

  Future<void> _reload() async {
    await _readRows();
    _notify();
  }

  Future<void> _readRows() async {
    try {
      _rows = await _store.readAll();
    } on Exception {
      // An unreadable cache shows as empty; the next pull fills it.
    }
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _notify();
    await _ready;
    await _refreshPermissions();
    if (!noAccess) {
      try {
        await _sync();
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

  Future<void> _sync() async {
    await _readRows();
    if (_cacheTooOld()) await _reset();
    var done = await _pull();
    if (done == null) {
      // The server refused the saved position: start over once.
      await _reset();
      done = await _pull(retry: true);
    }
    await _readRows();
    if (_fieldsMissing()) {
      await _reset();
      done = await _pull(retry: true);
      await _readRows();
    }
    if (done == true) await _stamp();
  }

  /// Pulls pages. Returns true when the server said there is nothing more, false when the run
  /// stopped early (page budget), and null when the server refused the cursor (only when [retry]
  /// is false; a second refusal is thrown).
  Future<bool?> _pull({bool retry = false}) async {
    var more = true;
    try {
      await pullFeed(
        fetch: (cursor) async {
          final page = await _fetch(cursor);
          more = page.hasMore;
          return page;
        },
        store: _store,
      );
    } on ApiError catch (e) {
      if (!retry && _badCursor(e)) return null;
      rethrow;
    }
    return !more;
  }

  static bool _badCursor(ApiError e) => e.status == 400 && e.code == 'yazan_mobile_bad_cursor';

  /// True when the last complete sync is older than [staleAfter] (tombstones may have expired).
  bool _cacheTooOld() {
    for (final r in _rows) {
      if (r['id'] == metaId) {
        final at = DateTime.tryParse('${r['synced_at'] ?? ''}');
        if (at == null) return false;
        return _clock().toUtc().difference(at.toUtc()) > staleAfter;
      }
    }
    return false;
  }

  /// A permission was granted after the rows were stored: they lack the key the server now sends.
  bool _fieldsMissing() {
    final p = _permissions;
    if (!p.known) return false;
    for (final r in _rows) {
      if (!_isCustomer(r)) continue;
      if (p.canViewPii && !r.containsKey('email')) return true;
      if (p.canViewSpend && !r.containsKey('total_spent')) return true;
    }
    return false;
  }

  Future<void> _stamp() async {
    try {
      await _store.apply(
        upserts: [
          {'id': metaId, 'meta': true, 'synced_at': _clock().toUtc().toIso8601String()},
        ],
        deletedIds: const [],
        cursor: await _store.readCursor(),
        initial: false,
      );
    } on Exception {
      // Without the stamp the staleness check simply does not fire.
    }
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
