import 'package:yazan_offline_sync/yazan_offline_sync.dart';

/// The name of the catalogue cache inside the local database.
const catalogueFeedName = 'products';

/// The account key everything that belongs to a signed-in customer is stored under.
///
/// The session holds no user id (the access and refresh tokens are opaque), and the profile id
/// would need a network call, or a second persisted copy, before it could be used offline. The
/// server binds one live session per device, so at most one customer is signed in on this install:
/// one fixed key is enough, and "forget the account" is exactly "wipe this key". The catalogue is
/// public and never lives under this key. To move to per-customer keys later, change this value
/// where the account becomes known; nothing else depends on it.
const signedInAccountId = 'customer';

/// What the app keeps on the phone between runs, behind a small seam so tests use memory.
abstract class StoreLocalData {
  /// True once, when the database file could not be read and was replaced by an empty one.
  bool get recreated;

  /// The cache of the public catalogue. It belongs to nobody, so signing in or out never touches it.
  FeedStore catalogue();

  /// Removes everything stored for the signed-in customer, and nothing else. The catalogue copy
  /// stays, so the shop still opens offline after signing out.
  Future<void> forgetAccount();
}

/// [StoreLocalData] over the encrypted database of `yazan_storage`.
class DurableLocalData implements StoreLocalData {
  DurableLocalData(this._storage);

  final YazanStorage _storage;

  @override
  bool get recreated => _storage.recreated;

  @override
  FeedStore catalogue() => _storage.feed(SqlFeedStore.guestAccountId, catalogueFeedName);

  @override
  Future<void> forgetAccount() => _storage.wipe(signedInAccountId);
}
