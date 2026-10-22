import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/more/more_registry.dart';
import 'package:yazan_admin/src/more/staff_permissions.dart';
import 'package:yazan_admin/src/users/staff_detail_controller.dart';
import 'package:yazan_admin/src/users/staff_member.dart';
import 'package:yazan_admin/src/users/staff_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../customers/fakes.dart' show customersMe;
import 'fakes.dart';

StaffRepository _repo({Object? fail, List<String>? permissions, FeedStore? store, int pages = 1}) {
  return StaffRepository(
    store: store,
    clock: () => DateTime.utc(2026, 10, 22, 8, 30),
    fetch: (page) async {
      if (fail != null) throw fail;
      return staffPage(pages == 1 ? staffRows : [staffRows[page - 1]], totalPages: pages);
    },
    loadPermissions: permissions == null ? null : () async => customersMe(permissions),
  );
}

StaffDetailController _controller(FakeStaffServer s, {List<String> slugs = const ['users.view', 'roles.view', 'users.force_logout']}) {
  var n = 0;
  return StaffDetailController(
    member: StaffMember.fromJson(staffRows[1]),
    loadRoles: s.roles,
    signOut: s.signOut,
    permissions: StaffPermissions.of(slugs),
    newKey: () => 'key-${++n}',
  );
}

/// A store whose writes fail with [error] (an [Error], not an [Exception]) while it is set.
class _BrokenStore extends MemoryFeedStore {
  Object? error;

  @override
  Future<void> apply({
    required List<Map<String, dynamic>> upserts,
    required List<int> deletedIds,
    required String cursor,
    required bool initial,
  }) async {
    final e = error;
    if (e != null) throw e;
    return super.apply(upserts: upserts, deletedIds: deletedIds, cursor: cursor, initial: initial);
  }
}

void main() {
  test('the registry has Staff behind users.view', () {
    expect(moreEntries.firstWhere((e) => e.key == 'staff').permission, 'users.view');
  });

  group('StaffMember', () {
    test('parses a row and survives odd fields', () {
      final m = StaffMember.fromJson(staffRows[0]);
      expect(m.name, 'Sara Manager');
      expect(m.roles.single.name, 'Manager');
      expect(m.lastLoginShort, '2026-10-20 14:05');
      expect(m.isSelf, isTrue);
      final odd = StaffMember.fromJson({'id': '9', 'login': 'x', 'roles': 'no'});
      expect(odd.id, 9);
      expect(odd.name, 'x');
      expect(odd.roles, isEmpty);
      expect(odd.suspended, isFalse);
    });

    test('search matches name, email and role', () {
      final m = StaffMember.fromJson(staffRows[1]);
      expect(m.matches('omar'), isTrue);
      expect(m.matches('PACKER'), isTrue);
      expect(m.matches('example.test'), isTrue);
      expect(m.matches('zzz'), isFalse);
    });

    test('role permissions are grouped by area', () {
      final s = RolePermissionSummary.fromJson((rolesBody()['items'] as List)[1] as Map<String, dynamic>);
      expect(s.groups, {
        'orders': ['edit', 'view'],
        'products': ['view'],
        'reports': ['view'],
      });
      expect(s.count, 4);
    });
  });

  group('StaffRepository', () {
    test('refresh caches the list with its time, and a failed refresh keeps both', () async {
      final store = MemoryFeedStore();
      final ok = _repo(store: store);
      await ok.refresh();
      expect(ok.all.map((m) => m.name), ['Omar Packer', 'Sara Manager', 'المالك']);
      expect(ok.fetchedAt, DateTime.utc(2026, 10, 22, 8, 30));

      final offline = _repo(store: store, fail: Exception('offline'));
      await offline.refresh();
      expect(offline.lastRefreshFailed, isTrue);
      expect(offline.all, hasLength(3));
      expect(offline.fetchedAt, DateTime.utc(2026, 10, 22, 8, 30));
    });

    test('reads every page', () async {
      final repo = _repo(pages: 3);
      await repo.refresh();
      expect(repo.all, hasLength(3));
    });

    test('a 403 or a map without users.view drops the cache', () async {
      final store = MemoryFeedStore();
      await _repo(store: store).refresh();
      final denied = _repo(store: store, permissions: ['orders.view']);
      await denied.refresh();
      expect(denied.noAccess, isTrue);
      expect(denied.all, isEmpty);
      expect(store.rows, isEmpty);

      await _repo(store: store).refresh();
      final forbidden = _repo(store: store, fail: const ApiError(status: 403, code: 'rest_forbidden'));
      await forbidden.refresh();
      expect(forbidden.noAccess, isTrue);
      expect(forbidden.all, isEmpty);
    });

    test('no access purges the store even when nothing was read into memory', () async {
      final store = MemoryFeedStore();
      final repo = _repo(store: store, permissions: ['orders.view']);
      await repo.ready;
      expect(repo.all, isEmpty);
      // Rows the reload never saw (written after it, or unreadable then) are on the phone.
      await store.apply(upserts: staffRows, deletedIds: const [], cursor: '', initial: true);
      await store.writeMeta('fetched_at', '2026-10-22T08:30:00.000Z');

      await repo.refresh();
      expect(repo.noAccess, isTrue);
      expect(store.rows, isEmpty);
      expect(store.meta, isEmpty);
    });

    test('a row with a malformed id is skipped; the rest of the page is kept', () async {
      final store = MemoryFeedStore();
      var calls = 0;
      final repo = StaffRepository(
        store: store,
        fetch: (page) async {
          calls++;
          return staffPage([
            {...staffRows[0], 'id': 'five'},
            staffRows[1],
            {...staffRows[2], 'id': null},
          ]);
        },
      );
      await repo.refresh();
      expect(repo.loading, isFalse);
      expect(repo.lastRefreshFailed, isFalse);
      expect(repo.all.map((m) => m.id), [6]);
      expect(store.rows.keys, [6]);

      await repo.refresh();
      expect(calls, 2);
    });

    test('a store write that throws an Error does not wedge refresh', () async {
      final store = _BrokenStore()..error = TypeError();
      var calls = 0;
      final repo = StaffRepository(
        store: store,
        fetch: (page) async {
          calls++;
          return staffPage(staffRows);
        },
      );
      await repo.refresh();
      expect(repo.loading, isFalse);
      expect(repo.loaded, isTrue);

      store.error = null;
      await repo.refresh();
      expect(calls, 2);
      expect(repo.loading, isFalse);
      expect(store.rows, hasLength(3));
    });

    test('a fetch that throws an Error is a failed refresh, not a stuck one', () async {
      var calls = 0;
      final repo = StaffRepository(
        fetch: (page) async {
          calls++;
          if (calls == 1) throw StateError('odd body');
          return staffPage(staffRows);
        },
      );
      await repo.refresh();
      expect(repo.loading, isFalse);
      expect(repo.lastRefreshFailed, isTrue);

      await repo.refresh();
      expect(calls, 2);
      expect(repo.lastRefreshFailed, isFalse);
      expect(repo.all, hasLength(3));
    });

    test('force-logout is offered only when the map lists it', () async {
      final a = _repo(permissions: ['users.view', 'users.force_logout']);
      await a.refresh();
      expect(a.canForceLogout, isTrue);
      final b = _repo(permissions: ['users.view']);
      await b.refresh();
      expect(b.canForceLogout, isFalse);
      expect(_repo().canForceLogout, isFalse); // unknown keeps it off
    });
  });

  group('StaffDetailController', () {
    test('loads the role summaries only with roles.view', () async {
      final s = FakeStaffServer();
      final c = _controller(s);
      await c.loadRoles();
      expect(c.summaryFor(c.member.roles.single), isNotNull);

      final denied = _controller(s, slugs: ['users.view']);
      await denied.loadRoles();
      expect(denied.rolesDenied, isTrue);
      expect(denied.summaryFor(denied.member.roles.single), isNull);
    });

    test('a failed roles load is flagged, a 403 hides the summary', () async {
      final s = FakeStaffServer()..rolesError = Exception('offline');
      final c = _controller(s);
      await c.loadRoles();
      expect(c.rolesFailed, isTrue);
      s.rolesError = const ApiError(status: 403, code: 'rest_forbidden');
      await c.loadRoles();
      expect(c.rolesDenied, isTrue);
    });

    test('sign-out sends one request with an idempotency key', () async {
      final s = FakeStaffServer();
      final c = _controller(s);
      expect(await c.signOutEverywhere(), StaffSignOutResult.done);
      expect(s.signOuts.single.id, 6);
      expect(s.signOuts.single.key, 'key-1');
      expect(c.canRetry, isFalse);
      // A later request is a new intent.
      await c.signOutEverywhere();
      expect(s.signOuts.last.key, 'key-2');
    });

    test('offline keeps the key for the retry', () async {
      final s = FakeStaffServer()..signOutFailures.add(Exception('offline'));
      final c = _controller(s);
      expect(await c.signOutEverywhere(), StaffSignOutResult.offline);
      expect(c.canRetry, isTrue);
      expect(await c.retry(), StaffSignOutResult.done);
      expect(s.signOuts.map((e) => e.key), ['key-1', 'key-1']);
    });

    test('busy keeps the key; 403 closes the attempt', () async {
      final s = FakeStaffServer()
        ..signOutFailures.addAll([
          const ApiError(status: 409, code: 'yazan_idempotency_busy'),
          const ApiError(status: 403, code: 'rest_forbidden'),
        ]);
      final c = _controller(s);
      expect(await c.signOutEverywhere(), StaffSignOutResult.busy);
      expect(c.canRetry, isTrue);
      expect(await c.retry(), StaffSignOutResult.noAccess);
      expect(c.canRetry, isFalse);
    });

    test('without users.force_logout nothing is sent', () async {
      final s = FakeStaffServer();
      final c = _controller(s, slugs: ['users.view', 'roles.view']);
      expect(c.canSignOut, isFalse);
      expect(await c.signOutEverywhere(), StaffSignOutResult.noAccess);
      expect(s.signOuts, isEmpty);
    });

    test('a 200 without ok is a failure, not a success', () async {
      final s = FakeStaffServer()..signOutAnswer = {'ok': false};
      final c = _controller(s);
      expect(await c.signOutEverywhere(), StaffSignOutResult.failed);
    });
  });
}
