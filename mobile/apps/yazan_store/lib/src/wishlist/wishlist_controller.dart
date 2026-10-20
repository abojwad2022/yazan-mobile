import 'package:flutter/foundation.dart';

import '../account/failure.dart';
import 'wishlist_api.dart';
import 'wishlist_mirror.dart';
import 'wishlist_models.dart';

/// The app's view of the customer's favourites.
///
/// * Reading works offline: the last server answer is kept in a [WishlistMirror] and shown first.
/// * Writing is online only. The outbox package has no persistent store yet, and the server route is
///   a toggle (not a "set"), so a queued write could flip the wrong way after a restart. When
///   offline, a change is refused with a clear message and nothing changes locally.
/// * [setSaved] makes sure the server's state is known before it toggles, so one tap always means
///   what the person intended.
class WishlistController extends ChangeNotifier {
  WishlistController({required this.api, required this.mirror});

  final WishlistApi api;
  final WishlistMirror mirror;

  List<WishlistItem> _items = const [];
  bool _busy = false;

  /// True once the list on screen is known to match the server (a refresh succeeded).
  bool _synced = false;
  Failure? _failure;
  bool _refreshFailed = false;
  bool _disposed = false;

  /// Bumped by [forget]; answers that arrive for an older generation are ignored.
  int _generation = 0;

  List<WishlistItem> get items => _items;
  int get count => _items.length;
  bool get busy => _busy;

  /// The last failure, cleared by the next request.
  Failure? get failure => _failure;

  /// True while the list shown comes from the phone's copy because the server was not reached.
  bool get stale => _refreshFailed;

  bool contains(int productId) => _items.any((i) => i.id == productId);

  /// Shows the phone's copy at once, then asks the server.
  Future<void> load() async {
    final gen = _generation;
    List<WishlistItem>? saved;
    try {
      saved = await mirror.read();
    } catch (_) {
      saved = null;
    }
    if (gen != _generation) return;
    if (saved != null && !_synced) {
      _items = saved;
      _notify();
    }
    await refresh();
  }

  /// Replaces the list with the server's. On failure the current list stays and [stale] turns on.
  Future<bool> refresh() async {
    if (_busy) return false;
    final gen = _generation;
    _busy = true;
    _failure = null;
    _notify();
    try {
      final fresh = await api.list();
      if (gen != _generation) return false;
      _items = fresh;
      _synced = true;
      _refreshFailed = false;
      await _persist(fresh);
      return true;
    } catch (e) {
      if (gen == _generation) {
        _failure = Failure.from(e);
        _refreshFailed = true;
      }
      return false;
    } finally {
      if (gen == _generation) {
        _busy = false;
        _notify();
      }
    }
  }

  /// Saves or removes [item] on the server. Returns false (and sets [failure]) when it could not.
  Future<bool> setSaved(WishlistItem item, {required bool saved}) async {
    if (_busy) return false;
    if (!_synced) {
      final ok = await refresh();
      if (!ok) return false;
    }
    if (contains(item.id) == saved) return true;

    final gen = _generation;
    _busy = true;
    _failure = null;
    _notify();
    try {
      final result = await api.toggle(item.id);
      if (gen != _generation) return false;
      final next = <WishlistItem>[
        if (result.inList) item,
        for (final i in _items)
          if (i.id != item.id) i,
      ];
      _items = next;
      await _persist(next);
      return true;
    } catch (e) {
      if (gen == _generation) _failure = Failure.from(e);
      return false;
    } finally {
      if (gen == _generation) {
        _busy = false;
        _notify();
      }
    }
  }

  /// Sign-out: drops the list and the phone's copy, so the next customer starts clean.
  Future<void> forget() async {
    _generation++;
    _items = const [];
    _busy = false;
    _synced = false;
    _refreshFailed = false;
    _failure = null;
    _notify();
    try {
      await mirror.clear();
    } catch (_) {
      // Nothing more can be done; the copy is overwritten on the next sign-in.
    }
  }

  Future<void> _persist(List<WishlistItem> items) async {
    try {
      await mirror.write(items);
    } catch (_) {
      // The copy is a convenience; the server stays the source of truth.
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
