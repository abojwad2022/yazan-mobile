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

  group('pagedCustomersFetch', () {
    Map<String, dynamic> body(int page, int pages, List<Map<String, dynamic>> items) => {
          'items': items,
          'total': 3,
          'total_pages': pages,
          'page': page,
        };

    test('asks for stats, customers only, and walks the pages as a snapshot', () async {
      final queries = <Map<String, dynamic>>[];
      final fetch = pagedCustomersFetch((q) async {
        queries.add(q);
        final page = q['page'] as int;
        return page == 1 ? body(1, 2, [customerRows[0]]) : body(2, 2, [customerRows[1]]);
      }, limit: 1);

      final first = await fetch('');
      expect(first.initial, isTrue);
      expect(first.hasMore, isTrue);
      expect(first.cursor, '2');
      expect(queries.first['stats'], '1');
      expect(queries.first['role'], 'customer');
      expect(queries.first['per_page'], 1);

      final second = await fetch(first.cursor);
      expect(second.initial, isFalse);
      expect(second.hasMore, isFalse);
      // Empty, so the next refresh starts again from page 1.
      expect(second.cursor, '');
      expect(queries.last['page'], 2);
    });

    test('through pullFeed a refresh replaces the snapshot, so a removed customer disappears', () async {
      var removed = false;
      final repo = CustomersRepository(
        fetch: pagedCustomersFetch((q) async {
          return body(1, 1, removed ? [customerRows[0]] : [customerRows[0], customerRows[1]]);
        }),
      );
      await repo.refresh();
      expect(repo.all.length, 2);
      removed = true;
      await repo.refresh();
      expect(repo.all.map((c) => c.id), [11]);
    });

    test('ignores rows without an integer id and a body without items', () async {
      final fetch = pagedCustomersFetch((q) async => {
            'items': [
              {'id': 'x', 'name': 'bad'},
              customerRows[0],
              'junk',
            ],
          });
      final page = await fetch('');
      expect(page.items.length, 1);
      final empty = await pagedCustomersFetch((q) async => <String, dynamic>{})('');
      expect(empty.items, isEmpty);
      expect(empty.hasMore, isFalse);
    });
  });
}
