import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/l10n/app_localizations.dart';
import 'package:yazan_store/src/account/failure.dart';
import 'package:yazan_store/src/catalogue/product.dart';
import 'package:yazan_store/src/catalogue/product_page.dart';
import 'package:yazan_store/src/wishlist/wishlist_controller.dart';
import 'package:yazan_store/src/wishlist/wishlist_mirror.dart';
import 'package:yazan_store/src/wishlist/wishlist_models.dart';
import 'package:yazan_store/src/wishlist/wishlist_page.dart';
import 'package:yazan_store/src/wishlist/wishlist_scope.dart';

import 'fixtures/account_fakes.dart';

Widget _app(Widget home, Locale locale, {WishlistController? wishlist}) {
  final app = MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
  return wishlist == null ? app : WishlistScope(controller: wishlist, child: app);
}

const _offline = 'You are offline. Changing favourites needs an internet connection.';

void main() {
  group('WishlistItem', () {
    test('reads a server card and survives a round trip through the mirror format', () {
      final item = WishlistItem.fromJson({
        'id': '13',
        'name': 'Carnelian &amp; Silver',
        'price': '&#36;120.00',
        'thumb': 'https://x.test/t.jpg',
        'url': 'https://x.test/p',
      });
      expect(item.id, 13);
      expect(item.name, 'Carnelian & Silver');
      expect(item.price, r'$120.00');
      expect(item.thumbUrl, 'https://x.test/t.jpg');
      final again = WishlistItem.fromJson(item.toJson());
      expect(again.id, 13);
      expect(again.name, item.name);
    });

    test('unusable rows are dropped', () {
      final items = parseWishlistItems([
        {'id': 5, 'name': 'Ok'},
        {'name': 'No id'},
        'junk',
      ]);
      expect([for (final i in items) i.id], [5]);
    });
  });

  group('WishlistController', () {
    test('shows the phone copy first, then replaces it with the server list', () async {
      final api = FakeWishlistApi([ring(2, 'Server ring')]);
      final mirror = MemoryWishlistMirror([ring(1, 'Old copy')]);
      final c = WishlistController(api: api, mirror: mirror);
      addTearDown(c.dispose);

      final seen = <List<int>>[];
      c.addListener(() => seen.add([for (final i in c.items) i.id]));
      await c.load();

      expect(seen.first, [1]); // the copy appeared before the server answered
      expect([for (final i in c.items) i.id], [2]);
      expect([for (final i in mirror.items!) i.id], [2]);
      expect(c.stale, isFalse);
      expect(c.failure, isNull);
    });

    test('offline: the copy stays readable and is marked stale', () async {
      final api = FakeWishlistApi()..failure = Exception('offline');
      final mirror = MemoryWishlistMirror([ring(1, 'Saved ring')]);
      final c = WishlistController(api: api, mirror: mirror);
      addTearDown(c.dispose);

      await c.load();
      expect([for (final i in c.items) i.id], [1]);
      expect(c.stale, isTrue);
      expect(c.failure!.kind, FailureKind.offline);
      expect(c.contains(1), isTrue);
    });

    test('saving checks the server first, toggles once and updates the copy', () async {
      final api = FakeWishlistApi();
      final mirror = MemoryWishlistMirror();
      final c = WishlistController(api: api, mirror: mirror);
      addTearDown(c.dispose);

      expect(await c.setSaved(ring(9, 'Nine'), saved: true), isTrue);
      expect(api.calls, ['list', 'toggle:9']);
      expect(c.contains(9), isTrue);
      expect([for (final i in mirror.items!) i.id], [9]);

      // Already saved: nothing is sent.
      expect(await c.setSaved(ring(9, 'Nine'), saved: true), isTrue);
      expect(api.calls, ['list', 'toggle:9']);

      expect(await c.setSaved(ring(9, 'Nine'), saved: false), isTrue);
      expect(api.calls.last, 'toggle:9');
      expect(c.contains(9), isFalse);
      expect(mirror.items, isEmpty);
    });

    test('a piece the server already has is not toggled off by a stale phone copy', () async {
      final api = FakeWishlistApi([ring(4, 'Four')]);
      final c = WishlistController(api: api, mirror: MemoryWishlistMirror());
      addTearDown(c.dispose);

      expect(await c.setSaved(ring(4, 'Four'), saved: true), isTrue);
      expect(api.calls, ['list']);
      expect(c.contains(4), isTrue);
    });

    test('offline: a change is refused, nothing is toggled and nothing changes locally', () async {
      final api = FakeWishlistApi()..failure = Exception('offline');
      final mirror = MemoryWishlistMirror([ring(1, 'Saved ring')]);
      final c = WishlistController(api: api, mirror: mirror);
      addTearDown(c.dispose);
      await c.load();

      expect(await c.setSaved(ring(7, 'Seven'), saved: true), isFalse);
      expect(api.calls.where((x) => x.startsWith('toggle')), isEmpty);
      expect(c.failure!.kind, FailureKind.offline);
      expect([for (final i in c.items) i.id], [1]);
      expect([for (final i in mirror.items!) i.id], [1]);
    });

    test('a toggle that fails after a good sync leaves the list as it was', () async {
      final api = FakeWishlistApi([ring(1, 'One')]);
      final c = WishlistController(api: api, mirror: MemoryWishlistMirror());
      addTearDown(c.dispose);
      await c.load();

      api.failure = Exception('offline');
      expect(await c.setSaved(ring(1, 'One'), saved: false), isFalse);
      expect(c.contains(1), isTrue);
      expect(c.busy, isFalse);
    });

    test('forget empties the list and the copy, and ignores answers still in flight', () async {
      final gate = Completer<void>();
      final api = FakeWishlistApi([ring(1, 'One')])..gate = gate.future;
      final mirror = MemoryWishlistMirror();
      final c = WishlistController(api: api, mirror: mirror);
      addTearDown(c.dispose);

      final loading = c.load();
      await Future<void>.delayed(Duration.zero);
      await c.forget();
      gate.complete();
      await loading;

      expect(c.items, isEmpty);
      expect(mirror.items, isNull);
    });
  });

  group('wishlist page', () {
    testWidgets('lists the saved pieces and removes one with a clear confirmation', (tester) async {
      final api = FakeWishlistApi([ring(1, 'Alpha ring'), ring(2, 'Beta ring', price: r'$90.00')]);
      final c = WishlistController(api: api, mirror: MemoryWishlistMirror());
      addTearDown(c.dispose);
      unawaited(c.load());

      await tester.pumpWidget(_app(
        WishlistPage(controller: c, findProduct: (id) async => null, onSessionEnded: () {}),
        const Locale('en'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Favourites'), findsOneWidget);
      expect(find.text('Alpha ring'), findsOneWidget);
      expect(find.text(r'$90.00'), findsOneWidget);
      expect(find.text('Offline - showing saved items'), findsNothing);

      await tester.tap(find.byTooltip('Remove from favourites').first);
      await tester.pumpAndSettle();
      expect(api.calls, contains('toggle:1'));
      expect(find.text('Alpha ring'), findsNothing);
      expect(find.text('Removed from your favourites'), findsOneWidget);
    });

    testWidgets('offline: the saved copy is readable, flagged, and removing is refused', (tester) async {
      final api = FakeWishlistApi()..failure = Exception('offline');
      final c = WishlistController(
        api: api,
        mirror: MemoryWishlistMirror([ring(1, 'Alpha ring')]),
      );
      addTearDown(c.dispose);
      unawaited(c.load());

      await tester.pumpWidget(_app(
        WishlistPage(controller: c, findProduct: (id) async => null, onSessionEnded: () {}),
        const Locale('en'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Alpha ring'), findsOneWidget);
      expect(find.text('Offline - showing saved items'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove from favourites'));
      await tester.pumpAndSettle();
      expect(find.text(_offline), findsOneWidget);
      expect(find.text('Alpha ring'), findsOneWidget);
      expect(api.calls.where((x) => x.startsWith('toggle')), isEmpty);
    });

    testWidgets('empty list', (tester) async {
      final c = WishlistController(api: FakeWishlistApi(), mirror: MemoryWishlistMirror());
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(
        WishlistPage(controller: c, findProduct: (id) async => null, onSessionEnded: () {}),
        const Locale('en'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No favourites yet. Tap the heart on a ring to save it.'), findsOneWidget);
    });

    testWidgets('a finished session asks the app to show the sign-in form', (tester) async {
      final api = FakeWishlistApi([ring(1, 'Alpha ring')]);
      final c = WishlistController(api: api, mirror: MemoryWishlistMirror());
      addTearDown(c.dispose);
      unawaited(c.load());
      var ended = false;
      await tester.pumpWidget(_app(
        WishlistPage(
          controller: c,
          findProduct: (id) async => null,
          onSessionEnded: () => ended = true,
        ),
        const Locale('en'),
      ));
      await tester.pumpAndSettle();

      api.failure = const ApiError(status: 401, code: 'yazan_mobile_bad_refresh');
      await tester.tap(find.byTooltip('Remove from favourites'));
      await tester.pumpAndSettle();
      expect(ended, isTrue);
    });

    testWidgets('a piece missing from the local catalogue says what to do', (tester) async {
      final c = WishlistController(
        api: FakeWishlistApi([ring(1, 'Alpha ring')]),
        mirror: MemoryWishlistMirror(),
      );
      addTearDown(c.dispose);
      unawaited(c.load());
      await tester.pumpWidget(_app(
        WishlistPage(controller: c, findProduct: (id) async => null, onSessionEnded: () {}),
        const Locale('en'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha ring'));
      await tester.pumpAndSettle();
      expect(find.text('Open the shop and pull down to refresh, then try again.'), findsOneWidget);
    });

    testWidgets('opens the product page for a cached piece', (tester) async {
      final c = WishlistController(
        api: FakeWishlistApi([ring(13, 'Alpha ring')]),
        mirror: MemoryWishlistMirror(),
      );
      addTearDown(c.dispose);
      unawaited(c.load());
      await tester.pumpWidget(_app(
        WishlistPage(
          controller: c,
          findProduct: (id) async => Product(id: id, name: 'Alpha ring page'),
          onSessionEnded: () {},
        ),
        const Locale('en'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha ring'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductPage), findsOneWidget);
    });

    testWidgets('Arabic: right-to-left with translated labels', (tester) async {
      final c = WishlistController(
        api: FakeWishlistApi()..failure = Exception('offline'),
        mirror: MemoryWishlistMirror([ring(1, 'Alpha ring')]),
      );
      addTearDown(c.dispose);
      unawaited(c.load());
      await tester.pumpWidget(_app(
        WishlistPage(controller: c, findProduct: (id) async => null, onSessionEnded: () {}),
        const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('المفضلة'), findsOneWidget);
      expect(find.text('غير متصل - عرض العناصر المحفوظة'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('Alpha ring'))), TextDirection.rtl);
    });
  });

  group('heart on the product page', () {
    const ring13 = Product(id: 13, name: 'Carnelian ring');

    testWidgets('saves and removes the piece, with a message each time', (tester) async {
      final api = FakeWishlistApi();
      final c = WishlistController(api: api, mirror: MemoryWishlistMirror());
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(const ProductPage(product: ring13), const Locale('en'), wishlist: c));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save to favourites'));
      await tester.pumpAndSettle();
      expect(api.calls, ['list', 'toggle:13']);
      expect(find.text('Saved to your favourites'), findsOneWidget);
      expect(find.byTooltip('Remove from favourites'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove from favourites'));
      await tester.pumpAndSettle();
      expect(find.text('Removed from your favourites'), findsOneWidget);
      expect(find.byTooltip('Save to favourites'), findsOneWidget);
    });

    testWidgets('offline: says so and keeps the heart as it was', (tester) async {
      final api = FakeWishlistApi()..failure = Exception('offline');
      final c = WishlistController(api: api, mirror: MemoryWishlistMirror());
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(const ProductPage(product: ring13), const Locale('en'), wishlist: c));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save to favourites'));
      await tester.pumpAndSettle();
      expect(find.text(_offline), findsOneWidget);
      expect(find.byTooltip('Save to favourites'), findsOneWidget);
      expect(api.calls.where((x) => x.startsWith('toggle')), isEmpty);
    });

    testWidgets('no heart without favourites in scope', (tester) async {
      await tester.pumpWidget(_app(const ProductPage(product: ring13), const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Save to favourites'), findsNothing);
    });
  });
}
