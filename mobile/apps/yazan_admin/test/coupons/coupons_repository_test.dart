import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/coupons/coupon_summary.dart';
import 'package:yazan_admin/src/coupons/coupons_repository.dart';
import 'package:yazan_admin/src/storage/admin_stores.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../customers/fakes.dart' show customersMe;
import '../storage/fakes.dart';
import 'fakes.dart';

void main() {
  test('CouponSummary reads a row, 0 meaning no limit', () {
    final c = CouponSummary.fromJson(couponRows[1]);
    expect(c.code, 'OLD5');
    expect(c.expired, isTrue);
    expect(c.usageLimit, isNull);
    expect(c.amountText, r'$5.00');
    expect(CouponSummary.fromJson(couponRows[0]).usageLimit, 10);
    expect(CouponSummary.fromJson(const {}).code, '');
  });

  test('refresh reads every page and the list is newest first', () async {
    final pages = <int>[];
    final repo = CouponsRepository(fetch: (p) async {
      pages.add(p);
      return p == 1
          ? couponsPage([couponRows[0], couponRows[1]], totalPages: 2)
          : couponsPage([couponRows[2]], totalPages: 2);
    });
    await repo.refresh();
    expect(pages, [1, 2]);
    expect(repo.all.map((c) => c.id), [23, 22, 21]);
    expect(repo.loaded, isTrue);
    expect(repo.lastRefreshFailed, isFalse);
  });

  test('search is local and matches the code or the description', () async {
    final repo = CouponsRepository(fetch: (_) async => couponsPage(couponRows));
    await repo.refresh();
    repo.setQuery('spring');
    expect(repo.coupons.map((c) => c.id), [21]);
    repo.setQuery('رمضان');
    expect(repo.coupons.map((c) => c.id), [23]);
    repo.setQuery('nothing');
    expect(repo.coupons, isEmpty);
  });

  test('the last snapshot is kept in the store and shown when the next refresh fails', () async {
    final store = MemoryFeedStore();
    final first = CouponsRepository(store: store, fetch: (_) async => couponsPage(couponRows));
    await first.refresh();
    expect(store.rows.keys, containsAll([21, 22, 23]));

    final offline = CouponsRepository(store: store, fetch: (_) async => throw Exception('offline'));
    await offline.ready;
    expect(offline.all, hasLength(3)); // shown before any network round trip
    await offline.refresh();
    expect(offline.lastRefreshFailed, isTrue);
    expect(offline.all, hasLength(3));
  });

  test('a page that fails half way keeps the old snapshot untouched', () async {
    final store = MemoryFeedStore();
    await CouponsRepository(store: store, fetch: (_) async => couponsPage([couponRows[0]])).refresh();
    final repo = CouponsRepository(store: store, fetch: (p) async {
      if (p == 2) throw Exception('dropped');
      return couponsPage([couponRows[1]], totalPages: 2);
    });
    await repo.refresh();
    expect(repo.lastRefreshFailed, isTrue);
    expect(store.rows.keys, [21]);
    expect(repo.all.map((c) => c.id), [21]);
  });

  test('a snapshot replaces rows of coupons that were deleted on the server', () async {
    final store = MemoryFeedStore();
    await CouponsRepository(store: store, fetch: (_) async => couponsPage(couponRows)).refresh();
    await CouponsRepository(store: store, fetch: (_) async => couponsPage([couponRows[0]])).refresh();
    expect(store.rows.keys, [21]);
  });

  test('a 403 hides the feature and drops the cached rows', () async {
    final store = MemoryFeedStore();
    await CouponsRepository(store: store, fetch: (_) async => couponsPage(couponRows)).refresh();
    final repo = CouponsRepository(
      store: store,
      fetch: (_) async => throw const ApiError(status: 403, code: 'some_other_code'),
    );
    await repo.refresh();
    // Whatever code the server used, a 403 must not leave coupons on the phone.
    expect(repo.noAccess, isTrue);
    expect(store.rows, isEmpty);
  });

  test('without coupons.view in the permission map nothing is pulled and the cache is dropped', () async {
    final store = MemoryFeedStore();
    await CouponsRepository(store: store, fetch: (_) async => couponsPage(couponRows)).refresh();
    var fetched = false;
    final repo = CouponsRepository(
      store: store,
      fetch: (_) async {
        fetched = true;
        return couponsPage(couponRows);
      },
      loadPermissions: () async => customersMe(['orders.view']),
    );
    await repo.refresh();
    expect(repo.noAccess, isTrue);
    expect(fetched, isFalse);
    expect(store.rows, isEmpty);
    expect(repo.all, isEmpty);
  });

  test('editing is offered only when the map grants coupons.edit', () async {
    final view = CouponsRepository(
      fetch: (_) async => couponsPage(couponRows),
      loadPermissions: () async => customersMe(['coupons.view']),
    );
    await view.refresh();
    expect(view.canEdit, isFalse);
    final edit = CouponsRepository(
      fetch: (_) async => couponsPage(couponRows),
      loadPermissions: () async => customersMe(['coupons.view', 'coupons.edit']),
    );
    await edit.refresh();
    expect(edit.canEdit, isTrue);
  });

  test('the account wipe removes the coupons feed, in memory and in the durable stores', () async {
    final memory = MemoryAdminStores(accountId: 'a');
    await CouponsRepository(store: memory.feed(AdminFeeds.coupons), fetch: (_) async => couponsPage(couponRows))
        .refresh();
    expect(await memory.feed(AdminFeeds.coupons).readAll(), hasLength(3));
    await memory.wipe();
    expect(await memory.feed(AdminFeeds.coupons).readAll(), isEmpty);

    final storage = FakeAccountStorage();
    final durable = DurableAdminStores(storage, 'shop.test:1');
    final other = DurableAdminStores(storage, 'shop.test:2');
    for (final s in [durable, other]) {
      await CouponsRepository(store: s.feed(AdminFeeds.coupons), fetch: (_) async => couponsPage(couponRows))
          .refresh();
    }
    await durable.wipe();
    expect(await durable.feed(AdminFeeds.coupons).readAll(), isEmpty);
    expect(await other.feed(AdminFeeds.coupons).readAll(), hasLength(3));
  });
}
