import 'package:yazan_offline_sync/yazan_offline_sync.dart';

/// The mirrored feeds of the Admin app. The names are the `feed` column of the durable
/// store, so renaming one orphans the rows of the old name.
class AdminFeeds {
  const AdminFeeds._();

  static const orders = 'orders';
  static const products = 'products';
  static const customers = 'customers';
  static const dashboard = 'dashboard';
  static const reports = 'reports';
  static const inventory = 'inventory';

  /// The last coupon list (a snapshot, replaced on every refresh).
  static const coupons = 'coupons';

  /// The last shipping zones and tax settings (two snapshot rows, replaced on every refresh).
  static const shippingTax = 'shipping_tax';

  /// The first page of the whole activity log (one snapshot row, replaced on every refresh).
  static const activity = 'activity';
}

/// What the Admin app needs from durable storage, in the shape of `YazanStorage` but small enough
/// to fake in tests. Every method takes the staff account, so two accounts on one phone never share
/// a row.
abstract class AccountStorage {
  FeedStore feed(String accountId, String name);

  /// All accounts' queues; every [OutboxStore] method already takes the account id.
  OutboxStore get outbox;

  /// Removes everything stored for [accountId]: queue, cached rows and cursors.
  Future<void> wipe(String accountId);
}

/// [AccountStorage] over the encrypted database of `yazan_storage` / `yazan_offline_sync`.
class YazanAccountStorage implements AccountStorage {
  YazanAccountStorage(this._storage);

  final YazanStorage _storage;

  @override
  FeedStore feed(String accountId, String name) => _storage.feed(accountId, name);

  @override
  OutboxStore get outbox => _storage.outbox;

  @override
  Future<void> wipe(String accountId) => _storage.wipe(accountId);
}

/// Everything one signed-in staff member has on this phone: the three feed mirrors and the outbox.
abstract class AdminStores {
  String get accountId;

  /// True when the data survives a restart (encrypted database); false for the in-memory fallback.
  bool get durable;

  OutboxStore get outbox;
  FeedStore feed(String name);

  /// Deletes everything of this account: queued notes, cached orders, products and customers.
  Future<void> wipe();
}

/// Rows live as long as the process. The default for tests, and the fallback when the staff
/// account could not be identified (offline on the first start after an update).
class MemoryAdminStores implements AdminStores {
  MemoryAdminStores({this.accountId = 'admin-session'});

  @override
  final String accountId;
  final Map<String, MemoryFeedStore> _feeds = {};
  final MemoryOutboxStore _outbox = MemoryOutboxStore();
  final _WipeGate _gate = _WipeGate();

  @override
  bool get durable => false;

  @override
  OutboxStore get outbox => _outbox;

  @override
  FeedStore feed(String name) =>
      _GuardedFeedStore(_feeds.putIfAbsent(name, MemoryFeedStore.new), _gate);

  @override
  Future<void> wipe() async {
    _gate.closed = true;
    await _outbox.clearAccount(accountId);
    // Emptied in place: repositories still hold these objects.
    for (final f in _feeds.values) {
      f.rows.clear();
      f.cursor = '';
      f.meta.clear();
    }
  }
}

/// The encrypted, per-account stores.
class DurableAdminStores implements AdminStores {
  DurableAdminStores(this._storage, this.accountId);

  final AccountStorage _storage;
  final _WipeGate _gate = _WipeGate();

  @override
  final String accountId;

  @override
  bool get durable => true;

  @override
  OutboxStore get outbox => _storage.outbox;

  @override
  FeedStore feed(String name) => _GuardedFeedStore(_storage.feed(accountId, name), _gate);

  @override
  Future<void> wipe() {
    _gate.closed = true;
    return _storage.wipe(accountId);
  }
}

/// Set when an account's stores are wiped.
class _WipeGate {
  bool closed = false;
}

/// A feed that stops accepting pages once its stores were wiped. A refresh that was still in flight
/// when the person signed out would otherwise write its next page back after the wipe.
///
/// Feed metadata (`FeedMeta.readMeta` / `writeMeta`) is passed through to the wrapped store, and
/// is equally refused after the wipe; over a store without metadata it stores nothing.
class _GuardedFeedStore implements FeedStore, FeedMetaStore {
  _GuardedFeedStore(this._inner, this._gate);

  final FeedStore _inner;
  final _WipeGate _gate;

  @override
  Future<String> readCursor() => _inner.readCursor();

  @override
  Future<String?> readMeta(String key) => _inner.readMeta(key);

  @override
  Future<void> writeMeta(String key, String? value) async {
    if (_gate.closed) return;
    await _inner.writeMeta(key, value);
  }

  @override
  Future<List<Map<String, dynamic>>> readAll() => _inner.readAll();

  @override
  Future<void> apply({
    required List<Map<String, dynamic>> upserts,
    required List<int> deletedIds,
    required String cursor,
    required bool initial,
  }) async {
    if (_gate.closed) return;
    await _inner.apply(upserts: upserts, deletedIds: deletedIds, cursor: cursor, initial: initial);
  }
}
