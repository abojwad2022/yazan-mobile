import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'activity_snapshot.dart';

/// `GET /yazan/v1/audit` (needs `audit.view`): one page of the activity log, newest first, with the
/// filter facets. [query] holds `page`, `per_page` and the filter parameters.
typedef AuditFetch = Future<Map<String, dynamic>> Function(Map<String, dynamic> query);

AuditFetch auditFetch(YazanApiClient client) =>
    (query) => client.getJson('/yazan/v1/audit', query: query);

/// Reads the activity log, read only, a page at a time, and keeps the first page of the whole log
/// for offline use.
///
/// Online first: [refresh] asks for page 1 under the current [filter] and replaces what is shown;
/// [loadMore] appends the next page. Only the unfiltered first page is saved, as one row (id
/// [rowId]) of a [FeedStore] in the encrypted per-account database, with its "as of" time. A failed
/// refresh keeps the cached copy and sets [lastRefreshFailed]; a failed [loadMore] keeps what is
/// shown and sets [loadMoreFailed]. A 403 (`ErrorAction.hideFeature`) sets [noAccess] and drops the
/// cached copy, so a revoked permission does not leave the log on the phone.
///
/// Changing the filter discards any answer still in flight for the old one.
class ActivityRepository extends ChangeNotifier {
  ActivityRepository({
    required AuditFetch fetch,
    FeedStore? store,
    DateTime Function()? clock,
    this.perPage = 50,
  })  : _fetch = fetch,
        _store = store ?? MemoryFeedStore(),
        _clock = clock ?? DateTime.now {
    _ready = _reload();
  }

  /// The production wiring over the API client.
  factory ActivityRepository.forClient(YazanApiClient client, {FeedStore? store}) =>
      ActivityRepository(fetch: auditFetch(client), store: store);

  /// The row id of the cached first page.
  static const rowId = 1;

  /// Entries asked for per page (the web dashboard's 50).
  final int perPage;

  final AuditFetch _fetch;
  final FeedStore _store;
  final DateTime Function() _clock;
  late final Future<void> _ready;

  ActivitySnapshot? _cached;
  ActivitySnapshot? _snapshot;
  AuditFacets _facets = const AuditFacets();
  ActivityFilter _filter = const ActivityFilter();
  int _generation = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loaded = false;
  bool _failed = false;
  bool _moreFailed = false;
  bool _noAccess = false;
  bool _disposed = false;

  /// Completes once the cached first page has been read.
  Future<void> get ready => _ready;

  /// What is shown: the pages read so far under [filter]; null while a new filter is loading or when
  /// nothing could be read.
  ActivitySnapshot? get snapshot => _snapshot;

  /// The latest filter choices the server gave, kept while a filtered page loads.
  AuditFacets get facets => _facets;
  ActivityFilter get filter => _filter;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;

  /// True once a refresh has finished, successfully or not.
  bool get loaded => _loaded;
  bool get lastRefreshFailed => _failed;
  bool get loadMoreFailed => _moreFailed;
  bool get noAccess => _noAccess;

  Future<void> _reload() async {
    try {
      for (final r in await _store.readAll()) {
        if (r['id'] == rowId) {
          final cached = ActivitySnapshot.fromJson(r);
          _cached = cached;
          if (_snapshot == null && _filter.isEmpty) _snapshot = cached;
          if (_facets.isEmpty) _facets = cached.facets;
        }
      }
    } on Exception {
      // An unreadable cache shows as empty; the next refresh fills it.
    }
    _notify();
  }

  /// Narrows the log to [next] and reads its first page. The whole log shows its cached copy at
  /// once; a filtered view shows nothing until its answer arrives.
  Future<void> setFilter(ActivityFilter next) {
    if (next == _filter) return Future.value();
    _filter = next;
    _snapshot = next.isEmpty ? _cached : null;
    _failed = false;
    return refresh();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    _loading = true;
    _loadingMore = false;
    _moreFailed = false;
    _notify();
    await _ready;
    if (generation != _generation || _disposed) return;
    final filter = _filter;
    try {
      final next = ActivitySnapshot.fromServer(await _fetch(_query(filter, 1)), fetchedAt: _clock());
      if (generation != _generation || _disposed) return;
      _snapshot = next;
      if (!next.facets.isEmpty || filter.isEmpty) _facets = next.facets;
      _noAccess = false;
      _failed = false;
      if (filter.isEmpty) {
        _cached = next;
        await _save(next);
      }
    } on ApiError catch (e) {
      if (generation != _generation || _disposed) return;
      if (e.action == ErrorAction.hideFeature) {
        await _forbid();
      } else {
        _failed = true;
      }
    } on Exception {
      if (generation != _generation || _disposed) return;
      _failed = true;
    }
    _loading = false;
    _loaded = true;
    _notify();
  }

  /// Appends the next page, when there is one and nothing else is loading.
  Future<void> loadMore() async {
    final current = _snapshot;
    if (current == null || !current.hasMore || _loading || _loadingMore) return;
    final generation = _generation;
    _loadingMore = true;
    _moreFailed = false;
    _notify();
    try {
      final next = ActivitySnapshot.fromServer(
        await _fetch(_query(_filter, current.page + 1)),
        fetchedAt: current.fetchedAt,
      );
      if (generation != _generation || _disposed) return;
      _snapshot = current.append(next);
      if (!next.facets.isEmpty) _facets = next.facets;
    } on ApiError catch (e) {
      if (generation != _generation || _disposed) return;
      if (e.action == ErrorAction.hideFeature) {
        await _forbid();
      } else {
        _moreFailed = true;
      }
    } on Exception {
      if (generation != _generation || _disposed) return;
      _moreFailed = true;
    }
    _loadingMore = false;
    _notify();
  }

  Map<String, dynamic> _query(ActivityFilter filter, int page) => {
        'page': '$page',
        'per_page': '$perPage',
        ...filter.toQuery(),
      };

  Future<void> _forbid() async {
    _noAccess = true;
    _failed = false;
    _moreFailed = false;
    _snapshot = null;
    _cached = null;
    _facets = const AuditFacets();
    await _drop();
  }

  Future<void> _save(ActivitySnapshot snapshot) async {
    try {
      await _store.apply(
        upserts: [
          {...snapshot.toJson(), 'id': rowId},
        ],
        deletedIds: const [],
        cursor: '',
        initial: false,
      );
    } on Exception {
      // A cache that cannot be written only means no offline copy next time.
    }
  }

  Future<void> _drop() async {
    try {
      await _store.apply(upserts: const [], deletedIds: const [rowId], cursor: '', initial: false);
    } on Exception {
      // Nothing more to do for an unwritable cache.
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
