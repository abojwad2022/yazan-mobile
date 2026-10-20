import 'wishlist_models.dart';

/// The phone's copy of the favourites, so the list can be read offline and after a restart.
///
/// It is a cache of what the server last said, never a second source of truth: every refresh
/// replaces it. The app clears it on sign-out.
abstract class WishlistMirror {
  /// The saved copy, or null when nothing has been saved yet.
  Future<List<WishlistItem>?> read();

  Future<void> write(List<WishlistItem> items);

  Future<void> clear();
}

class MemoryWishlistMirror implements WishlistMirror {
  MemoryWishlistMirror([this.items]);

  List<WishlistItem>? items;

  @override
  Future<List<WishlistItem>?> read() async => items;

  @override
  Future<void> write(List<WishlistItem> items) async => this.items = List<WishlistItem>.of(items);

  @override
  Future<void> clear() async => items = null;
}
