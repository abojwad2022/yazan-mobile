import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/more/staff_permissions.dart';
import 'package:yazan_admin/src/users/staff_detail_page.dart';
import 'package:yazan_admin/src/users/staff_list_page.dart';
import 'package:yazan_admin/src/users/staff_member.dart';
import 'package:yazan_admin/src/users/staff_repository.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../customers/fakes.dart' show customersHost, customersMe;
import 'fakes.dart';

StaffRepository _repo({Object? fail, List<String>? permissions, FeedStore? store}) {
  return StaffRepository(
    store: store,
    clock: () => DateTime(2026, 10, 22, 8, 30),
    fetch: (_) async {
      if (fail != null) throw fail;
      return staffPage(staffRows);
    },
    loadPermissions: permissions == null ? null : () async => customersMe(permissions),
  );
}

StaffDetailPage _detail(
  FakeStaffServer server, {
  int row = 1,
  List<String> slugs = const ['users.view', 'roles.view', 'users.force_logout'],
}) {
  var n = 0;
  return StaffDetailPage(
    member: StaffMember.fromJson(staffRows[row]),
    loadRoles: server.roles,
    signOut: server.signOut,
    permissions: StaffPermissions.of(slugs),
    newKey: () => 'key-${++n}',
  );
}

Future<void> _show(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

void main() {
  group('list', () {
    testWidgets('renders name, email, role badge, suspended badge and last sign-in (en)', (tester) async {
      await tester.pumpWidget(customersHost(const Locale('en'), StaffListPage(repository: _repo(), onOpen: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text('Sara Manager (You)'), findsOneWidget);
      expect(find.text('sara@example.test'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('staff-role-5'))).data, 'Manager');
      expect(find.byKey(const ValueKey('staff-suspended-6')), findsOneWidget);
      expect(find.byKey(const ValueKey('staff-suspended-5')), findsNothing);
      expect(find.textContaining('2026-10-20 14:05'), findsOneWidget);
      expect(find.text('Never signed in'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('staff-role-7'))).data, 'Owner');
    });

    testWidgets('renders right-to-left in Arabic', (tester) async {
      await tester.pumpWidget(customersHost(const Locale('ar'), StaffListPage(repository: _repo(), onOpen: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text('لم يسجّل الدخول بعد'), findsOneWidget);
      expect(find.text('موقوف'), findsOneWidget);
      expect(find.text('المالك'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('المالك'))), TextDirection.rtl);
    });

    testWidgets('search narrows the list and says when nothing matches', (tester) async {
      await tester.pumpWidget(customersHost(const Locale('en'), StaffListPage(repository: _repo(), onOpen: (_) {})));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('staff-search')), 'packer');
      await tester.pumpAndSettle();
      expect(find.text('Omar Packer'), findsOneWidget);
      expect(find.text('Sara Manager (You)'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('staff-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No staff member matches “zzz”.'), findsOneWidget);
    });

    testWidgets('a failed refresh shows the cached list with the offline badge and "As of"', (tester) async {
      final store = MemoryFeedStore();
      await _repo(store: store).refresh();
      await tester.pumpWidget(customersHost(
        const Locale('en'),
        StaffListPage(repository: _repo(fail: Exception('offline'), store: store), onOpen: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Omar Packer'), findsOneWidget);
      expect(find.text('Offline copy'), findsOneWidget);
      expect(find.byKey(const ValueKey('staff-as-of')), findsOneWidget);
      expect(find.textContaining('As of'), findsOneWidget);
    });

    testWidgets('an empty cache and a failed refresh says so', (tester) async {
      await tester.pumpWidget(customersHost(
        const Locale('en'),
        StaffListPage(repository: _repo(fail: Exception('offline')), onOpen: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Could not load staff. Pull down to try again.'), findsOneWidget);
    });

    testWidgets('no users.view in the permission map shows the lock', (tester) async {
      await tester.pumpWidget(customersHost(
        const Locale('en'),
        StaffListPage(repository: _repo(permissions: ['orders.view']), onOpen: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No access'), findsOneWidget);
      expect(find.byKey(const ValueKey('staff-search')), findsNothing);
    });

    testWidgets('pull to refresh reloads', (tester) async {
      var calls = 0;
      final repo = StaffRepository(fetch: (_) async {
        calls++;
        return staffPage(staffRows);
      });
      await tester.pumpWidget(customersHost(const Locale('en'), StaffListPage(repository: repo, onOpen: (_) {})));
      await tester.pumpAndSettle();
      final before = calls;
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
      await tester.pumpAndSettle();
      expect(calls, before + 1);
    });

    testWidgets('tapping a row opens it', (tester) async {
      StaffMember? opened;
      await tester.pumpWidget(customersHost(const Locale('en'), StaffListPage(repository: _repo(), onOpen: (m) => opened = m)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('staff-6')));
      expect(opened?.name, 'Omar Packer');
    });
  });

  group('detail', () {
    testWidgets('shows the account, the role and its permission summary (en)', (tester) async {
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(FakeStaffServer(), row: 0)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff-email')), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('orders: edit, view'), findsOneWidget);
      expect(find.text('4 permissions'), findsOneWidget);
      expect(find.byKey(const ValueKey('staff-readonly-note')), findsOneWidget);
    });

    testWidgets('an owner role shows full access, a role without grants says so', (tester) async {
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(FakeStaffServer(), row: 2)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('perm-full-1')), findsOneWidget);

      await tester.pumpWidget(customersHost(const Locale('en'), _detail(FakeStaffServer(), row: 1)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('perm-none-3')), findsOneWidget);
    });

    testWidgets('is right-to-left in Arabic', (tester) async {
      await tester.pumpWidget(customersHost(const Locale('ar'), _detail(FakeStaffServer())));
      await tester.pumpAndSettle();
      expect(find.text('ما يستطيع هذا الدور فعله'), findsOneWidget);
      await _show(tester, find.byKey(const ValueKey('staff-signout')));
      expect(find.text('تسجيل الخروج من كل الأجهزة'), findsOneWidget);
      expect(Directionality.of(tester.element(find.byKey(const ValueKey('staff-signout')))), TextDirection.rtl);
    });

    testWidgets('without roles.view the summary is replaced by a note', (tester) async {
      await tester.pumpWidget(customersHost(
        const Locale('en'),
        _detail(FakeStaffServer(), slugs: const ['users.view', 'users.force_logout']),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('perm-hidden')), findsOneWidget);
    });

    testWidgets('a failed roles load offers a retry', (tester) async {
      final server = FakeStaffServer()..rolesError = Exception('offline');
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('perm-failed')), findsOneWidget);
      server.rolesError = null;
      await tester.tap(find.byKey(const ValueKey('perm-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('perm-failed')), findsNothing);
      expect(find.byKey(const ValueKey('perm-none-3')), findsOneWidget);
    });

    testWidgets('sign out asks for confirmation, then sends one request with a key', (tester) async {
      final server = FakeStaffServer();
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server)));
      await tester.pumpAndSettle();
      await _show(tester, find.byKey(const ValueKey('staff-signout')));
      await tester.tap(find.byKey(const ValueKey('staff-signout')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sign Omar Packer out on all devices?'), findsOneWidget);
      expect(server.signOuts, isEmpty); // nothing before the confirmation
      await tester.tap(find.byKey(const ValueKey('confirm-signout')));
      await tester.pumpAndSettle();
      expect(server.signOuts.single.id, 6);
      expect(server.signOuts.single.key, 'key-1');
      expect(find.text('Signed out on all devices.'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      final server = FakeStaffServer();
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server)));
      await tester.pumpAndSettle();
      await _show(tester, find.byKey(const ValueKey('staff-signout')));
      await tester.tap(find.byKey(const ValueKey('staff-signout')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.signOuts, isEmpty);
    });

    testWidgets('offline keeps the message and retries with the same key', (tester) async {
      final server = FakeStaffServer()..signOutFailures.add(Exception('offline'));
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server)));
      await tester.pumpAndSettle();
      await _show(tester, find.byKey(const ValueKey('staff-signout')));
      await tester.tap(find.byKey(const ValueKey('staff-signout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-signout')));
      await tester.pumpAndSettle();
      expect(find.text('No connection. Nothing was changed. Try again when you are online.'), findsOneWidget);
      await _show(tester, find.byKey(const ValueKey('signout-retry')));
      await tester.tap(find.byKey(const ValueKey('signout-retry')));
      await tester.pumpAndSettle();
      expect(server.signOuts.map((e) => e.key), ['key-1', 'key-1']);
      expect(find.byKey(const ValueKey('signout-message')), findsNothing);
    });

    testWidgets('on your own account the confirmation says this device stays signed in', (tester) async {
      final server = FakeStaffServer();
      await tester.pumpWidget(customersHost(const Locale('en'), _detail(server, row: 0)));
      await tester.pumpAndSettle();
      await _show(tester, find.byKey(const ValueKey('staff-signout')));
      await tester.tap(find.byKey(const ValueKey('staff-signout')));
      await tester.pumpAndSettle();
      expect(find.textContaining('This device stays signed in'), findsOneWidget);
    });

    testWidgets('without users.force_logout there is no sign-out button', (tester) async {
      await tester.pumpWidget(customersHost(
        const Locale('en'),
        _detail(FakeStaffServer(), slugs: const ['users.view', 'roles.view']),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff-signout')), findsNothing);
      expect(find.byKey(const ValueKey('staff-readonly-note')), findsOneWidget);
    });
  });
}
