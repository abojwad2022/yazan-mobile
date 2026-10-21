import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../more/staff_permissions.dart';
import '../products/product_permissions.dart' show PermissionsLoader;
import 'staff_api.dart';
import 'staff_member.dart';

/// The staff list and its offline copy.
///
/// The users route is paged with no change feed, so the cache is a snapshot: [refresh] reads every
/// page (at most [maxPages]) and, only when all of them arrived, replaces the rows in the
/// [FeedStore] (feed `staff`, wiped with the account on sign-out) together with the time it was
/// taken (a [FeedMeta] slot, [fetchedAt], shown as "as of"). A failed refresh keeps what is cached
/// and sets [lastRefreshFailed]. A 403, or a permission map without `users.view`, sets [noAccess]
/// and drops the cached rows. Read-only: nothing here writes to the server.
class StaffRepository extends ChangeNotifier {
  StaffRepository({
    required StaffFetch fetch,
    FeedStore? store,
    PermissionsLoader? loadPermissions,
    DateTime Function()? clock,
    this.maxPages = 10,
  })  : _fetch = fetch,
        _store = store ?? MemoryFeedStore(),
        _permissionsLoader = loadPermissions,
        _clock = clock ?? DateTime.now {
    _ready = _reload();
  }

  factory StaffRepository.forClient(YazanApiClient client, {FeedStore? store}) {
    return StaffRepository(
      fetch: staffFetch(client),
      store: store,
      loadPermissions: () => client.getJson('/yazan-mobile/v1/me'),
    );
  }

  static const _metaKey = 'fetched_at';

  final int maxPages;
  final StaffFetch _fetch;
  final FeedStore _store;
  final PermissionsLoader? _permissionsLoader;
  final DateTime Function() _clock;
  late final Future<void> _ready;

  List<Map<String, dynamic>> _rows = const [];
  DateTime? _fetchedAt;
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  bool _disposed = false;
  ApiError? _error;
  String _query = '';
  StaffPermissions _permissions = const StaffPermissions.unknown();

  Future<void> get ready => _ready;
  bool get loading => _loading;
  bool get loaded => _loaded;
  bool get lastRefreshFailed => _failed;
  StaffPermissions get permissions => _permissions;

  /// When the cached list was taken from the server, or null (nothing cached).
  DateTime? get fetchedAt => _fetchedAt;

  bool get noAccess => _forbidden(_error) || !_permissions.allows('users.view');

  static bool _forbidden(ApiError? e) => e != null && (e.action == ErrorAction.hideFeature || e.status == 403);

  /// The permission summary needs `roles.view`; unknown permissions leave the server as the judge.
  bool get canViewRoles => _permissions.allows('roles.view');

  /// "Sign out on all devices" is offered only when the map says so (unknown keeps it off).
  bool get canForceLogout => _permissions.known && _permissions.allows('users.force_logout');

  String get query => _query;

  static bool _isMember(Map<String, dynamic> row) => row['id'] is int && (row['id'] as int) > 0;

  /// Every cached account, by name.
  List<StaffMember> get all {
    final list = [
      for (final r in _rows)
        if (_isMember(r)) StaffMember.fromJson(r),
    ];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// [all] narrowed by the search text.
  List<StaffMember> get members {
    final list = all;
    if (_query.trim().isEmpty) return list;
    return [
      for (final m in list)
        if (m.matches(_query)) m,
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
    _fetchedAt = null;
    await _save(const [], null);
    _notify();
  }

  Future<void> _reload() async {
    try {
      _rows = await _store.readAll();
      _fetchedAt = DateTime.tryParse(await _store.readMeta(_metaKey) ?? '');
    } on Exception {
      // An unreadable cache shows as empty; the next refresh fills it.
    }
    _notify();
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
        final now = _clock();
        await _save(items, now);
        _rows = items;
        _fetchedAt = now;
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
      if (raw is! List) throw const FormatException('users: items is not a list');
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

  Future<void> _save(List<Map<String, dynamic>> items, DateTime? at) async {
    try {
      await _store.apply(upserts: items, deletedIds: const [], cursor: '', initial: true);
      await _store.writeMeta(_metaKey, at?.toUtc().toIso8601String());
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
