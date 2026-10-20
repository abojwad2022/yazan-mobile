import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../more/staff_permissions.dart';
import '../products/product_permissions.dart' show PermissionsLoader;
import 'coupon_api.dart';
import 'coupon_summary.dart';

/// The coupon list and its offline copy.
///
/// The coupon route is paged and has no change feed, so the cache is a snapshot: [refresh] reads
/// every page (at most [maxPages]) and, only when all of them arrived, replaces the rows in the
/// [FeedStore] (feed `coupons`, same encrypted per-account database as the other caches, wiped on
/// sign-out). On start the rows are read back so the list shows before any network round trip. A
/// failed refresh keeps what is cached and sets [lastRefreshFailed]. A 403, or a permission map
/// without `coupons.view`, sets [noAccess] and drops the cached rows.
///
/// Search is local, over the cached rows, so it works offline too.
class CouponsRepository extends ChangeNotifier {
  CouponsRepository({
    required CouponsFetch fetch,
    FeedStore? store,
    PermissionsLoader? loadPermissions,
    this.maxPages = 10,
  })  : _fetch = fetch,
        _store = store ?? MemoryFeedStore(),
        _permissionsLoader = loadPermissions {
    _ready = _reload();
  }

  factory CouponsRepository.forClient(YazanApiClient client, {FeedStore? store}) {
    return CouponsRepository(
      fetch: couponsFetch(client),
      store: store,
      loadPermissions: () => client.getJson('/yazan-mobile/v1/me'),
    );
  }

  /// A snapshot never holds more than `maxPages * couponsPerPage` coupons.
  final int maxPages;

  final CouponsFetch _fetch;
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
  StaffPermissions _permissions = const StaffPermissions.unknown();

  Future<void> get ready => _ready;
  bool get loading => _loading;

  /// True once a refresh has finished, successfully or not.
  bool get loaded => _loaded;
  bool get lastRefreshFailed => _failed;
  StaffPermissions get permissions => _permissions;

  bool get noAccess => _forbidden(_error) || !_permissions.allows('coupons.view');

  static bool _forbidden(ApiError? e) => e != null && (e.action == ErrorAction.hideFeature || e.status == 403);

  /// Editing is offered only when the map says so (unknown permissions keep it off).
  bool get canEdit => _permissions.known && _permissions.allows('coupons.edit');

  String get query => _query;

  static bool _isCoupon(Map<String, dynamic> row) => row['id'] is int && (row['id'] as int) > 0;

  /// Every cached coupon, newest first (highest id first).
  List<CouponSummary> get all {
    final list = [
      for (final r in _rows)
        if (_isCoupon(r)) CouponSummary.fromJson(r),
    ];
    list.sort((a, b) => b.id.compareTo(a.id));
    return list;
  }

  /// [all] narrowed by the search text.
  List<CouponSummary> get coupons {
    final list = all;
    if (_query.trim().isEmpty) return list;
    return [
      for (final c in list)
        if (c.matches(_query)) c,
    ];
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _notify();
  }

  /// Drops the cached rows (memory and store), for a revoked permission.
  Future<void> purge() async {
    _rows = const [];
    await _save(const []);
    _notify();
  }

  Future<void> _reload() async {
    await _readRows();
    _notify();
  }

  Future<void> _readRows() async {
    try {
      _rows = await _store.readAll();
    } on Exception {
      // An unreadable cache shows as empty; the next refresh fills it.
    }
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _notify();
    await _ready;
    await _refreshPermissions();
    if (noAccess) {
      if (_rows.isNotEmpty) await purge();
    } else {
      try {
        final items = await _pullAll();
        await _save(items);
        _rows = items;
        _failed = false;
        _error = null;
      } on ApiError catch (e) {
        _failed = true;
        _error = e;
        if (_forbidden(e)) await purge();
      } on Exception {
        _failed = true;
        _error = null;
      }
    }
    _loading = false;
    _loaded = true;
    _notify();
  }

  Future<List<Map<String, dynamic>>> _pullAll() async {
    final items = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final body = await _fetch(page);
      final raw = body['items'];
      if (raw is! List) throw const FormatException('coupons: items is not a list');
      for (final r in raw) {
        if (r is Map) items.add(Map<String, dynamic>.from(r));
      }
      final pages = body['total_pages'];
      final total = pages is num ? pages.toInt() : 1;
      if (page >= total || page >= maxPages) break;
      page++;
    }
    return items;
  }

  Future<void> _save(List<Map<String, dynamic>> items) async {
    try {
      await _store.apply(upserts: items, deletedIds: const [], cursor: '', initial: true);
    } on Exception {
      // A cache that cannot be written only means no offline copy next time.
    }
  }

  Future<void> _refreshPermissions() async {
    final loader = _permissionsLoader;
    if (loader == null) return;
    try {
      _permissions = StaffPermissions.fromMe(await loader());
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
