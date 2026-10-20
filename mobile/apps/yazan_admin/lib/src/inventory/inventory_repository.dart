import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'stock_snapshot.dart';

/// `GET /yazan/v1/reports/stock` (needs `inventory.view`): out of stock, low stock and the
/// low-stock threshold. Read only; quick stock edits belong to the products screen.
typedef StockFetch = Future<Map<String, dynamic>> Function();

StockFetch stockFetch(YazanApiClient client) => () => client.getJson('/yazan/v1/reports/stock');

/// Loads the stock report and keeps the last good answer for offline use.
///
/// Online first: [refresh] asks the server and replaces the snapshot, which is saved as one row
/// (id 1) of a [FeedStore] in the encrypted per-account database. A failed refresh keeps the cached
/// copy and sets [lastRefreshFailed]. A 403 sets [noAccess] and drops the cached copy.
class InventoryRepository extends ChangeNotifier {
  InventoryRepository({
    required StockFetch fetch,
    FeedStore? store,
    DateTime Function()? clock,
  })  : _fetch = fetch,
        _store = store ?? MemoryFeedStore(),
        _clock = clock ?? DateTime.now {
    _ready = _reload();
  }

  /// The production wiring over the API client.
  factory InventoryRepository.forClient(YazanApiClient client, {FeedStore? store}) =>
      InventoryRepository(fetch: stockFetch(client), store: store);

  /// The row id of the single cached snapshot.
  static const rowId = 1;

  final StockFetch _fetch;
  final FeedStore _store;
  final DateTime Function() _clock;
  late final Future<void> _ready;

  StockSnapshot? _snapshot;
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  bool _noAccess = false;
  bool _disposed = false;

  /// Completes once the cached snapshot has been read.
  Future<void> get ready => _ready;

  StockSnapshot? get snapshot => _snapshot;
  bool get loading => _loading;

  /// True once a refresh has finished, successfully or not.
  bool get loaded => _loaded;
  bool get lastRefreshFailed => _failed;
  bool get noAccess => _noAccess;

  Future<void> _reload() async {
    try {
      for (final r in await _store.readAll()) {
        if (r['id'] == rowId) _snapshot = StockSnapshot.fromJson(r);
      }
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
    try {
      final next = StockSnapshot.fromServer(await _fetch(), fetchedAt: _clock());
      _snapshot = next;
      _noAccess = false;
      _failed = false;
      await _save(next);
    } on ApiError catch (e) {
      _failed = true;
      if (e.action == ErrorAction.hideFeature) {
        _noAccess = true;
        _failed = false;
        _snapshot = null;
        await _save(null);
      }
    } on Exception {
      _failed = true;
    }
    _loading = false;
    _loaded = true;
    _notify();
  }

  Future<void> _save(StockSnapshot? snapshot) async {
    try {
      await _store.apply(
        upserts: [
          if (snapshot != null) {'id': rowId, ...snapshot.toJson()},
        ],
        deletedIds: snapshot == null ? const [rowId] : const [],
        cursor: '',
        initial: false,
      );
    } on Exception {
      // A cache that cannot be written only means no offline copy next time.
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
