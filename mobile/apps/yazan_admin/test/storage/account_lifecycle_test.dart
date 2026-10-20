import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/storage/account_id_store.dart';
import 'package:yazan_admin/src/storage/account_lifecycle.dart';
import 'package:yazan_admin/src/storage/admin_stores.dart';
import 'package:yazan_domain/yazan_domain.dart';

import 'fakes.dart';

void main() {
  late FakeAccountStorage storage;
  late MemoryAccountIdStore ids;
  late FakeMe me;
  late AccountLifecycle life;

  AccountLifecycle make({String namespace = 'shop.test'}) =>
      AccountLifecycle(storage: storage, ids: ids, loadMe: me.call, namespace: namespace);

  setUp(() {
    storage = FakeAccountStorage();
    ids = MemoryAccountIdStore();
    me = FakeMe();
    life = make();
  });

  group('forNewSession', () {
    test('keys the data by the staff id from /me, namespaced by server, and remembers it', () async {
      final s = await life.forNewSession();
      expect(s.durable, isTrue);
      expect(s.accountId, 'shop.test:7');
      expect(await ids.read(), 'shop.test:7');
    });

    test('an empty namespace gives the bare id; a string id is accepted', () async {
      me.answer = {'id': '12'};
      final s = await make(namespace: '').forNewSession();
      expect(s.accountId, '12');
    });

    test('a different staff member than the remembered one wipes the old data first', () async {
      await storage.seed('shop.test:3');
      await ids.write('shop.test:3');

      final s = await life.forNewSession();

      expect(s.accountId, 'shop.test:7');
      expect(storage.wiped, ['shop.test:3']);
      expect(storage.rowCount('shop.test:3'), 0);
      expect(await storage.outbox.all('shop.test:3'), isEmpty);
      expect(await ids.read(), 'shop.test:7');
    });

    test('when /me cannot be read it falls back to memory and wipes what it cannot trust', () async {
      await storage.seed('shop.test:3');
      await ids.write('shop.test:3');
      me.error = Exception('offline');

      final s = await life.forNewSession();

      expect(s.durable, isFalse);
      expect(storage.rowCount('shop.test:3'), 0);
      expect(await ids.read(), isNull);
    });

    test('an answer without a usable id is treated like no answer', () async {
      final answers = <Map<String, dynamic>>[{}, {'id': 0}, {'id': 'abc'}];
      for (final bad in answers) {
        me.answer = bad;
        expect((await life.forNewSession()).durable, isFalse, reason: '$bad');
      }
    });
  });

  group('forExistingSession', () {
    test('uses the remembered account without asking the server', () async {
      await ids.write('shop.test:7');
      final s = await life.forExistingSession();
      expect(s.accountId, 'shop.test:7');
      expect(s.durable, isTrue);
      expect(me.calls, 0);
    });

    test('a session from before durable storage asks /me once and remembers the answer', () async {
      final s = await life.forExistingSession();
      expect(s.accountId, 'shop.test:7');
      expect(await ids.read(), 'shop.test:7');
      expect(me.calls, 1);
    });

    test('offline with no remembered account runs in memory', () async {
      me.error = Exception('offline');
      expect((await life.forExistingSession()).durable, isFalse);
      expect(await ids.read(), isNull);
    });
  });

  group('forget (sign-out, revoked session, lost access)', () {
    test('wipes the current account and any remembered one, then forgets the id', () async {
      await storage.seed('shop.test:7');
      await storage.seed('shop.test:3');
      await ids.write('shop.test:3');

      final ok = await life.forget(DurableAdminStores(storage, 'shop.test:7'));

      expect(ok, isTrue);
      expect(storage.rowCount('shop.test:7'), 0);
      expect(storage.rowCount('shop.test:3'), 0);
      expect(await storage.outbox.all('shop.test:7'), isEmpty);
      expect(await storage.outbox.all('shop.test:3'), isEmpty);
      expect(await ids.read(), isNull);
    });

    test('a failed wipe keeps the id so the next start removes the data', () async {
      await storage.seed('shop.test:7');
      await ids.write('shop.test:7');
      storage.failWipe = true;

      final ok = await life.forget(DurableAdminStores(storage, 'shop.test:7'));

      expect(ok, isFalse);
      expect(await ids.read(), 'shop.test:7');
      expect(storage.rowCount('shop.test:7'), 2);

      storage.failWipe = false;
      expect(await life.forget(null), isTrue);
      expect(storage.rowCount('shop.test:7'), 0);
      expect(await ids.read(), isNull);
    });

    test('with nobody signed in and nothing remembered it does nothing', () async {
      await storage.seed('shop.test:7');
      expect(await life.forget(null), isTrue);
      expect(storage.wiped, isEmpty);
      expect(storage.rowCount('shop.test:7'), 2);
    });
  });

  group('verify', () {
    late DurableAdminStores current;

    setUp(() async {
      current = DurableAdminStores(storage, 'shop.test:7');
      await ids.write('shop.test:7');
      await storage.seed('shop.test:7');
    });

    test('the same account changes nothing', () async {
      final r = await life.verify(current);
      expect(r.kind, AccountCheckKind.same);
      expect(storage.wiped, isEmpty);
    });

    test('a different account wipes the cache and returns stores for the new one', () async {
      me.answer = {'id': 9};
      final r = await life.verify(current);
      expect(r.kind, AccountCheckKind.switched);
      expect(r.stores!.accountId, 'shop.test:9');
      expect(storage.rowCount('shop.test:7'), 0);
      expect(await storage.outbox.all('shop.test:7'), isEmpty);
      expect(await ids.read(), 'shop.test:9');
    });

    test('a refusal (403) means the account lost its access: everything is wiped', () async {
      me.error = forbidden;
      final r = await life.verify(current);
      expect(r.kind, AccountCheckKind.accessLost);
      expect(storage.rowCount('shop.test:7'), 0);
      expect(await storage.outbox.all('shop.test:7'), isEmpty);
      expect(await ids.read(), isNull);
    });

    test('offline or an expired token does not wipe anything', () async {
      me.error = Exception('offline');
      expect((await life.verify(current)).kind, AccountCheckKind.unknown);
      me.error = const ApiError(status: 401, code: 'yazan_mobile_bad_token');
      expect((await life.verify(current)).kind, AccountCheckKind.unknown);
      expect(storage.rowCount('shop.test:7'), 2);
    });

    test('memory stores are never swapped mid-session', () async {
      final r = await life.verify(MemoryAdminStores());
      expect(r.kind, AccountCheckKind.unknown);
    });
  });
}
