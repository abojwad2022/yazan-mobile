import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/customers/customer_detail_controller.dart';
import 'package:yazan_admin/src/customers/customer_detail_page.dart';
import 'package:yazan_admin/src/customers/customer_permissions.dart';
import 'package:yazan_admin/src/customers/customer_summary.dart';
import 'package:yazan_domain/yazan_domain.dart';

import 'fakes.dart';

CustomerSummary get _summary => CustomerSummary.fromJson(customerRows[0]);

void main() {
  group('CustomerDetail', () {
    test('parses the billing block, the last order and the totals', () {
      final d = CustomerDetail.fromJson(customerDetailBody());
      expect(d.name, 'Layla Hassan');
      expect(d.phone, '+966501234567');
      expect(d.orderCount, 3);
      expect(d.totalSpent, '450.00');
      expect(d.currencySymbol, r'$');
      expect(d.addressLines, ['Layla Hassan', '12 Palm Street', '11564 Riyadh', 'SA']);
      expect(d.hasBilling, isTrue);
      expect(d.lastOrder?.number, '901');
      expect(d.lastOrder?.status, 'processing');
    });

    test('a record the server stripped of billing and without orders still parses', () {
      final d = CustomerDetail.fromJson(customerDetailBody(withBilling: false, withLastOrder: false));
      expect(d.hasBilling, isFalse);
      expect(d.phone, '');
      expect(d.addressLines, isEmpty);
      expect(d.lastOrder, isNull);
      expect(d.email, 'layla@example.test');
    });
  });

  group('CustomerDetailController', () {
    test('loads the record', () async {
      final c = CustomerDetailController(customerId: 11, load: (id) async => customerDetailBody());
      await c.load();
      expect(c.loading, isFalse);
      expect(c.failed, isFalse);
      expect(c.detail?.orderCount, 3);
    });

    test('a network failure is a failed load; a 403 is no access', () async {
      final offline = CustomerDetailController(customerId: 11, load: (id) async => throw Exception('offline'));
      await offline.load();
      expect(offline.failed, isTrue);
      expect(offline.noAccess, isFalse);

      final denied = CustomerDetailController(
        customerId: 11,
        load: (id) async => throw const ApiError(status: 403, code: 'yazan_forbidden'),
      );
      await denied.load();
      expect(denied.noAccess, isTrue);
      expect(denied.failed, isFalse);
    });
  });

  group('CustomerDetailPage', () {
    testWidgets('shows contact, address, totals and the last order (en)', (tester) async {
      await tester.pumpWidget(
        customersHost(
          const Locale('en'),
          CustomerDetailPage(summary: _summary, load: (id) async => customerDetailBody()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Customer since 2026-01-05'), findsOneWidget);
      expect(find.text('+966501234567'), findsOneWidget);
      expect(find.text('12 Palm Street'), findsOneWidget);
      expect(find.text('11564 Riyadh'), findsOneWidget);
      expect(find.text('450.00 \$'), findsOneWidget);
      expect(find.text('Order #901'), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);
      expect(find.text('150.00 \$'), findsOneWidget);
      expect(find.byKey(const ValueKey('customer-pii-note')), findsNothing);
    });

    testWidgets('has no edit controls: it is read-only', (tester) async {
      await tester.pumpWidget(
        customersHost(
          const Locale('en'),
          CustomerDetailPage(summary: _summary, load: (id) async => customerDetailBody()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('offline: the list row still shows, with a retry that works', (tester) async {
      var online = false;
      await tester.pumpWidget(
        customersHost(
          const Locale('en'),
          CustomerDetailPage(
            summary: _summary,
            load: (id) async {
              if (!online) throw Exception('offline');
              return customerDetailBody();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('layla@example.test'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.textContaining('Could not load the customer details'), findsOneWidget);
      expect(find.text('Order #901'), findsNothing);

      online = true;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Order #901'), findsOneWidget);
      expect(find.textContaining('Could not load the customer details'), findsNothing);
    });

    testWidgets('a customer with no orders says so', (tester) async {
      await tester.pumpWidget(
        customersHost(
          const Locale('en'),
          CustomerDetailPage(
            summary: _summary,
            load: (id) async => customerDetailBody(withLastOrder: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('customer-no-orders')), findsOneWidget);
    });

    testWidgets('without customers.view_pii the screen explains the missing contact details', (tester) async {
      await tester.pumpWidget(
        customersHost(
          const Locale('en'),
          CustomerDetailPage(
            summary: _summary,
            permissions: CustomerPermissions.of(['customers.view']),
            load: (id) async => customerDetailBody(withBilling: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Contact details and addresses are hidden for your account.'), findsOneWidget);
      expect(find.text('12 Palm Street'), findsNothing);
    });

    testWidgets('a 403 on the record shows the no-access state', (tester) async {
      await tester.pumpWidget(
        customersHost(
          const Locale('en'),
          CustomerDetailPage(
            summary: _summary,
            load: (id) async => throw const ApiError(status: 403, code: 'yazan_forbidden'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No access'), findsOneWidget);
    });

    testWidgets('renders right-to-left in Arabic with Latin contact details', (tester) async {
      await tester.pumpWidget(
        customersHost(
          const Locale('ar'),
          CustomerDetailPage(summary: _summary, load: (id) async => customerDetailBody()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('عميل منذ 2026-01-05'), findsOneWidget);
      expect(find.text('آخر طلب'), findsOneWidget);
      expect(find.text('قيد المعالجة'), findsOneWidget);
      final phone = find.text('+966501234567');
      expect(phone, findsOneWidget);
      expect(Directionality.of(tester.element(phone)), TextDirection.rtl);
      expect(tester.widget<Text>(phone).textDirection, TextDirection.ltr);
    });
  });
}
