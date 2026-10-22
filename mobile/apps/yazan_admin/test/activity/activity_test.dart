import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/activity/activity_page.dart';
import 'package:yazan_admin/src/activity/activity_repository.dart';
import 'package:yazan_admin/src/activity/activity_snapshot.dart';
import 'package:yazan_admin/src/dashboard/dashboard_format.dart';
import 'package:yazan_admin/src/more/more_registry.dart';
import 'package:yazan_admin/src/more/staff_permissions.dart';
import 'package:yazan_admin/src/storage/admin_stores.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../dashboard/fakes.dart' show dashboardHost, tallScreen;
import 'fakes.dart';

Widget _page(ActivityRepository repo, {Locale locale = const Locale('en')}) =>
    dashboardHost(locale, ActivityPage(repository: repo));

Finder _in(String key, Finder what) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: what, matchRoot: true);

/// Lets the fake answers (and sheet or menu animations) arrive. Spinners never settle, so no
/// pumpAndSettle.
Future<void> _load(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _forbidden = ApiError(status: 403, code: 'yazan_forbidden');

void main() {
  testWidgets('English: newest first, with object, actor and time kept left to right', (tester) async {
    tallScreen(tester);
    final server = FakeAuditServer();
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);

    expect(server.asked.single, {'page': '1', 'per_page': '50'});
    expect(_in('activity-entry-5-action', find.text(isolate('product.update'))), findsOneWidget);
    expect(_in('activity-entry-5-object', find.text(isolate('product #12'))), findsOneWidget);
    expect(_in('activity-entry-5-actor', find.text('By Sara ${isolate('#7')}')), findsOneWidget);
    expect(_in('activity-entry-5-time', find.text(isolate('2026-10-20 14:05'))), findsOneWidget);
    // A name that is an email address is isolated too, so its "@" and dots keep their order.
    expect(
      _in('activity-entry-3-actor', find.text('By ${isolate('owner@yazan.test')} ${isolate('#1')}')),
      findsOneWidget,
    );
    // No object id: the type alone. No actor: the app's own word, not the server's.
    expect(_in('activity-entry-3-object', find.text(isolate('auth'))), findsOneWidget);
    expect(_in('activity-entry-2-actor', find.text('By System')), findsOneWidget);
    // Destructive events stand out.
    expect(_in('activity-entry-4', find.byIcon(Icons.delete_outline)), findsOneWidget);

    expect(find.byKey(const ValueKey('activity-entry-1')), findsOneWidget);
    expect(find.text('5 of 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-load-more')), findsNothing);
    expect(find.textContaining('2026-10-20 14:05'), findsNWidgets(2)); // the entry and "as of"
    expect(find.byKey(const ValueKey('activity-asof')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-stale')), findsNothing);
  });

  testWidgets('read only: nothing to type in or switch, no purge', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(FakeAuditServer().repository()));
    await _load(tester);

    expect(find.byKey(const ValueKey('activity-readonly')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('urge'), findsNothing);
  });

  testWidgets('Arabic: translated wording, right to left, machine data still left to right', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(FakeAuditServer().repository(), locale: const Locale('ar')));
    await _load(tester);

    expect(find.text('للعرض فقط. لا يمكن تعديل إدخالات السجل من هنا.'), findsOneWidget);
    expect(_in('activity-entry-5-actor', find.text('بواسطة Sara ${isolate('#7')}')), findsOneWidget);
    expect(_in('activity-entry-2-actor', find.text('بواسطة النظام')), findsOneWidget);
    expect(_in('activity-entry-5-action', find.text(isolate('product.update'))), findsOneWidget);
    expect(find.text('5 من 5'), findsOneWidget);
    expect(find.text('كل الإجراءات'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byKey(const ValueKey('activity-entry-5')))),
      TextDirection.rtl,
    );
  });

  testWidgets('an entry opens a sheet with the details, IP and browser', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(FakeAuditServer().repository()));
    await _load(tester);

    await tester.tap(find.byKey(const ValueKey('activity-entry-5')));
    await _load(tester);

    expect(find.byKey(const ValueKey('activity-detail')), findsOneWidget);
    expect(_in('activity-change-regular_price', find.text(isolate('regular_price: 120.00'))), findsOneWidget);
    expect(_in('activity-change-stock', find.text(isolate('stock: {"old":3,"new":5}'))), findsOneWidget);
    expect(_in('activity-detail-ip', find.text(isolate('203.0.113.9'))), findsOneWidget);
    expect(_in('activity-detail-browser', find.text(isolate('YazanAdmin/0.1 (Android 14)'))), findsOneWidget);
    expect(_in('activity-detail-actor', find.text('Sara ${isolate('#7')}')), findsOneWidget);
    expect(_in('activity-detail-object', find.text(isolate('product #12'))), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-filter-actor')), findsOneWidget);
  });

  testWidgets('an entry with nothing recorded says so; the system cannot be filtered to', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(FakeAuditServer().repository()));
    await _load(tester);

    await tester.tap(find.byKey(const ValueKey('activity-entry-4')));
    await _load(tester);
    expect(find.byKey(const ValueKey('activity-detail-none')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-detail-ip')), findsNothing);
    Navigator.of(tester.element(find.byKey(const ValueKey('activity-detail')))).pop();
    await _load(tester);

    await tester.tap(find.byKey(const ValueKey('activity-entry-2')));
    await _load(tester);
    expect(_in('activity-change-sent', find.text(isolate('sent: 2'))), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-filter-actor')), findsNothing);
  });

  testWidgets('load more appends the next page until there is none', (tester) async {
    tallScreen(tester);
    final server = FakeAuditServer();
    await tester.pumpWidget(_page(server.repository(perPage: 2)));
    await _load(tester);

    expect(find.byKey(const ValueKey('activity-entry-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-entry-3')), findsNothing);
    expect(find.text('2 of 5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('activity-load-more')));
    await _load(tester);
    expect(find.byKey(const ValueKey('activity-entry-2')), findsOneWidget);
    expect(find.text('4 of 5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('activity-load-more')));
    await _load(tester);
    expect(find.byKey(const ValueKey('activity-entry-1')), findsOneWidget);
    expect(find.text('5 of 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-load-more')), findsNothing);
    expect([for (final q in server.asked) q['page']], ['1', '2', '3']);
  });

  testWidgets('a failed next page keeps what is shown and offers a retry', (tester) async {
    tallScreen(tester);
    final server = FakeAuditServer();
    await tester.pumpWidget(_page(server.repository(perPage: 2)));
    await _load(tester);

    server.goOffline();
    await tester.tap(find.byKey(const ValueKey('activity-load-more')));
    await _load(tester);
    expect(find.byKey(const ValueKey('activity-more-failed')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-entry-5')), findsOneWidget);
    expect(_in('activity-load-more', find.text('Try again')), findsOneWidget);

    server.failure = null;
    await tester.tap(find.byKey(const ValueKey('activity-load-more')));
    await _load(tester);
    expect(find.byKey(const ValueKey('activity-more-failed')), findsNothing);
    expect(find.byKey(const ValueKey('activity-entry-3')), findsOneWidget);
  });

  testWidgets('filtering by action asks the server, and clearing brings the whole log back', (tester) async {
    tallScreen(tester);
    final server = FakeAuditServer();
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);

    await tester.tap(find.byKey(const ValueKey('activity-filter-action')));
    await _load(tester);
    await tester.tap(find.text(isolate('product.delete')).last);
    await _load(tester);

    expect(server.asked.last, {'page': '1', 'per_page': '50', 'action_filter': 'product.delete'});
    expect(find.byKey(const ValueKey('activity-entry-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-entry-5')), findsNothing);
    expect(find.text('1 of 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('activity-clear-filters')));
    await _load(tester);
    expect(server.asked.last, {'page': '1', 'per_page': '50'});
    expect(find.byKey(const ValueKey('activity-entry-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-clear-filters')), findsNothing);
  });

  testWidgets('filtering by object type', (tester) async {
    tallScreen(tester);
    final server = FakeAuditServer();
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);

    await tester.tap(find.byKey(const ValueKey('activity-filter-type')));
    await _load(tester);
    await tester.tap(find.text(isolate('order')).last);
    await _load(tester);

    expect(server.asked.last['object_type'], 'order');
    expect(find.byKey(const ValueKey('activity-entry-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-entry-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-entry-5')), findsNothing);
  });

  testWidgets('"only this person" narrows to one actor, shown as a chip', (tester) async {
    tallScreen(tester);
    final server = FakeAuditServer();
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);

    await tester.tap(find.byKey(const ValueKey('activity-entry-5')));
    await _load(tester);
    await tester.tap(find.byKey(const ValueKey('activity-filter-actor')));
    await _load(tester);

    expect(server.asked.last['user_id'], '7');
    expect(find.byKey(const ValueKey('activity-detail')), findsNothing);
    expect(_in('activity-actor-filter', find.text('Only Sara')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-entry-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-entry-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-entry-4')), findsNothing);
  });

  testWidgets('a filter that matches nothing says so', (tester) async {
    tallScreen(tester);
    final server = FakeAuditServer();
    final repo = server.repository();
    await tester.pumpWidget(_page(repo));
    await _load(tester);

    server.rows = [for (final r in server.rows) if (r['action'] != 'auth.login') r];
    unawaited(repo.setFilter(const ActivityFilter(action: 'auth.login')));
    await _load(tester);
    expect(_in('activity-empty', find.text('Nothing matches these filters.')), findsOneWidget);
    // The vanished slug stays selectable, so the dropdown still shows the choice in force.
    expect(_in('activity-filter-action', find.text(isolate('auth.login'))), findsOneWidget);
  });

  testWidgets('no access when the server refuses', (tester) async {
    final server = FakeAuditServer()..failure = _forbidden;
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);

    expect(find.text('No access'), findsOneWidget);
    expect(find.textContaining('view the activity log'), findsOneWidget);
  });

  testWidgets('offline: the cached first page shows with the offline badge', (tester) async {
    tallScreen(tester);
    final store = MemoryFeedStore();
    await FakeAuditServer().repository(store: store).refresh();

    final server = FakeAuditServer()..goOffline();
    await tester.pumpWidget(_page(server.repository(store: store)));
    await _load(tester);

    expect(find.byKey(const ValueKey('activity-stale')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-entry-5')), findsOneWidget);
    expect(_in('activity-asof', find.textContaining('2026-10-20 14:05')), findsOneWidget);
    // The filter choices came from the cache too.
    expect(find.byKey(const ValueKey('activity-filter-action')), findsOneWidget);
  });

  testWidgets('offline with nothing cached: a retry hint', (tester) async {
    final server = FakeAuditServer()..goOffline();
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);

    expect(find.byKey(const ValueKey('activity-failed')), findsOneWidget);
    expect(find.textContaining('Could not load the activity log'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-stale')), findsOneWidget);
  });

  testWidgets('pull to refresh asks the server again', (tester) async {
    tallScreen(tester);
    final server = FakeAuditServer();
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);
    expect(server.asked, hasLength(1));

    server.rows = [
      auditRow(id: 6, userId: 7, user: 'Sara', action: 'coupon.create', date: '2026-10-20 15:00:00'),
      ...server.rows,
    ];
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(server.asked, hasLength(2));
    expect(find.byKey(const ValueKey('activity-entry-6')), findsOneWidget);
    expect(find.text('6 of 6'), findsOneWidget);
  });

  group('repository', () {
    test('only the unfiltered first page is kept on the phone', () async {
      final store = MemoryFeedStore();
      final server = FakeAuditServer();
      final repo = server.repository(store: store, perPage: 2);
      await repo.refresh();
      await repo.loadMore();
      expect(repo.snapshot!.entries, hasLength(4));

      var saved = ActivitySnapshot.fromJson((await store.readAll()).single);
      expect(saved.entries.map((e) => e.id), [5, 4]);

      await repo.setFilter(const ActivityFilter(action: 'order.create'));
      expect(repo.snapshot!.entries.map((e) => e.id), [1]);
      saved = ActivitySnapshot.fromJson((await store.readAll()).single);
      expect(saved.entries.map((e) => e.id), [5, 4]);
    });

    test('newer entries do not repeat rows on the next page', () async {
      final server = FakeAuditServer();
      final repo = server.repository(perPage: 2);
      await repo.refresh();
      server.rows = [
        auditRow(id: 6, userId: 7, user: 'Sara', action: 'coupon.create', date: '2026-10-20 15:00:00'),
        ...server.rows,
      ];
      await repo.loadMore(); // the server's page 2 is now 4, 3
      expect(repo.snapshot!.entries.map((e) => e.id), [5, 4, 3]);
      expect(repo.snapshot!.total, 6);
    });

    test('an answer for a filter no longer chosen is discarded', () async {
      final server = FakeAuditServer();
      final pending = <Completer<Map<String, dynamic>>>[];
      final repo = ActivityRepository(
        fetch: (q) {
          final c = Completer<Map<String, dynamic>>();
          pending.add(c);
          server.asked.add(q);
          return c.future;
        },
      );
      unawaited(repo.setFilter(const ActivityFilter(action: 'product.delete')));
      await Future<void>.delayed(Duration.zero);
      unawaited(repo.setFilter(const ActivityFilter(action: 'order.create')));
      await Future<void>.delayed(Duration.zero);
      expect(pending, hasLength(2));

      pending[1].complete(server.answer(server.asked[1]));
      await Future<void>.delayed(Duration.zero);
      pending[0].complete(server.answer(server.asked[0]));
      await Future<void>.delayed(Duration.zero);

      expect(repo.filter.action, 'order.create');
      expect(repo.snapshot!.entries.map((e) => e.action), ['order.create']);
      expect(repo.loading, isFalse);
    });

    test('a 403 drops the cached copy', () async {
      final store = MemoryFeedStore();
      final server = FakeAuditServer();
      final repo = server.repository(store: store);
      await repo.refresh();
      expect(await store.readAll(), hasLength(1));

      server.failure = _forbidden;
      await repo.refresh();
      expect(repo.noAccess, isTrue);
      expect(repo.snapshot, isNull);
      expect(repo.lastRefreshFailed, isFalse);
      expect(await store.readAll(), isEmpty);
    });

    test('the cached copy survives a restart unchanged', () async {
      final store = MemoryFeedStore();
      await FakeAuditServer().repository(store: store).refresh();

      final again = FakeAuditServer().repository(store: store);
      await again.ready;
      final first = again.snapshot!.entries.first;
      expect(first.action, 'product.update');
      expect(first.userId, 7);
      expect(first.changes['stock'], {'old': 3, 'new': 5});
      expect(first.ip, '203.0.113.9');
      expect(again.snapshot!.entries[1].changes, isEmpty);
      expect(again.facets.actions, contains('auth.login'));
      expect(again.facets.objectTypes, ['auth', 'order', 'product']);
    });
  });

  group('wording', () {
    late AppLocalizations l;
    setUpAll(() async => l = await AppLocalizations.delegate.load(const Locale('en')));

    test('recorded values read as text, structured ones as JSON', () {
      expect(changeValueText('12'), '12');
      expect(changeValueText(3), '3');
      expect(changeValueText(''), '-');
      expect(changeValueText(null), '-');
      expect(changeValueText(['a', 'b']), 'a\nb');
      expect(changeValueText([
        {'field': 'price', 'old': 1},
      ]), '{"field":"price","old":1}');
      expect(changeValueText({'old': 3}), '{"old":3}');
    });

    test('times, objects, tones and actors', () {
      expect(shortLogTime('2026-10-20 14:05:33'), '2026-10-20 14:05');
      expect(shortLogTime('yesterday'), 'yesterday');
      expect(actionTone('product.delete'), ActionTone.danger);
      expect(actionTone('audit.purge'), ActionTone.danger);
      expect(actionTone('order.refund_failed'), ActionTone.danger);
      expect(actionTone('product.create'), ActionTone.ok);
      expect(actionTone('order.refund'), ActionTone.warn);
      expect(actionTone('auth.login'), ActionTone.muted);
      expect(actionTone('product.update'), ActionTone.info);

      final entry = AuditEntry.fromJson(auditLog().first);
      expect(objectText(entry), 'product #12');
      expect(actorText(l, entry), 'Sara ${isolate('#7')}');
      final nameless = AuditEntry.fromJson(
        auditRow(id: 9, userId: 4, user: '#4', action: 'x.y', date: ''),
      );
      expect(actorText(l, nameless), isolate('#4'));
    });

    test('PHP empty objects and odd shapes parse without throwing', () {
      final s = ActivitySnapshot.fromServer({
        'items': [
          {'id': '3', 'changes': ['first', 'second']},
          'not a row',
        ],
        'facets': <dynamic>[],
      }, fetchedAt: DateTime(2026));
      expect(s.entries.single.id, 3);
      expect(s.entries.single.changes, {'0': 'first', '1': 'second'});
      expect(s.facets.isEmpty, isTrue);
      expect(s.hasMore, isFalse);
    });
  });

  group('More tab', () {
    test('the registry has the Activity log, shown with audit.view', () {
      final entry = moreEntries.firstWhere((e) => e.key == 'activity');
      expect(entry.permission, 'audit.view');
      expect(entry.visibleWith(StaffPermissions.of(['audit.view'])), isTrue);
      expect(entry.visibleWith(StaffPermissions.of(['orders.view'])), isFalse);
      expect(entry.visibleWith(const StaffPermissions.unknown()), isTrue);
    });

    test('the feed has its own name', () {
      expect(AdminFeeds.activity, 'activity');
      expect(
        {AdminFeeds.coupons, AdminFeeds.shippingTax, AdminFeeds.reports, AdminFeeds.inventory},
        isNot(contains(AdminFeeds.activity)),
      );
    });
  });
}
