import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/orders/order_summary.dart';
import 'package:yazan_admin/src/orders/orders_list_page.dart';
import 'package:yazan_admin/src/orders/orders_repository.dart';
import 'package:yazan_domain/yazan_domain.dart';

Widget _host(Locale locale, Widget home) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: home),
    );

Map<String, dynamic> _row(int id, String status, String name, {String? email, String? phone}) => {
      'id': id,
      'number': '$id',
      'status': status,
      'total': '10.00',
      'currency': 'USD',
      'items': 1,
      'name': name,
      'created': '2026-10-0${id - 1000}T09:00:00+00:00',
      'version': 'v$id',
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
    };

OrdersRepository _repo() => OrdersRepository(
      fetch: (_) async => DeltaPage(
        items: [
          _row(1001, 'processing', 'Sara Ali'),
          _row(1002, 'on-hold', 'Omar Zaid'),
          _row(1003, 'completed', 'Layla Noor'),
          _row(1004, 'processing', 'Hadi Saleh'),
        ],
        cursor: 'c1',
        hasMore: false,
        initial: true,
      ),
    );

void main() {
  group('OrderSummary.matches', () {
    OrderSummary o(Map<String, dynamic> j) => OrderSummary.fromJson(j);

    test('number, name, optional email and phone; Arabic-Indic digits', () {
      final s = o(_row(1001, 'processing', 'Sara Ali', email: 'Sara@Example.com', phone: '+966 55-512 3456'));
      expect(s.matches(''), isTrue);
      expect(s.matches('#1001'), isTrue);
      expect(s.matches('١٠٠١'), isTrue);
      expect(s.matches('sara'), isTrue);
      expect(s.matches('example.com'), isTrue);
      expect(s.matches('0555 12'), isFalse);
      expect(s.matches('55512'), isTrue);
      expect(s.matches('٥٥٥١٢'), isTrue);
      expect(s.matches('zzz'), isFalse);
    });

    test('a row without email or phone never matches on them', () {
      final s = o(_row(1002, 'on-hold', 'Omar'));
      expect(s.matches('55512'), isFalse);
      expect(s.matches('@'), isFalse);
    });
  });

  group('OrdersRepository filter', () {
    test('status, query and counts', () async {
      final r = _repo();
      await r.refresh();
      expect(r.filtered.length, 4);
      r.setStatus('processing');
      expect(r.filtered.map((e) => e.id), [1004, 1001]);
      r.setQuery('sara');
      expect(r.filtered.map((e) => e.id), [1001]);
      final c = r.statusCounts;
      expect(c[null], 1);
      expect(c['processing'], 1);
      expect(c['on-hold'], isNull);
      r.setStatus(null);
      r.setQuery('');
      expect(r.statusCounts['processing'], 2);
      expect(r.statusCounts[null], 4);
    });
  });

  group('OrdersListPage filter UI', () {
    testWidgets('chips show counts and filter the rows', (tester) async {
      await tester.pumpWidget(_host(const Locale('en'), OrdersListPage(repository: _repo(), onOpen: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text('All (4)'), findsOneWidget);
      expect(find.text('Processing (2)'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-1002')), findsOneWidget);

      final chip = find.byKey(const ValueKey('orders-filter-on-hold'));
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();
      expect(find.byKey(const ValueKey('order-1002')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-1001')), findsNothing);
    });

    testWidgets('search narrows the list and shows the no-match text', (tester) async {
      await tester.pumpWidget(_host(const Locale('en'), OrdersListPage(repository: _repo(), onOpen: (_) {})));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('orders-search')), 'layla');
      await tester.pump();
      expect(find.byKey(const ValueKey('order-1003')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-1001')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('orders-search')), '٩٩٩٩');
      await tester.pump();
      expect(find.text('No orders match this filter.'), findsOneWidget);
    });

    testWidgets('a preselected status (from a dashboard card) is applied on open', (tester) async {
      final repo = _repo();
      await repo.refresh();
      repo.setStatus('on-hold');
      await tester.pumpWidget(_host(const Locale('en'), OrdersListPage(repository: repo, onOpen: (_) {})));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-1002')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-1001')), findsNothing);
      final selected = tester.widget<ChoiceChip>(find.byKey(const ValueKey('orders-filter-on-hold')));
      expect(selected.selected, isTrue);
    });

    testWidgets('renders right-to-left in Arabic with Arabic chip labels', (tester) async {
      await tester.pumpWidget(_host(const Locale('ar'), OrdersListPage(repository: _repo(), onOpen: (_) {})));
      await tester.pumpAndSettle();
      expect(find.text('الكل (4)'), findsOneWidget);
      expect(Directionality.of(tester.element(find.byKey(const ValueKey('orders-search')))), TextDirection.rtl);
    });
  });
}
