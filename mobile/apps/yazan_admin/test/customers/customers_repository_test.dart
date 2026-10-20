import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/customers/customer_api.dart';
import 'package:yazan_admin/src/customers/customer_summary.dart';
import 'package:yazan_admin/src/customers/customers_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'fakes.dart';

DeltaPage _page(List<Map<String, dynamic>> items, {String cursor = 'c1', bool initial = true}) =>
    DeltaPage(items: items, cursor: cursor, hasMore: false, initial: initial);

void main() {
  group('CustomerSummary', () {
    test('parses the list row and survives odd fields', () {
      final c = CustomerSummary.fromJson(customerRows[1]);
      expect(c.id, 12);
      expect(c.name, 'Omar Saleh');
      expect(c.phone, '+966 55-512 3456');
      expect(c.orderCount, 0);
      expect(c.totalSpent, '0.00');

      final odd = CustomerSummary.fromJson({'id': '7', 'email': ' a@b.test ', 'order_count': 'x'});
      expect(odd.id, 7);
      expect(odd.name, 'a@b.test');
      expect(odd.orderCount, isNull);
      expect(odd.totalSpent, '');
    });

    test('matches name, email and phone digits, and not a phone against letters', () {
      final omar = CustomerSummary.fromJson(customerRows[1]);
      expect(omar.matches('OMAR'), isTrue);
      expect(omar.matches('omar@example'), isTrue);
      expect(omar.matches('0555'), isFalse);
      expect(omar.matches('55512'), isTrue);
      expect(omar.matches('+966 55-512'), isTrue);
      // Arabic-Indic digits typed on an Arabic keyboard.
      expect(omar.matches('٥٥٥١٢'), isTrue);
      expect(omar.matches('omar2'), isFalse);
      expect(omar.matches(''), isTrue);
    });
  });

  group('CustomersRepository', () {
    test('refresh lists customers by name', () async {
      final repo = CustomersRepository(fetch: (_) async => _page(customerRows));
      await repo.refresh();
      expect(repo.loaded, isTrue);
      expect(repo.lastRefreshFailed, isFalse);
      expect(repo.customers.map((c) => c.id), [11, 12, 13]);
    });

    test('search matches name, email and phone and can be cleared', () async {
      final repo = CustomersRepository(fetch: (_) async => _page(customerRows));
      await repo.refresh();
      repo.setQuery('layla');
      expect(repo.customers.map((c) => c.id), [11]);
      repo.setQuery('example.test');
      expect(repo.customers.length, 3);
      repo.setQuery('966 55');
      expect(repo.customers.map((c) => c.id), [12]);
      repo.setQuery('ليلى');
      expect(repo.customers.map((c) => c.id), [13]);
      repo.setQuery('nobody');
      expect(repo.customers, isEmpty);
      expect(repo.all.length, 3);
      repo.setQuery('');
      expect(repo.customers.length, 3);
    });

    test('the cache shows before any network round trip and survives a failed refresh', () async {
      final store = MemoryFeedStore()
        ..rows[11] = Map<String, dynamic>.from(customerRows[0])
        ..cursor = 'c0';
      var calls = 0;
      final repo = CustomersRepository(
        store: store,
        fetch: (_) async {
          calls++;
          throw Exception('offline');
        },
      );
      await repo.ready;
      expect(repo.customers.single.name, 'Layla Hassan');
      expect(calls, 0);

      await repo.refresh();
      expect(calls, 1);
      expect(repo.lastRefreshFailed, isTrue);
      expect(repo.noAccess, isFalse);
      expect(repo.customers.single.name, 'Layla Hassan');
    });

    test('a 403 from the feed is no access', () async {
      final repo = CustomersRepository(
        fetch: (_) async => throw const ApiError(status: 403, code: 'yazan_forbidden'),
      );
      await repo.refresh();
      expect(repo.noAccess, isTrue);
    });

    test('a permission map without customers.view hides the list and skips the feed', () async {
      var pulled = false;
      final repo = CustomersRepository(
        fetch: (_) async {
          pulled = true;
          return _page(customerRows);
        },
        loadPermissions: () async => customersMe(['orders.view', 'products.view']),
      );
      await repo.refresh();
      expect(repo.noAccess, isTrue);
      expect(pulled, isFalse);
      expect(repo.permissions.known, isTrue);
      expect(repo.customers, isEmpty);
    });

    test('a permission map with customers.view lists them and reports the PII right', () async {
      final repo = CustomersRepository(
        fetch: (_) async => _page(customerRows),
        loadPermissions: () async => customersMe(['customers.view']),
      );
      await repo.refresh();
      expect(repo.noAccess, isFalse);
      expect(repo.customers.length, 3);
      expect(repo.permissions.canViewPii, isFalse);
    });

    test('an empty permission list (PHP encodes an empty map as a list) means no access', () async {
      final repo = CustomersRepository(
        fetch: (_) async => _page(customerRows),
        loadPermissions: () async => {'id': 1, 'permissions': <Object?>[]},
      );
      await repo.refresh();
      expect(repo.noAccess, isTrue);
    });

    test('permissions that cannot be read do not block the cached list', () async {
      final repo = CustomersRepository(
        fetch: (_) async => _page(customerRows),
        loadPermissions: () async => throw Exception('offline'),
      );
      await repo.refresh();
      expect(repo.noAccess, isFalse);
      expect(repo.permissions.known, isFalse);
      expect(repo.customers.length, 3);
    });

    test('a refresh while one is running is ignored', () async {
      var calls = 0;
      final repo = CustomersRepository(
        fetch: (_) async {
          calls++;
          return _page(customerRows);
        },
      );
      final first = repo.refresh();
      final second = repo.refresh();
      await Future.wait([first, second]);
      expect(calls, 1);
    });
  });

  group('customersFeedFetch', () {
    test('asks the sync feed for the cursor and limit and parses tombstones', () async {
      final queries = <Map<String, dynamic>>[];
      final fetch = customersFeedFetch((q) async {
        queries.add(q);
        return {
          'items': [
            {'id': 11, 'name': 'Layla', 'registered': '2026-01-05T10:20:30+00:00'},
            {'id': 99, 'deleted': true},
          ],
          'cursor': 'abc',
          'has_more': true,
          'initial': true,
          'server_time': '2026-10-20T00:00:00+00:00',
        };
      }, limit: 25);
      final page = await fetch('');
      expect(queries.single, {'cursor': '', 'limit': 25});
      expect(page.cursor, 'abc');
      expect(page.hasMore, isTrue);
      expect(page.initial, isTrue);
      expect(page.upserts.single['id'], 11);
      expect(page.deletedIds, [99]);
    });

    test('a malformed body is a failed refresh, not a crash', () async {
      final repo = CustomersRepository(
        fetch: customersFeedFetch((q) async => <String, dynamic>{'oops': true}),
      );
      await repo.refresh();
      expect(repo.lastRefreshFailed, isTrue);
      expect(repo.all, isEmpty);
    });
  });

  group('CustomerSummary from the feed', () {
    test('keeps only the day of the ISO sign-up time and tolerates removed keys', () {
      final c = CustomerSummary.fromJson({
        'id': 5,
        'name': 'Sara',
        'order_count': 2,
        'registered': '2026-03-04T08:00:00+00:00',
        'modified': '2026-10-01 12:00:00',
      });
      expect(c.registered, '2026-03-04');
      expect(c.email, '');
      expect(c.phone, '');
      expect(c.totalSpent, '');
    });
  });

  group('CustomersRepository delta feed', () {
    DeltaPage page(List<Map<String, dynamic>> items,
            {required String cursor, bool initial = false, bool more = false}) =>
        DeltaPage(items: items, cursor: cursor, hasMore: more, initial: initial);

    test('walks pages, then a later delta upserts and a tombstone removes', () async {
      final seen = <String>[];
      final pages = <String, DeltaPage>{
        '': page([customerRows[0]], cursor: 'c1', initial: true, more: true),
        'c1': page([customerRows[1]], cursor: 'c2', initial: true),
        'c2': page([
          {'id': 11, 'deleted': true},
          {...customerRows[1], 'name': 'Omar S.'},
        ], cursor: 'c3'),
      };
      final repo = CustomersRepository(fetch: (c) async {
        seen.add(c);
        return pages[c]!;
      });
      await repo.refresh();
      expect(seen, ['', 'c1']);
      expect(repo.all.map((c) => c.id), [11, 12]);

      await repo.refresh();
      expect(seen.last, 'c2');
      expect(repo.all.map((c) => c.name), ['Omar S.']);
    });

    test('the sync stamp row is never listed', () async {
      final store = MemoryFeedStore();
      final repo = CustomersRepository(
        store: store,
        fetch: (_) async => page(customerRows, cursor: 'c1', initial: true),
      );
      await repo.refresh();
      expect(store.rows.containsKey(CustomersRepository.metaId), isTrue);
      expect(store.cursor, 'c1');
      expect(repo.all.length, 3);
    });

    test('a cache older than the tombstone window starts over with an empty cursor', () async {
      var now = DateTime.utc(2026, 1, 1);
      final seen = <String>[];
      final repo = CustomersRepository(
        clock: () => now,
        fetch: (c) async {
          seen.add(c);
          return c.isEmpty
              ? page(customerRows, cursor: 'c1', initial: true)
              : page(const [], cursor: c);
        },
      );
      await repo.refresh();
      now = now.add(const Duration(days: 30));
      await repo.refresh();
      expect(seen, ['', 'c1']);

      // Offline for longer than the server keeps tombstones: the deleted customers never arrive,
      // so the rows are dropped and the whole feed is read again.
      now = now.add(const Duration(days: 100));
      seen.clear();
      await repo.refresh();
      expect(seen, ['']);
      expect(repo.all.length, 3);
    });

    test('a cursor the server refuses (400) is retried once from scratch', () async {
      final store = MemoryFeedStore()
        ..rows[11] = Map<String, dynamic>.from(customerRows[0])
        ..rows[77] = {'id': 77, 'name': 'Deleted long ago', 'email': 'x@example.test'}
        ..cursor = 'old';
      final seen = <String>[];
      final repo = CustomersRepository(
        store: store,
        fetch: (c) async {
          seen.add(c);
          if (c == 'old') {
            throw const ApiError(status: 400, code: 'yazan_mobile_bad_cursor');
          }
          return page([customerRows[1]], cursor: 'n1', initial: true);
        },
      );
      await repo.refresh();
      expect(seen, ['old', '']);
      expect(repo.lastRefreshFailed, isFalse);
      expect(repo.all.map((c) => c.id), [12]);
    });

    test('a second refusal is reported, not looped on', () async {
      var calls = 0;
      final repo = CustomersRepository(fetch: (_) async {
        calls++;
        throw const ApiError(status: 400, code: 'yazan_mobile_bad_cursor');
      });
      await repo.refresh();
      expect(calls, 2);
      expect(repo.lastRefreshFailed, isTrue);
    });

    test('without customers.view_pii the cache shows no email or phone, even from older rows', () async {
      final store = MemoryFeedStore()..rows[12] = Map<String, dynamic>.from(customerRows[1]);
      final repo = CustomersRepository(
        store: store,
        loadPermissions: () async => customersMe(['customers.view']),
        fetch: (_) async => page(const [], cursor: 'c1'),
      );
      await repo.refresh();
      final c = repo.all.single;
      expect(c.email, '');
      expect(c.phone, '');
      expect(c.totalSpent, '');
      expect(c.name, 'Omar Saleh');
    });

    test('granting customers.view_pii later refetches everything, since cached rows lack the key', () async {
      final seen = <String>[];
      final store = MemoryFeedStore()
        ..rows[12] = {'id': 12, 'name': 'Omar Saleh'}
        ..cursor = 'c1';
      final repo = CustomersRepository(
        store: store,
        loadPermissions: () async => customersMe(['customers.view', 'customers.view_pii']),
        fetch: (c) async {
          seen.add(c);
          return c.isEmpty
              ? page([customerRows[1]], cursor: 'c9', initial: true)
              : page(const [], cursor: c);
        },
      );
      await repo.refresh();
      expect(seen, ['c1', '']);
      expect(repo.all.single.email, 'omar@example.test');
    });
  });
}
