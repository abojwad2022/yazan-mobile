import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_domain/yazan_domain.dart';
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

/// A server whose feed never ends within one refresh (every page says there is more) until
/// [ends] is set; then one page brings [_row] 3 and the feed ends.
class _CutOffServer {
  bool ends = false;
  int calls = 0;

  Future<DeltaPage> fetch(String cursor) async {
    calls++;
    if (ends) {
      return DeltaPage(items: [_row(3, 'Gamma ring')], cursor: 'end', hasMore: false, initial: true);
    }
    return DeltaPage(items: const [], cursor: 'c$calls', hasMore: true, initial: cursor.isEmpty);
  }
}

CatalogueRepository _cutOffRepo(_CutOffServer server) {
  final store = MemoryFeedStore()
    ..rows.addAll({
      1: _row(1, 'Beta ring', status: 'outofstock'),
      2: _row(2, 'Alpha ring', sale: true),
    });
  return CatalogueRepository(store: store, fetch: server.fetch);
}

/// Fixed-step pumps: lets the fake async refresh run without waiting on a settled frame.
Future<void> _pumpSteps(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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

  testWidgets('a refresh cut off before the end of the feed keeps the saved items marked stale',
      (tester) async {
    final server = _CutOffServer();
    await tester.pumpWidget(_app(_cutOffRepo(server), const Locale('en')));
    await _pumpSteps(tester);

    expect(server.calls, greaterThan(1), reason: 'the pull ran until its page limit');
    // The saved rows stay on screen (a staged first sync applied nothing), marked as not fresh.
    expect(find.text('Alpha ring'), findsOneWidget);
    expect(find.text('Beta ring'), findsOneWidget);
    expect(find.text('Offline - showing saved items'), findsOneWidget);
  });

  testWidgets('a pull to refresh that reads the feed to its end clears the stale badge',
      (tester) async {
    final server = _CutOffServer();
    await tester.pumpWidget(_app(_cutOffRepo(server), const Locale('en')));
    await _pumpSteps(tester);
    expect(find.text('Offline - showing saved items'), findsOneWidget);

    server.ends = true;
    // Not awaited: the indicator's future ends only after its close animation.
    unawaited(tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show());
    await tester.pump();
    // Fixed steps: the scroll settles, the indicator snaps and refreshes, then hides.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('Offline - showing saved items'), findsNothing);
    expect(find.text('Gamma ring'), findsOneWidget);
    expect(find.text('Alpha ring'), findsNothing, reason: 'the complete first sync replaced the cache');
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
