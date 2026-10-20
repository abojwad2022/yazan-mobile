import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';
import 'package:yazan_store/l10n/app_localizations.dart';
import 'package:yazan_store/src/catalogue/catalogue_list_page.dart';
import 'package:yazan_store/src/catalogue/catalogue_repository.dart';

Map<String, dynamic> _row(int id, String name, {String status = 'instock', bool sale = false}) => {
      'id': id,
      'name': name,
      'price': sale ? '90.00' : '120.00',
      'regular_price': '120.00',
      'on_sale': sale,
      'stock_status': status,
      'images': <Object>[],
    };

CatalogueRepository _repo({required bool offline}) {
  final store = MemoryFeedStore()
    ..rows.addAll({
      1: _row(1, 'Beta ring', status: 'outofstock'),
      2: _row(2, 'Alpha ring', sale: true),
    });
  return CatalogueRepository(
    store: store,
    fetch: (cursor) async {
      if (offline) throw Exception('offline');
      throw StateError('unreachable in this test');
    },
  );
}

Widget _app(CatalogueRepository repo, Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: CatalogueListPage(repository: repo)),
    );

void main() {
  testWidgets('English: cards, sold label, sale price and stale badge when offline', (tester) async {
    await tester.pumpWidget(_app(_repo(offline: true), const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Alpha ring'), findsOneWidget);
    expect(find.text('Beta ring'), findsOneWidget);
    expect(find.text('Sold'), findsOneWidget);
    expect(find.text('USD 90.00'), findsOneWidget);
    expect(find.text('USD 120.00'), findsOneWidget); // struck-through regular price
    expect(find.text('Offline - showing saved items'), findsOneWidget);

    // Alpha sorts before Beta.
    final alpha = tester.getTopLeft(find.text('Alpha ring'));
    final beta = tester.getTopLeft(find.text('Beta ring'));
    expect(alpha.dx < beta.dx || alpha.dy < beta.dy, isTrue);
  });

  testWidgets('Arabic: renders right-to-left with translated labels', (tester) async {
    await tester.pumpWidget(_app(_repo(offline: true), const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.text('نفدت الكمية'), findsOneWidget);
    expect(find.text('غير متصل - عرض العناصر المحفوظة'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.text('Alpha ring')));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('tapping a card opens the product page', (tester) async {
    await tester.pumpWidget(_app(_repo(offline: true), const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta ring'));
    await tester.pumpAndSettle();
    // The square image fills the test screen; the stock line sits below it.
    await tester.scrollUntilVisible(find.text('Sold'), 200);
    expect(find.text('Sold'), findsOneWidget);
    expect(find.text('Beta ring'), findsWidgets);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
