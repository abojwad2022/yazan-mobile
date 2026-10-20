import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/customers/customers_list_page.dart';
import 'package:yazan_admin/src/customers/customers_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'fakes.dart';

CustomersRepository _repo({Object? fail, List<String>? permissions, FeedStore? store}) {
  return CustomersRepository(
    store: store,
    fetch: (_) async {
      if (fail != null) throw fail;
      return DeltaPage(items: customerRows, cursor: 'c1', hasMore: false, initial: true);
    },
    loadPermissions: permissions == null ? null : () async => customersMe(permissions),
  );
}

void main() {
  testWidgets('the customer list renders in English with orders and spend', (tester) async {
    await tester.pumpWidget(
      customersHost(const Locale('en'), CustomersListPage(repository: _repo(), onOpen: (_) {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('Layla Hassan'), findsOneWidget);
    expect(find.text('layla@example.test'), findsOneWidget);
    expect(find.text('Orders: 3'), findsOneWidget);
    expect(find.text('450.00'), findsOneWidget);
    expect(find.text('+966 55-512 3456'), findsOneWidget);
  });

  testWidgets('the customer list renders right-to-left in Arabic', (tester) async {
    await tester.pumpWidget(
      customersHost(const Locale('ar'), CustomersListPage(repository: _repo(), onOpen: (_) {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('الطلبات: 3'), findsOneWidget);
    expect(find.text('ليلى الحداد'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('Layla Hassan'))), TextDirection.rtl);
  });

  testWidgets('search narrows the list by name, email and phone, and says when nothing matches', (tester) async {
    await tester.pumpWidget(
      customersHost(const Locale('en'), CustomersListPage(repository: _repo(), onOpen: (_) {})),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('customer-search')), 'omar');
    await tester.pumpAndSettle();
    expect(find.text('Omar Saleh'), findsOneWidget);
    expect(find.text('Layla Hassan'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('customer-search')), 'layla@');
    await tester.pumpAndSettle();
    expect(find.text('Layla Hassan'), findsOneWidget);
    expect(find.text('Omar Saleh'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('customer-search')), '55512');
    await tester.pumpAndSettle();
    expect(find.text('Omar Saleh'), findsOneWidget);
    expect(find.text('Layla Hassan'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('customer-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No customer matches “zzz”.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('customer-search')), '');
    await tester.pumpAndSettle();
    expect(find.text('Layla Hassan'), findsOneWidget);
    expect(find.text('Omar Saleh'), findsOneWidget);
  });

  testWidgets('tapping a row opens it', (tester) async {
    int? opened;
    await tester.pumpWidget(
      customersHost(const Locale('en'), CustomersListPage(repository: _repo(), onOpen: (c) => opened = c.id)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('customer-12')));
    expect(opened, 12);
  });

  testWidgets('a failed refresh keeps the cached list and shows the offline badge', (tester) async {
    final store = MemoryFeedStore()
      ..rows[11] = Map<String, dynamic>.from(customerRows[0])
      ..cursor = 'c0';
    await tester.pumpWidget(
      customersHost(
        const Locale('en'),
        CustomersListPage(repository: _repo(fail: Exception('offline'), store: store), onOpen: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Layla Hassan'), findsOneWidget);
    expect(find.text('Offline copy'), findsOneWidget);
  });

  testWidgets('an empty list says so', (tester) async {
    final repo = CustomersRepository(
      fetch: (_) async => DeltaPage(items: const [], cursor: '', hasMore: false, initial: true),
    );
    await tester.pumpWidget(customersHost(const Locale('en'), CustomersListPage(repository: repo, onOpen: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('No customers yet.'), findsOneWidget);
  });

  testWidgets('a 403 shows the no-access state', (tester) async {
    await tester.pumpWidget(
      customersHost(
        const Locale('en'),
        CustomersListPage(
          repository: _repo(fail: const ApiError(status: 403, code: 'yazan_forbidden')),
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No access'), findsOneWidget);
    expect(find.text('Your account does not have permission to view customers. Ask the store owner to grant it.'),
        findsOneWidget);
    expect(find.text('Layla Hassan'), findsNothing);
  });

  testWidgets('a permission map without customers.view hides the section (ar)', (tester) async {
    await tester.pumpWidget(
      customersHost(
        const Locale('ar'),
        CustomersListPage(repository: _repo(permissions: ['orders.view']), onOpen: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('لا صلاحية'), findsOneWidget);
    expect(find.text('حسابك لا يملك صلاحية عرض العملاء. اطلب من مالك المتجر منحك إياها.'), findsOneWidget);
    expect(find.text('Layla Hassan'), findsNothing);
  });

  testWidgets('a permission map with customers.view shows the list', (tester) async {
    await tester.pumpWidget(
      customersHost(
        const Locale('en'),
        CustomersListPage(repository: _repo(permissions: ['customers.view']), onOpen: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Layla Hassan'), findsOneWidget);
    expect(find.text('No access'), findsNothing);
  });
}
