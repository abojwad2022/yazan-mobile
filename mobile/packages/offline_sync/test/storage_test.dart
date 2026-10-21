import 'package:test/test.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'support/fake_sql_database.dart';

OutboxOp op(
  String id, {
  String account = 'u1',
  QueueableKind kind = QueueableKind.orderNote,
  Map<String, dynamic>? body,
  String? entity,
  String? baseVersion,
}) =>
    OutboxOp(
      id: id,
      accountId: account,
      kind: kind,
      method: 'POST',
      path: '/yazan/v1/orders/5/notes',
      idempotencyKey: 'key-$id-0000',
      body: body ?? {'note': id},
      entity: entity,
      baseVersion: baseVersion,
    );

DeltaPage page(List<Map<String, dynamic>> items, String cursor,
        {bool more = false, bool initial = false}) =>
    DeltaPage(items: items, cursor: cursor, hasMore: more, initial: initial);

void main() {
  final t0 = DateTime.utc(2026, 1, 1);
  late FakeSqlDatabase db;
  late SqlOutboxStore outbox;
  var now = t0;

  setUp(() {
    db = FakeSqlDatabase();
    outbox = SqlOutboxStore(db, clock: () => now);
    now = t0;
  });

  group('SqlOutboxStore', () {
    test('keeps every field, including a nested Arabic field-level patch', () async {
      final patch = {
        'title': {'ar': 'خاتم عقيق يماني', 'en': null},
        'tags': ['a', 'b'],
        'stock': 3,
      };
      final original = op(
        'a',
        kind: QueueableKind.productText,
        body: patch,
        entity: 'product:12',
        baseVersion: 'etag-7',
      );
      await outbox.add(original);

      final back = (await outbox.all('u1')).single;
      expect(back, isNot(same(original)));
      expect(back.id, 'a');
      expect(back.accountId, 'u1');
      expect(back.kind, QueueableKind.productText);
      expect(back.entity, 'product:12');
      expect(back.method, 'POST');
      expect(back.path, '/yazan/v1/orders/5/notes');
      expect(back.idempotencyKey, 'key-a-0000');
      expect(back.baseVersion, 'etag-7');
      expect(back.body, patch);
      expect(back.state, OpState.pending);
      expect(back.attempts, 0);
      expect(back.nextAttemptAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      expect(back.lastError, isNull);
      expect(back.serverVersion, isNull);
    });

    test('a null body and null entity stay null', () async {
      await outbox.add(OutboxOp(
        id: 'a',
        accountId: 'u1',
        kind: QueueableKind.wishlist,
        method: 'DELETE',
        path: '/x',
        idempotencyKey: 'key-a-0000',
      ));
      final back = (await outbox.all('u1')).single;
      expect(back.body, isNull);
      expect(back.entity, isNull);
      expect(back.baseVersion, isNull);
    });

    test('queue order is insertion order, stable across removals', () async {
      await outbox.add(op('c'));
      await outbox.add(op('a'));
      await outbox.add(op('b'));
      expect([for (final o in await outbox.due('u1', t0)) o.id], ['c', 'a', 'b']);

      await outbox.remove('a');
      await outbox.add(op('d'));
      expect([for (final o in await outbox.all('u1')) o.id], ['c', 'b', 'd']);
    });

    test('order does not depend on next-attempt times', () async {
      final overdue = op('late')..nextAttemptAt = t0.subtract(const Duration(days: 1));
      await outbox.add(op('first'));
      await outbox.add(overdue);
      expect([for (final o in await outbox.due('u1', t0)) o.id], ['first', 'late']);
    });

    test('due returns only pending ops that are due, for that account', () async {
      final later = op('later')..nextAttemptAt = t0.add(const Duration(minutes: 5));
      await outbox.add(op('now'));
      await outbox.add(later);
      await outbox.add(op('other', account: 'u2'));
      final conflict = op('conflict')..state = OpState.conflict;
      await outbox.add(conflict);

      expect([for (final o in await outbox.due('u1', t0)) o.id], ['now']);
      final inSix = t0.add(const Duration(minutes: 6));
      expect([for (final o in await outbox.due('u1', inSix)) o.id], ['now', 'later']);
      expect([for (final o in await outbox.due('u2', t0)) o.id], ['other']);
    });

    test('adding the same id twice keeps one op', () async {
      await outbox.add(op('a'));
      await outbox.add(op('a'));
      expect(await outbox.all('u1'), hasLength(1));
    });

    test('update persists state, attempts, schedule and error but not identity', () async {
      await outbox.add(op('a'));
      final o = (await outbox.all('u1')).single
        ..state = OpState.conflict
        ..attempts = 3
        ..nextAttemptAt = t0.add(const Duration(hours: 1))
        ..lastError = 'yazan_precondition_failed'
        ..serverVersion = 'v9';
      await outbox.update(o);

      final back = (await outbox.all('u1')).single;
      expect(back.state, OpState.conflict);
      expect(back.attempts, 3);
      expect(back.nextAttemptAt, t0.add(const Duration(hours: 1)));
      expect(back.lastError, 'yazan_precondition_failed');
      expect(back.serverVersion, 'v9');
      expect(back.idempotencyKey, 'key-a-0000');
      expect(back.body, {'note': 'a'});
    });

    test('a row this version cannot read is skipped, not fatal', () async {
      await outbox.add(op('good'));
      db.outboxRows.add({...db.outboxRows.first, 'id': 'bad', 'kind': 'from_the_future', 'seq': 99});
      db.outboxRows.add({...db.outboxRows.first, 'id': 'bad2', 'body': '{not json', 'seq': 100});
      expect([for (final o in await outbox.all('u1')) o.id], ['good']);
    });

    test('clearAccount removes only that account', () async {
      await outbox.add(op('a'));
      await outbox.add(op('b', account: 'u2'));
      await outbox.clearAccount('u1');
      expect(await outbox.all('u1'), isEmpty);
      expect(await outbox.all('u2'), hasLength(1));
    });

    test('ops left in sending by a killed process are sent again', () async {
      await outbox.add(op('a'));
      final o = (await outbox.due('u1', t0)).single..state = OpState.sending;
      await outbox.update(o);
      expect(await outbox.due('u1', t0), isEmpty); // the process died here

      await outbox.recoverInterrupted();
      final back = (await outbox.due('u1', t0)).single;
      expect(back.id, 'a');
      expect(back.idempotencyKey, 'key-a-0000');
      expect(back.attempts, 0);
    });

    test('recoverInterrupted leaves conflict and failed ops alone', () async {
      await outbox.add(op('a')..state = OpState.conflict);
      await outbox.add(op('b')..state = OpState.failed);
      await outbox.recoverInterrupted();
      final states = {for (final o in await outbox.all('u1')) o.id: o.state};
      expect(states, {'a': OpState.conflict, 'b': OpState.failed});
    });
  });

  group('SyncEngine over SqlOutboxStore (state transitions survive a reload)', () {
    SyncEngine engine(OpSender send) => SyncEngine(
          store: outbox,
          send: send,
          clock: () => now,
          jitter: () => 1.0,
        );

    test('503: backed off in the database, same key on the retry, removed on success', () async {
      await outbox.add(op('a'));
      final keys = <String>[];
      var n = 0;
      final e = engine((o) async {
        keys.add(o.idempotencyKey);
        if (++n == 1) throw const ApiError(status: 503, code: 'unavailable');
      });

      final r1 = await e.run('u1');
      expect(r1.retryLater, 1);
      final stored = (await outbox.all('u1')).single;
      expect(stored.state, OpState.pending);
      expect(stored.attempts, 1);
      expect(stored.lastError, 'unavailable');
      expect(stored.nextAttemptAt, t0.add(const Duration(seconds: 10)));
      expect(await outbox.due('u1', t0), isEmpty);

      await e.run('u1'); // not due yet
      expect(n, 1);

      now = t0.add(const Duration(seconds: 11));
      final r2 = await e.run('u1');
      expect(r2.sent, 1);
      expect(keys, ['key-a-0000', 'key-a-0000']);
      expect(await outbox.all('u1'), isEmpty);
    });

    test('412: stored as conflict with the server version and never due again', () async {
      await outbox.add(op('a', baseVersion: 'v1'));
      final e = engine((_) async =>
          throw const ApiError(status: 412, code: 'yazan_precondition_failed', current: 'v9'));
      final r = await e.run('u1');
      expect(r.conflicts, 1);

      final stored = (await outbox.all('u1')).single;
      expect(stored.state, OpState.conflict);
      expect(stored.serverVersion, 'v9');
      expect(stored.baseVersion, 'v1');
      expect(await outbox.due('u1', t0.add(const Duration(days: 30))), isEmpty);
    });

    test('422: stored as failed, kept for the sync centre', () async {
      await outbox.add(op('a'));
      final r = await engine((_) async =>
          throw const ApiError(status: 422, code: 'yazan_idempotency_mismatch')).run('u1');
      expect(r.failed, 1);
      final stored = (await outbox.all('u1')).single;
      expect(stored.state, OpState.failed);
      expect(stored.lastError, 'yazan_idempotency_mismatch');
      expect(await outbox.due('u1', t0.add(const Duration(days: 30))), isEmpty);
    });

    test('no network: stored back as pending with no attempt spent', () async {
      await outbox.add(op('a'));
      await outbox.add(op('b'));
      final r = await engine((_) async => throw Exception('socket')).run('u1');
      expect(r.offline, isTrue);
      final all = await outbox.all('u1');
      expect(all.map((o) => o.state), everyElement(OpState.pending));
      expect(all.map((o) => o.attempts), everyElement(0));
    });

    test('dead session: queue kept, nothing else sent', () async {
      await outbox.add(op('a'));
      await outbox.add(op('b'));
      var calls = 0;
      final r = await engine((_) async {
        calls++;
        throw const ApiError(status: 401, code: 'yazan_mobile_bad_refresh');
      }).run('u1');
      expect(r.signedOut, isTrue);
      expect(calls, 1);
      expect(await outbox.all('u1'), hasLength(2));
      expect((await outbox.due('u1', t0)).map((o) => o.id), ['a', 'b']);
    });

    test('sends oldest first across accounts without mixing them', () async {
      await outbox.add(op('a'));
      await outbox.add(op('x', account: 'u2'));
      await outbox.add(op('b'));
      final sent = <String>[];
      await engine((o) async => sent.add(o.id)).run('u1');
      expect(sent, ['a', 'b']);
      expect((await outbox.all('u2')).map((o) => o.id), ['x']);
    });
  });

  group('SqlFeedStore', () {
    SqlFeedStore feed(String account, String name) => SqlFeedStore(
          db,
          accountId: account,
          feed: name,
          clock: () => now,
        );

    test('empty store: no cursor, no rows', () async {
      final f = feed('u1', 'orders');
      expect(await f.readCursor(), '');
      expect(await f.readAll(), isEmpty);
    });

    test('apply stores rows and the cursor; readAll is ordered by id', () async {
      final f = feed('u1', 'orders');
      await f.apply(
        upserts: [
          {'id': 3, 'name': 'ثلاثة'},
          {'id': 1, 'name': 'one'},
        ],
        deletedIds: const [],
        cursor: 'c1',
        initial: true,
      );
      expect(await f.readCursor(), 'c1');
      expect(await f.readAll(), [
        {'id': 1, 'name': 'one'},
        {'id': 3, 'name': 'ثلاثة'},
      ]);
    });

    test('upsert replaces, delete removes, an initial page replaces everything', () async {
      final f = feed('u1', 'orders');
      await f.apply(
        upserts: [{'id': 1, 'v': 1}, {'id': 2, 'v': 1}],
        deletedIds: const [],
        cursor: 'c1',
        initial: true,
      );
      await f.apply(
        upserts: [{'id': 2, 'v': 2}, {'id': 3, 'v': 1}],
        deletedIds: const [1],
        cursor: 'c2',
        initial: false,
      );
      expect(await f.readAll(), [{'id': 2, 'v': 2}, {'id': 3, 'v': 1}]);
      expect(await f.readCursor(), 'c2');

      await f.apply(
        upserts: [{'id': 9, 'v': 1}],
        deletedIds: const [],
        cursor: 'fresh',
        initial: true,
      );
      expect(await f.readAll(), [{'id': 9, 'v': 1}]);
    });

    test('accounts and feeds are isolated from each other', () async {
      final a = feed('u1', 'orders');
      final b = feed('u2', 'orders');
      final c = feed('u1', 'products');
      await a.apply(upserts: [{'id': 1, 'o': 'a'}], deletedIds: const [], cursor: 'ca', initial: true);
      await b.apply(upserts: [{'id': 1, 'o': 'b'}], deletedIds: const [], cursor: 'cb', initial: true);
      await c.apply(upserts: [{'id': 1, 'o': 'c'}], deletedIds: const [], cursor: 'cc', initial: true);

      // An initial page for one must not clear the others.
      await a.apply(upserts: const [], deletedIds: const [], cursor: 'ca2', initial: true);
      expect(await a.readAll(), isEmpty);
      expect(await b.readAll(), [{'id': 1, 'o': 'b'}]);
      expect(await c.readAll(), [{'id': 1, 'o': 'c'}]);
      expect(await b.readCursor(), 'cb');
      expect(await c.readCursor(), 'cc');
    });

    test('apply is atomic: a failure mid-page keeps the old rows AND the old cursor', () async {
      final f = feed('u1', 'orders');
      await f.apply(
        upserts: [{'id': 1}, {'id': 2}],
        deletedIds: const [],
        cursor: 'c1',
        initial: true,
      );

      db.failOn.add(FeedSql.upsertCursor);
      await expectLater(
        f.apply(upserts: [{'id': 3}], deletedIds: const [1], cursor: 'c2', initial: false),
        throwsA(isA<StateError>()),
      );
      db.failOn.clear();

      expect(await f.readCursor(), 'c1');
      expect((await f.readAll()).map((r) => r['id']), [1, 2]);
    });

    test('pullFeed resumes from the cursor that survived a restart', () async {
      final first = feed('u1', 'orders');
      final pages = {
        '': page([{'id': 1}, {'id': 2}], 'c1', more: true, initial: true),
        'c1': page([{'id': 2, 'deleted': true}, {'id': 3}], 'c2'),
      };
      // Interrupted after page one.
      await pullFeed(fetch: (c) async => pages[c]!, store: first, maxPages: 1);
      expect(await first.readCursor(), 'c1');

      // "Restart": a new store object over the same database.
      final reopened = feed('u1', 'orders');
      final asked = <String>[];
      await pullFeed(
        fetch: (c) async {
          asked.add(c);
          return pages[c]!;
        },
        store: reopened,
      );
      expect(asked, ['c1']);
      expect((await reopened.readAll()).map((r) => r['id']), [1, 3]);
      expect(await reopened.readCursor(), 'c2');
    });
  });

  group('feed metadata', () {
    SqlFeedStore feed(String account, String name) =>
        SqlFeedStore(db, accountId: account, feed: name, clock: () => now);

    test('round-trips, overwrites, removes with null, and is namespaced', () async {
      final f = feed('u1', 'orders');
      expect(await f.readMeta('synced_at'), isNull);
      await f.writeMeta('synced_at', '1');
      await f.writeMeta('synced_at', '2');
      expect(await f.readMeta('synced_at'), '2');
      expect(await feed('u1', 'products').readMeta('synced_at'), isNull);
      expect(await feed('u2', 'orders').readMeta('synced_at'), isNull);
      await f.writeMeta('synced_at', null);
      expect(await f.readMeta('synced_at'), isNull);
    });

    test('is independent of rows and cursor (apply with initial does not clear it)', () async {
      final f = feed('u1', 'orders');
      await f.writeMeta('k', 'v');
      await f.apply(upserts: [{'id': 1}], deletedIds: const [], cursor: 'c', initial: true);
      expect(await f.readMeta('k'), 'v');
    });

    test('the FeedMeta extension reaches SqlFeedStore through the FeedStore type', () async {
      final FeedStore f = feed('u1', 'orders');
      expect(f.supportsMeta, isTrue);
      await f.writeMeta('k', 'v');
      expect(await f.readMeta('k'), 'v');
    });
  });

  group('wipe', () {
    late YazanStorage storage;

    setUp(() async {
      storage = YazanStorage(db, clock: () => now);
      for (final account in ['u1', 'u2']) {
        await storage.outbox.add(op('op-$account', account: account));
        for (final name in ['orders', 'products']) {
          await storage.feed(account, name).apply(
            upserts: [{'id': 1, 'who': account}],
            deletedIds: const [],
            cursor: 'cur-$account-$name',
            initial: true,
          );
        }
      }
    });

    test('removes the queue, rows and cursors of that account only', () async {
      await storage.wipe('u1');

      expect(await storage.outbox.all('u1'), isEmpty);
      for (final name in ['orders', 'products']) {
        expect(await storage.feed('u1', name).readAll(), isEmpty);
        expect(await storage.feed('u1', name).readCursor(), '');
        expect(await storage.feed('u2', name).readAll(), [{'id': 1, 'who': 'u2'}]);
        expect(await storage.feed('u2', name).readCursor(), 'cur-u2-$name');
      }
      expect((await storage.outbox.all('u2')).map((o) => o.id), ['op-u2']);
      expect(db.feedRowCount, 2);
      expect(db.cursorCount, 2);
    });

    test('also clears the feed metadata of that account only', () async {
      await storage.feed('u1', 'orders').writeMeta('synced_at', '100');
      await storage.feed('u2', 'orders').writeMeta('synced_at', '200');
      await storage.wipe('u1');
      expect(await storage.feed('u1', 'orders').readMeta('synced_at'), isNull);
      expect(await storage.feed('u2', 'orders').readMeta('synced_at'), '200');
      expect(db.metaCount, 1);
    });

    test('is atomic: a failure part-way deletes nothing', () async {
      db.failOn.add(FeedSql.deleteAccountCursors);
      await expectLater(storage.wipe('u1'), throwsA(isA<StateError>()));
      db.failOn.clear();

      expect(await storage.outbox.all('u1'), hasLength(1));
      expect(await storage.feed('u1', 'orders').readAll(), hasLength(1));
      expect(await storage.feed('u1', 'orders').readCursor(), 'cur-u1-orders');
    });

    test('an in-flight update after the wipe does not bring the op back', () async {
      final inFlight = (await storage.outbox.due('u1', t0)).single..state = OpState.sending;
      await storage.wipe('u1');
      await storage.outbox.update(inFlight);
      expect(await storage.outbox.all('u1'), isEmpty);
    });

    test('wiping an unknown account is a no-op', () async {
      await storage.wipe('nobody');
      expect(await storage.outbox.all('u1'), hasLength(1));
      expect(db.feedRowCount, 4);
    });
  });

  group('SchemaMigrator', () {
    test('numbers must run 1..n without gaps', () {
      expect(() => SchemaMigrator([const SchemaMigration(2, [])]), throwsArgumentError);
      expect(
        () => SchemaMigrator([const SchemaMigration(1, []), const SchemaMigration(3, [])]),
        throwsArgumentError,
      );
    });

    test('a new database gets every table and the latest version; running again does nothing', () async {
      final m = SchemaMigrator(yazanSchemaMigrations);
      expect(await m.migrate(db), 2);
      expect(db.version, 2);
      expect(
        db.log,
        containsAll([
          OutboxSql.create,
          OutboxSql.createIndex,
          FeedSql.createRows,
          FeedSql.createCursors,
          FeedSql.createMeta,
        ]),
      );
      db.log.clear();
      await m.migrate(db);
      expect(db.log, isEmpty);
    });

    test('a v1 database upgrades to v2 by creating only the metadata table', () async {
      await SchemaMigrator(yazanSchemaMigrations.sublist(0, 1)).migrate(db);
      expect(db.version, 1);
      db.log.clear();
      expect(await SchemaMigrator(yazanSchemaMigrations).migrate(db), 2);
      expect(db.log, [FeedSql.createMeta]);
    });

    test('an existing database runs only the newer steps, including the Dart hook', () async {
      await SchemaMigrator(yazanSchemaMigrations).migrate(db);
      db.log.clear();

      var hooked = 0;
      final v2 = SchemaMigrator([
        ...yazanSchemaMigrations,
        SchemaMigration(
          3,
          ['ALTER TABLE outbox_ops ADD COLUMN note TEXT'],
          hook: (txn) async {
            hooked++;
            await txn.execute('UPDATE outbox_ops SET note = ?', ['x']);
          },
        ),
      ]);
      expect(await v2.migrate(db), 3);
      expect(db.version, 3);
      expect(hooked, 1);
      expect(db.log, ['ALTER TABLE outbox_ops ADD COLUMN note TEXT', 'UPDATE outbox_ops SET note = ?']);

      db.log.clear();
      await v2.migrate(db);
      expect(hooked, 1);
      expect(db.log, isEmpty);
    });

    test('a step that fails is rolled back with its version bump and retried next time', () async {
      await SchemaMigrator(yazanSchemaMigrations).migrate(db);
      const hookSql = 'UPDATE outbox_ops SET note = 1';
      final v2 = SchemaMigrator([
        ...yazanSchemaMigrations,
        SchemaMigration(
          3,
          ['ALTER TABLE outbox_ops ADD COLUMN note TEXT'],
          hook: (txn) => txn.execute(hookSql),
        ),
      ]);

      db.failOn.add(hookSql);
      await expectLater(v2.migrate(db), throwsA(isA<StateError>()));
      expect(db.version, 2);

      db.failOn.clear();
      expect(await v2.migrate(db), 3);
      expect(db.version, 3);
    });

    test('a database from a newer app is refused and left alone', () async {
      await outbox.add(op('a'));
      db.version = 9;
      await expectLater(
        SchemaMigrator(yazanSchemaMigrations).migrate(db),
        throwsA(isA<StorageSchemaException>()),
      );
      expect(db.version, 9);
      expect(db.outboxRows, hasLength(1));
    });
  });

  group('DatabaseKeyManager', () {
    test('creates a 256-bit hex key once and reuses it', () async {
      final secrets = MapSecretStore();
      final keys = DatabaseKeyManager(secrets);
      final k1 = await keys.obtain();
      expect(k1, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await keys.obtain(), k1);
      expect(await DatabaseKeyManager(secrets).obtain(), k1);
      expect(secrets.values.values.single, k1);
    });

    test('regenerate replaces the stored key', () async {
      final secrets = MapSecretStore();
      final keys = DatabaseKeyManager(secrets);
      final k1 = await keys.obtain();
      final k2 = await keys.regenerate();
      expect(k2, isNot(k1));
      expect(await keys.obtain(), k2);
    });

    test('a truncated stored value is not trusted', () async {
      final secrets = MapSecretStore()..values['yazan.db.key.v1'] = 'short';
      final key = await DatabaseKeyManager(secrets).obtain();
      expect(key, hasLength(64));
    });
  });

  group('YazanStorage.open', () {
    late FakeDatabaseOpener opener;
    late MapSecretStore secrets;

    Future<YazanStorage> open() =>
        YazanStorage.open(opener: opener, secrets: secrets, clock: () => now);

    setUp(() {
      opener = FakeDatabaseOpener();
      secrets = MapSecretStore();
    });

    test('first launch creates the schema and a key', () async {
      final s = await open();
      expect(s.recreated, isFalse);
      expect(opener.file!.version, 2);
      expect(secrets.values, hasLength(1));
    });

    test('data written before a restart is there after it', () async {
      var s = await open();
      await s.outbox.add(op('a', body: {'note': 'written offline'}));
      await s.feed('u1', 'orders').apply(
        upserts: [{'id': 7, 'total': '10.00'}],
        deletedIds: const [],
        cursor: 'c9',
        initial: true,
      );
      await s.close();
      expect(opener.file!.closed, isTrue);

      s = await open();
      expect(s.recreated, isFalse);
      expect(opener.deletes, 0);
      expect((await s.outbox.all('u1')).single.body, {'note': 'written offline'});
      expect(await s.feed('u1', 'orders').readCursor(), 'c9');
      expect(await s.feed('u1', 'orders').readAll(), [{'id': 7, 'total': '10.00'}]);
    });

    test('an op that was mid-send when the app died is pending again', () async {
      var s = await open();
      await s.outbox.add(op('a'));
      final o = (await s.outbox.due('u1', t0)).single..state = OpState.sending;
      await s.outbox.update(o);
      await s.close();

      s = await open();
      expect((await s.outbox.due('u1', t0)).map((o) => o.id), ['a']);
    });

    test('a lost key makes the file unreadable: it is replaced and the caller is told', () async {
      var s = await open();
      await s.outbox.add(op('a'));
      await s.close();
      final oldKey = secrets.values.values.single;

      secrets.values.clear(); // e.g. restored from a backup without the Keystore
      s = await open();
      expect(s.recreated, isTrue);
      expect(opener.deletes, 1);
      expect(await s.outbox.all('u1'), isEmpty);
      expect(secrets.values.values.single, isNot(oldKey));
      expect(opener.file!.version, 2);

      await s.close();
      s = await open();
      expect(s.recreated, isFalse);
      expect(opener.deletes, 1);
    });

    test('a database from a newer app is neither opened nor deleted', () async {
      final s = await open();
      await s.outbox.add(op('a'));
      await s.close();
      opener.file!.version = 9;

      await expectLater(open(), throwsA(isA<StorageSchemaException>()));
      expect(opener.deletes, 0);
      expect(opener.file!.closed, isTrue);
      expect(opener.file!.outboxRows, hasLength(1));
    });

    test('a failure other than an unreadable file is not treated as corruption', () async {
      final s = await open();
      await s.outbox.add(op('a'));
      await s.close();
      opener.file!.version = 0;
      opener.file!.failOn.add(OutboxSql.recoverInterrupted);

      await expectLater(open(), throwsA(isA<StateError>()));
      expect(opener.deletes, 0);
      expect(opener.file!.closed, isTrue);
      expect(opener.file!.outboxRows, hasLength(1));
    });
  });
}
