import 'package:yazan_domain/yazan_domain.dart';

import '../products/product_permissions.dart' show PermissionsLoader;
import 'account_id_store.dart';
import 'admin_stores.dart';

/// What [AccountLifecycle.verify] found out about who is really signed in.
enum AccountCheckKind {
  /// The server agrees with the cache.
  same,

  /// The server says a different staff member (stale cache): the old data was wiped, use
  /// [AccountCheck.stores].
  switched,

  /// The server no longer lets this session into the admin app: everything was wiped, sign out.
  accessLost,

  /// Could not ask (offline) or the answer had no id; nothing changed.
  unknown,
}

class AccountCheck {
  const AccountCheck(this.kind, [this.stores]);

  final AccountCheckKind kind;
  final AdminStores? stores;
}

/// Decides WHOSE data is on the phone and removes it when it must go.
///
/// The login response does carry `user.id`, but `YazanApiClient.login` only returns the tokens, so
/// the account id is taken from `GET /yazan-mobile/v1/me` (`id`) right after sign-in and kept in an
/// [AccountIdStore]. Rules:
///
/// * Data is keyed by that id (`<namespace>:<id>`; the namespace is the server host, so a staging
///   build and production never share an id). Another member of staff therefore can never read it,
///   even if a wipe was missed.
/// * A new sign-in whose id differs from the remembered one wipes the remembered account first.
/// * No session on start while an id is remembered means a sign-out or revocation that was not
///   finished: that account is wiped now.
/// * [forget] clears the remembered id only after the wipe succeeded, so a failed wipe is retried
///   on the next start instead of being forgotten.
class AccountLifecycle {
  AccountLifecycle({
    required this.storage,
    required this.ids,
    required this.loadMe,
    this.namespace = '',
    this.storageRecreated = false,
  });

  final AccountStorage storage;
  final AccountIdStore ids;

  /// `GET /yazan-mobile/v1/me`.
  final PermissionsLoader loadMe;
  final String namespace;

  /// The encrypted file was unreadable and has been replaced by an empty one (see
  /// `YazanStorage.recreated`). The shell tells the person once.
  final bool storageRecreated;

  String _scoped(int id) => namespace.isEmpty ? '$id' : '$namespace:$id';

  /// Cold start with a stored session.
  Future<AdminStores> forExistingSession() async {
    final stored = await ids.read();
    if (stored != null) return DurableAdminStores(storage, stored);
    // A session from before durable storage, or a first sign-in that was interrupted.
    final me = await _me();
    final id = me.id;
    if (id == null) return MemoryAdminStores();
    await ids.write(id);
    return DurableAdminStores(storage, id);
  }

  /// Right after a successful sign-in.
  Future<AdminStores> forNewSession() async {
    final me = await _me();
    final id = me.id;
    final stored = await ids.read();
    if (id == null) {
      // Cannot tell who this is, so cannot trust what is stored either.
      if (stored != null) await forget(null);
      return MemoryAdminStores();
    }
    if (stored != null && stored != id) await forget(null);
    await ids.write(id);
    return DurableAdminStores(storage, id);
  }

  /// Compares the cache with the server's answer. Called once after a cold start.
  Future<AccountCheck> verify(AdminStores current) async {
    final me = await _me();
    if (me.denied) {
      await forget(current);
      return const AccountCheck(AccountCheckKind.accessLost);
    }
    final id = me.id;
    if (id == null || !current.durable) return const AccountCheck(AccountCheckKind.unknown);
    if (id == current.accountId) return const AccountCheck(AccountCheckKind.same);
    await forget(current);
    await ids.write(id);
    return AccountCheck(AccountCheckKind.switched, DurableAdminStores(storage, id));
  }

  /// Sign-out, revoked session, lost access: removes [current] and any remembered account, then
  /// forgets the id. Returns false when a wipe failed; the id is then kept so the next start
  /// removes the data.
  Future<bool> forget(AdminStores? current) async {
    var clean = true;
    if (current != null) {
      // Through the stores themselves: that also stops a refresh still in flight from writing
      // its next page back.
      try {
        await current.wipe();
      } catch (_) {
        clean = false;
      }
    }
    final stored = await ids.read();
    if (stored != null && !(current != null && current.durable && current.accountId == stored)) {
      try {
        await storage.wipe(stored);
      } catch (_) {
        clean = false;
      }
    }
    if (clean) await ids.clear();
    return clean;
  }

  Future<({String? id, bool denied})> _me() async {
    try {
      final me = await loadMe();
      final raw = me['id'];
      final n = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (n == null || n < 1) return (id: null, denied: false);
      return (id: _scoped(n), denied: false);
    } on ApiError catch (e) {
      return (id: null, denied: e.action == ErrorAction.hideFeature);
    } catch (_) {
      return (id: null, denied: false);
    }
  }
}
