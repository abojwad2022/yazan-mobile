import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/orders/conflict_page.dart';
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

OrdersRepository _repo({bool fail = false}) => OrdersRepository(
      fetch: (_) async {
        if (fail) throw const ApiError(status: 403, code: 'yazan_forbidden');
        return DeltaPage(
          items: const [
            {
              'id': 1001,
              'number': '1001',
              'status': 'processing',
              'total': '129.50',
              'currency': 'USD',
              'items': 2,
              'name': 'Sara Ali',
              'created': '2026-10-01T09:00:00+00:00',
              'version': 'v1',
            },
          ],
          cursor: 'c1',
          hasMore: false,
          initial: true,
        );
      },
    );

void main() {
  testWidgets('orders list renders in English', (tester) async {
    await tester.pumpWidget(_host(const Locale('en'), OrdersListPage(repository: _repo(), onOpen: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('Order #1001'), findsOneWidget);
    expect(find.text('Sara Ali'), findsOneWidget);
    expect(find.text('Processing'), findsOneWidget);
    expect(find.text('129.50 USD'), findsOneWidget);
  });

  testWidgets('orders list renders right-to-left in Arabic', (tester) async {
    await tester.pumpWidget(_host(const Locale('ar'), OrdersListPage(repository: _repo(), onOpen: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('قيد المعالجة'), findsOneWidget);
    expect(find.text('Sara Ali'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.text('Sara Ali')));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('tapping a row opens it', (tester) async {
    int? opened;
    await tester.pumpWidget(
        _host(const Locale('en'), OrdersListPage(repository: _repo(), onOpen: (o) => opened = o.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('order-1001')));
    expect(opened, 1001);
  });

  testWidgets('a 403 shows the no-access state', (tester) async {
    await tester.pumpWidget(
        _host(const Locale('en'), OrdersListPage(repository: _repo(fail: true), onOpen: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('No access'), findsOneWidget);
  });

  testWidgets('ConflictPage fires the right callback', (tester) async {
    var kept = 0;
    var overwritten = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ConflictPage(
        local: const [MapEntry('Status', 'Completed')],
        server: const [MapEntry('Status', 'Cancelled')],
        onKeepServer: () => kept++,
        onOverwrite: () => overwritten++,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    await tester.tap(find.text('Keep server version'));
    await tester.tap(find.text('Overwrite with mine'));
    expect(kept, 1);
    expect(overwritten, 1);
  });
}
