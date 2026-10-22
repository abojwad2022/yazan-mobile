import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/products/product_detail_controller.dart';
import 'package:yazan_admin/src/products/product_detail_page.dart';
import 'package:yazan_admin/src/products/product_permissions.dart';
import 'package:yazan_admin/src/products/product_summary.dart';
import 'package:yazan_admin/src/products/products_format.dart';
import 'package:yazan_admin/src/products/products_list_page.dart';
import 'package:yazan_admin/src/products/products_repository.dart';
import 'package:yazan_admin/src/storage/admin_stores.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../orders/fakes.dart' show KeySeq;
import 'fakes.dart';

// The catalogue feed's `currency`, `version` and `variation_attributes`: parsing, the price line,
// the read-only sizes on the detail screen, and the version shortcut of the edit flow.

const Map<String, dynamic> _variable = {
  'id': 7,
  'type': 'variable',
  'name': 'Agate Ring',
  'sku': 'YZ-100',
  'price': '120.00',
  'regular_price': '120.00',
  'sale_price': '',
  'stock_status': 'instock',
  'stock': null,
  'currency': 'SAR',
  'version': 'fv1',
  'variation_attributes': [
    {
      'key': 'pa_size',
      'label': 'Size',
      'options': [
        {'value': '52', 'label': '52'},
        {'value': '54', 'label': '54 (large)'},
      ],
    },
  ],
};

Widget _app(Locale locale, Widget home) => MaterialApp(
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

ProductDetailController _controller(
  FakeProductServer server, {
  String? feedVersion,
  DateTime? syncedAt,
  required DateTime now,
}) {
  return ProductDetailController(
    productId: 7,
    load: server.load,
    write: server.write,
    permissions: ProductPermissions.of(allProductPermissions),
    newKey: KeySeq().next,
    feedVersion: feedVersion,
    feedSyncedAt: syncedAt,
    clock: () => now,
  );
}

void main() {
  final now = DateTime.utc(2026, 10, 20, 12);

  group('ProductSummary feed fields', () {
    test('reads currency, version and the variation attributes', () {
      final p = ProductSummary.fromJson(_variable);
      expect(p.currency, 'SAR');
      expect(p.version, 'fv1');
      expect(p.variationAttributes.single.label, 'Size');
      expect(p.variationAttributes.single.options.map((o) => o.label), ['52', '54 (large)']);
    });

    test('an old cached row, a public row and odd attributes still parse', () {
      final old = ProductSummary.fromJson(const {'id': 1, 'name': 'x'});
      expect(old.currency, '');
      expect(old.version, '');
      expect(old.variationAttributes, isEmpty);

      final odd = ProductSummary.fromJson(const {
        'id': 2,
        'version': null,
        'variation_attributes': [
          'junk',
          {'key': 'a', 'options': <Object?>[]},
          {
            'key': 'pa_color',
            'options': [
              {'value': 'red'},
              'blue',
            ],
          },
        ],
      });
      expect(odd.version, '');
      expect(odd.variationAttributes.length, 1);
      // A missing label falls back to the key, a missing option label to its value.
      expect(odd.variationAttributes.single.label, 'pa_color');
      expect(odd.variationAttributes.single.options.map((o) => o.label), ['red', 'blue']);
    });

    test('priceText appends the currency only when it is known', () {
      expect(priceText('120.000', 'SAR'), '120.00 SAR');
      expect(priceText('120.00'), '120.00');
      expect(priceText('', 'SAR'), '—');
    });
  });

  group('ProductsRepository.lastSyncedAt', () {
    DeltaPage page({bool more = false}) => DeltaPage(
          items: const [_variable],
          cursor: 'c1',
          hasMore: more,
          initial: true,
        );

    test('is set after a pull that reached the end, and cleared by purge', () async {
      final repo = ProductsRepository(fetch: (_) async => page(), clock: () => now);
      expect(repo.lastSyncedAt, isNull);
      await repo.refresh();
      expect(repo.lastSyncedAt, now);
      await repo.purge();
      expect(repo.lastSyncedAt, isNull);
    });

    test('stays null when the pull failed', () async {
      final repo = ProductsRepository(fetch: (_) async => throw Exception('offline'), clock: () => now);
      await repo.refresh();
      expect(repo.lastSyncedAt, isNull);
    });

    test('a complete pull is stored as synced_at feed metadata, and purge removes it', () async {
      final store = MemoryFeedStore();
      final repo = ProductsRepository(store: store, fetch: (_) async => page(), clock: () => now);
      await repo.refresh();
      expect(store.meta[ProductsRepository.syncedAtKey], now.toIso8601String());
      await repo.purge();
      expect(store.meta.containsKey(ProductsRepository.syncedAtKey), isFalse);
    });

    test('a pull cut short by the page budget stores no synced_at', () async {
      final store = MemoryFeedStore();
      final repo = ProductsRepository(store: store, fetch: (_) async => page(more: true), clock: () => now);
      await repo.refresh();
      expect(repo.lastSyncedAt, isNull);
      expect(store.meta, isEmpty);
    });

    test('the guarded admin feed passes synced_at through to the stored feed', () async {
      final stores = MemoryAdminStores();
      final feed = stores.feed(AdminFeeds.products);
      final repo = ProductsRepository(store: feed, fetch: (_) async => page(), clock: () => now);
      await repo.refresh();
      expect(await feed.readMeta(ProductsRepository.syncedAtKey), now.toIso8601String());
      await stores.wipe();
      expect(await feed.readMeta(ProductsRepository.syncedAtKey), isNull);
    });
  });

  group('edit flow version', () {
    test('a fresh feed version stands in for a missing ETag: no extra read before the write', () async {
      final server = FakeProductServer()..version = null;
      final c = _controller(server, feedVersion: 'fv1', syncedAt: now.subtract(const Duration(seconds: 30)), now: now);
      await c.load();
      expect(c.usesFeedVersion, isFalse);
      expect(c.version, 'fv1');
      expect(server.loads, 1);

      final result = await c.savePrice(regular: '130.00', sale: '');
      expect(result, ProductEditResult.done);
      expect(server.writes.single.version, 'fv1');
      // One read to open the screen, one after the write for its truth; none before the write.
      expect(server.loads, 2);
    });

    test('the screen\'s own read wins over the feed copy', () async {
      final server = FakeProductServer()..version = 'v1';
      final c = _controller(server, feedVersion: 'fv1', syncedAt: now, now: now);
      await c.load();
      await c.savePrice(regular: '130.00', sale: '');
      expect(server.writes.single.version, 'v1');
    });

    test('a stale feed version is not used: the record is read again right before the write', () async {
      final server = FakeProductServer()..version = null;
      final c = _controller(
        server,
        feedVersion: 'fv1',
        syncedAt: now.subtract(const Duration(minutes: 10)),
        now: now,
      );
      await c.load();
      expect(c.version, isNull);
      // The next read gets an ETag.
      server.version = 'v9';
      final result = await c.savePrice(regular: '130.00', sale: '');
      expect(result, ProductEditResult.done);
      expect(server.writes.single.version, 'v9');
      expect(server.loads, 3);
    });

    test('an unknown sync time or an empty version is never trusted', () async {
      for (final (v, at) in <(String?, DateTime?)>[('fv1', null), ('', now), (null, now)]) {
        final server = FakeProductServer()..version = null;
        final c = _controller(server, feedVersion: v, syncedAt: at, now: now);
        await c.load();
        server.version = 'v5';
        await c.savePrice(regular: '130.00', sale: '');
        expect(server.writes.single.version, 'v5', reason: '$v / $at');
      }
    });

    test('after a write the feed version is dropped, so a second write reads the record', () async {
      final server = FakeProductServer()..version = null;
      final c = _controller(server, feedVersion: 'fv1', syncedAt: now, now: now);
      await c.load();
      await c.savePrice(regular: '130.00', sale: '');
      expect(server.writes.last.version, 'fv1');
      server.version = 'v7';
      await c.load();
      expect(c.usesFeedVersion, isFalse);
      server.version = null;
      await c.load();
      // No ETag and no feed version any more.
      expect(c.version, isNull);
      server.version = 'v8';
      await c.saveStock(5);
      expect(server.writes.last.version, 'v8');
    });

    test('a 412 with a feed version still opens the conflict screen and writes nothing', () async {
      final server = FakeProductServer()
        ..version = null
        ..writeFailures.add(const ApiError(status: 412, code: 'yazan_precondition_failed', current: 'v2'));
      final c = _controller(server, feedVersion: 'fv1', syncedAt: now, now: now);
      await c.load();
      final result = await c.savePrice(regular: '130.00', sale: '');
      expect(result, ProductEditResult.conflict);
      expect(c.conflict, isNotNull);
      expect(server.regular, '120.00');
    });
  });

  group('screens', () {
    testWidgets('the list shows the currency next to the price', (tester) async {
      final repo = ProductsRepository(
        fetch: (_) async => const DeltaPage(items: [_variable], cursor: 'c1', hasMore: false, initial: true),
      );
      await tester.pumpWidget(_app(const Locale('en'), Scaffold(body: ProductsListPage(repository: repo, onOpen: (_) {}))));
      await tester.pumpAndSettle();
      expect(find.text('120.00 SAR'), findsOneWidget);
    });

    Future<void> openDetail(WidgetTester tester, Locale locale, FakeProductServer server) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        locale,
        ProductDetailPage(
          summary: ProductSummary.fromJson(_variable),
          load: server.load,
          write: server.write,
          permissions: ProductPermissions.of(allProductPermissions),
          feedSyncedAt: DateTime.now(),
          newKey: KeySeq().next,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a product with sizes lists them read-only and says editing is on the website (en)', (tester) async {
      await openDetail(tester, const Locale('en'), FakeProductServer()..type = 'variable');
      expect(find.text('Sizes and options'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('52'), findsOneWidget);
      expect(find.text('54 (large)'), findsOneWidget);
      expect(find.byKey(const ValueKey('variations-note')), findsOneWidget);
      expect(find.textContaining('on the website'), findsWidgets);
      expect(find.text('120.00 SAR'), findsOneWidget);
      // Read-only: no edit buttons for a variable product.
      expect(find.byKey(const ValueKey('edit-price')), findsNothing);
      expect(find.byKey(const ValueKey('edit-stock')), findsNothing);
    });

    testWidgets('the same in Arabic, right-to-left', (tester) async {
      await openDetail(tester, const Locale('ar'), FakeProductServer()..type = 'variable');
      expect(find.text('المقاسات والخيارات'), findsOneWidget);
      expect(find.textContaining('من الموقع'), findsWidgets);
      expect(find.text('54 (large)'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('54 (large)'))), TextDirection.rtl);
    });

    testWidgets('a product without variation attributes shows no sizes block', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final server = FakeProductServer();
      await tester.pumpWidget(_app(
        const Locale('en'),
        ProductDetailPage(
          summary: ProductSummary.fromJson(const {'id': 7, 'type': 'simple', 'name': 'Ring'}),
          load: server.load,
          write: server.write,
          permissions: ProductPermissions.of(allProductPermissions),
          newKey: KeySeq().next,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Sizes and options'), findsNothing);
    });
  });
}
