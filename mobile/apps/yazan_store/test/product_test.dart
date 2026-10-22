import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';
import 'package:yazan_store/src/catalogue/catalogue_repository.dart';
import 'package:yazan_store/src/catalogue/product.dart';

Map<String, dynamic> _record(int id, String name, {Map<String, dynamic>? extra}) => {
      'id': id,
      'name': name,
      'price': '90.00',
      'regular_price': '120.00',
      'sale_price': '90.00',
      'on_sale': true,
      'stock_status': 'instock',
      'stock': 3,
      'summary': 'Agate ring',
      'categories': [4, 7],
      'images': [
        {'id': 1, 'thumb': 'https://x.test/t.jpg', 'medium': 'https://x.test/m.jpg'},
      ],
      ...?extra,
    };

DeltaPage _page(List<Map<String, dynamic>> items, {String cursor = 'c1', bool initial = true}) =>
    DeltaPage(items: items, cursor: cursor, hasMore: false, initial: initial);

void main() {
  group('Product.fromRecord', () {
    test('parses a full record', () {
      final p = Product.fromRecord(_record(5, 'Aqeeq'));
      expect(p.id, 5);
      expect(p.name, 'Aqeeq');
      expect(p.price, const Money(9000));
      expect(p.regularPrice, const Money(12000));
      expect(p.hasSalePrice, isTrue);
      expect(p.isSoldOut, isFalse);
      expect(p.stock, 3);
      expect(p.categories, [4, 7]);
      expect(p.thumbUrl, 'https://x.test/t.jpg');
      expect(p.mediumUrl, 'https://x.test/m.jpg');
    });

    test('tolerates a nearly empty record', () {
      final p = Product.fromRecord({'id': 9});
      expect(p.name, '');
      expect(p.price, isNull);
      expect(p.hasSalePrice, isFalse);
      expect(p.stockStatus, 'instock');
      expect(p.stock, isNull);
      expect(p.images, isEmpty);
      expect(p.thumbUrl, isNull);
    });

    test('ignores malformed prices, images and categories', () {
      final p = Product.fromRecord({
        'id': 1,
        'name': 'X',
        'price': 'abc',
        'regular_price': '',
        'images': ['nope', 3],
        'categories': ['a', 2],
      });
      expect(p.price, isNull);
      expect(p.regularPrice, isNull);
      expect(p.images, isEmpty);
      expect(p.categories, [2]);
    });

    test('sold out and no sale when on_sale is false', () {
      final p = Product.fromRecord(
        _record(2, 'Y', extra: {'stock_status': 'outofstock', 'on_sale': false}),
      );
      expect(p.isSoldOut, isTrue);
      expect(p.hasSalePrice, isFalse);
    });
  });

  group('CatalogueRepository', () {
    test('refresh fills the cache sorted by name and stamps lastSyncedAt', () async {
      final now = DateTime(2026, 1, 1);
      final repo = CatalogueRepository(
        fetch: (cursor) async => _page([_record(1, 'Zafar'), _record(2, 'amber'), _record(3, 'Basil')]),
        clock: () => now,
      );
      expect(repo.lastSyncedAt, isNull);
      await repo.refresh();
      expect(repo.lastSyncedAt, now);
      final names = [for (final p in await repo.products()) p.name];
      expect(names, ['amber', 'Basil', 'Zafar']);
    });

    test('tombstones remove products on a later pull', () async {
      final store = MemoryFeedStore();
      var call = 0;
      final repo = CatalogueRepository(
        store: store,
        fetch: (cursor) async {
          call++;
          if (call == 1) return _page([_record(1, 'A'), _record(2, 'B')]);
          return _page([
            {'id': 1, 'deleted': true},
          ], cursor: 'c2', initial: false);
        },
      );
      await repo.refresh();
      await repo.refresh();
      expect([for (final p in await repo.products()) p.id], [2]);
    });

    test('products are read through FeedStore.readAll, whatever the store', () async {
      final repo = CatalogueRepository(
        store: _ListStore([_record(2, 'Zinc'), _record(1, 'Agate')]),
        fetch: (cursor) async => throw StateError('not called'),
      );
      expect([for (final p in await repo.products()) p.name], ['Agate', 'Zinc']);
    });

    test('a failed refresh throws and keeps the cache and lastSyncedAt', () async {
      var fail = false;
      final repo = CatalogueRepository(
        fetch: (cursor) async {
          if (fail) throw Exception('offline');
          return _page([_record(1, 'Keep')]);
        },
      );
      await repo.refresh();
      final stamp = repo.lastSyncedAt;
      fail = true;
      await expectLater(repo.refresh(), throwsException);
      expect(repo.lastSyncedAt, stamp);
      expect([for (final p in await repo.products()) p.name], ['Keep']);
    });

    test('a successful refresh stores synced_at (UTC) as feed metadata', () async {
      final store = MemoryFeedStore();
      final now = DateTime.utc(2026, 10, 20, 12);
      final repo = CatalogueRepository(store: store, fetch: (cursor) async => _page([_record(1, 'A')]), clock: () => now);
      await repo.refresh();
      expect(store.meta[CatalogueRepository.syncedAtKey], '2026-10-20T12:00:00.000Z');
    });

    test('a failed refresh stores no synced_at', () async {
      final store = MemoryFeedStore();
      final repo = CatalogueRepository(store: store, fetch: (cursor) async => throw Exception('offline'));
      await expectLater(repo.refresh(), throwsException);
      expect(store.meta, isEmpty);
    });

    test('a first sync over rows without a cursor keeps them until the new catalogue is complete', () async {
      // An older install: rows on disk but no cursor.
      final store = MemoryFeedStore()..rows[9] = _record(9, 'Old');
      var failSecondPage = true;
      final repo = CatalogueRepository(
        store: store,
        fetch: (cursor) async {
          if (cursor.isEmpty) {
            return DeltaPage(items: [_record(1, 'New')], cursor: 'p1', hasMore: true, initial: true);
          }
          if (failSecondPage) throw Exception('offline');
          return DeltaPage(items: [_record(2, 'Newer')], cursor: 'c2', hasMore: false, initial: false);
        },
      );

      await expectLater(repo.refresh(), throwsException);
      expect([for (final p in await repo.products()) p.name], ['Old']);
      expect(store.cursor, '');

      failSecondPage = false;
      await repo.refresh();
      expect([for (final p in await repo.products()) p.name], ['New', 'Newer']);
      expect(store.cursor, 'c2');
    });

    test('a store without metadata support still refreshes', () async {
      final repo = CatalogueRepository(
        store: _ListStore([_record(1, 'Agate')]),
        fetch: (cursor) async => _page([_record(1, 'Agate')]),
      );
      await repo.refresh();
      expect(repo.lastSyncedAt, isNotNull);
    });

    test('a complete refresh returns true', () async {
      final repo = CatalogueRepository(fetch: (cursor) async => _page([_record(1, 'A')]));
      expect(await repo.refresh(), isTrue);
    });

    test('a pull cut off by the page limit stamps no synced_at and returns false', () async {
      final store = MemoryFeedStore()..rows[9] = _record(9, 'Old');
      var fetched = 0;
      final repo = CatalogueRepository(
        store: store,
        // The server never says "no more": the run stops at pullFeed's page limit.
        fetch: (cursor) async {
          fetched++;
          return DeltaPage(
              items: [_record(fetched, 'P$fetched')], cursor: 'c$fetched', hasMore: true, initial: true);
        },
        clock: () => DateTime.utc(2026, 10, 20),
      );
      expect(await repo.refresh(), isFalse);
      expect(fetched, greaterThan(1));
      expect(store.meta.containsKey(CatalogueRepository.syncedAtKey), isFalse);
      expect(repo.lastSyncedAt, isNull);
      // A staged first sync that did not finish applies nothing: the old rows stay.
      expect([for (final p in await repo.products()) p.name], ['Old']);
      expect(store.cursor, '');
    });

    test('an incomplete delta pull keeps the previous synced_at', () async {
      final store = MemoryFeedStore();
      var now = DateTime.utc(2026, 10, 20, 12);
      var endless = false;
      final repo = CatalogueRepository(
        store: store,
        fetch: (cursor) async => endless
            ? DeltaPage(items: const [], cursor: '${cursor}x', hasMore: true, initial: false)
            : _page([_record(1, 'A')]),
        clock: () => now,
      );
      expect(await repo.refresh(), isTrue);
      final first = store.meta[CatalogueRepository.syncedAtKey];
      expect(first, '2026-10-20T12:00:00.000Z');

      endless = true;
      now = DateTime.utc(2026, 10, 21, 12);
      expect(await repo.refresh(), isFalse);
      expect(store.meta[CatalogueRepository.syncedAtKey], first);
      expect(repo.lastSyncedAt, DateTime.utc(2026, 10, 20, 12));
      expect(store.cursor, startsWith('c1x'), reason: 'the delta cursor advanced, so the next run resumes');
    });
  });

  group('variations (ring sizes)', () {
    Map<String, dynamic> variable(List<Object?> variations) =>
        _record(21, 'Signet', extra: {'type': 'variable', 'variations': variations});

    test('parses the feed: id, attributes without the attribute_ prefix, price and stock', () {
      final p = Product.fromRecord(variable([
        {
          'id': 211,
          'attributes': {'attribute_pa_size': '7'},
          'price': '120.00',
          'stock_status': 'instock',
          'stock': 3,
        },
        {
          'id': 213,
          'attributes': {'pa_size': '9'},
          'price': '',
          'stock_status': 'outofstock',
          'stock': null,
        },
      ]));
      expect(p.type, 'variable');
      expect(p.isVariable, isTrue);
      expect(p.variations, hasLength(2));
      final v = p.variations.first;
      expect(v.id, 211);
      expect(v.attributes, {'pa_size': '7'});
      expect(v.price, const Money(12000));
      expect(v.stock, 3);
      expect(v.isSoldOut, isFalse);
      expect(v.label, '7');
      expect(v.cartAttributes, [(attribute: 'pa_size', value: '7')]);
      expect(p.variations[1].isSoldOut, isTrue);
      expect(p.variations[1].price, isNull);
    });

    test('a simple product has no variations and is not variable', () {
      final p = Product.fromRecord(_record(5, 'Plain'));
      expect(p.isVariable, isFalse);
      expect(p.variations, isEmpty);
    });

    test('only variations with every attribute set are offered', () {
      final p = Product.fromRecord(variable([
        {'id': 1, 'attributes': {'pa_size': '7'}},
        {'id': 2, 'attributes': {'pa_size': ''}}, // "any size": the feed gives no options for it
        {'id': 3, 'attributes': <String, dynamic>{}},
        {'id': 0, 'attributes': {'pa_size': '8'}},
        'junk',
      ]));
      expect([for (final v in p.selectableVariations) v.id], [1]);
    });

    test('several attributes make one combined label', () {
      final p = Product.fromRecord(variable([
        {'id': 1, 'attributes': {'pa_metal': 'silver', 'pa_size': '7'}},
      ]));
      expect(p.variations.first.label, 'silver / 7');
    });

    test('labels come from variation_attributes, the slug is the fallback', () {
      final p = Product.fromRecord(variable([
        {'id': 1, 'attributes': {'pa_size': '7-5'}},
      ]));
      expect(p.variations.first.label, '7-5'); // no variation_attributes at all
      final q = Product.fromRecord({
        ..._record(21, 'Signet', extra: {'type': 'variable'}),
        'variation_attributes': [
          {
            'key': 'pa_size',
            'label': 'Size',
            'options': [
              {'value': '7-5', 'label': '7.5'},
              {'value': 'bad'},
            ],
          },
          'junk',
          {'label': 'no key'},
        ],
        'variations': [
          {'id': 1, 'attributes': {'pa_size': '7-5'}},
          {'id': 2, 'attributes': {'pa_size': '10'}},
        ],
      });
      expect(q.variations[0].label, '7.5');
      expect(q.variations[0].attributes, {'pa_size': '7-5'}); // the cart still gets the slug
      expect(q.variations[1].label, '10');
      expect(q.attributeLabel('pa_size'), 'Size');
      expect(q.attributeLabel('pa_metal'), isNull);
    });
  });

  group('currency, stock and version from the public feed', () {
    test('prices carry the item currency; a missing or odd one is USD', () {
      final p = Product.fromRecord(_record(1, 'A', extra: {'currency': 'omr'}));
      expect(p.currency, 'OMR');
      expect(p.price, const Money(9000, 'OMR'));
      expect(p.price.toString(), 'OMR 90.00');
      expect(p.hasSalePrice, isTrue);
      expect(Product.fromRecord(_record(2, 'B')).price, const Money(9000));
      expect(Product.fromRecord(_record(3, 'C', extra: {'currency': 5})).currency, 'USD');
      expect(Product.fromRecord(_record(4, 'D', extra: {'currency': 'dollars'})).currency, 'USD');
    });

    test('variation prices use the item currency too', () {
      final p = Product.fromRecord(_record(1, 'A', extra: {
        'currency': 'SAR',
        'type': 'variable',
        'variations': [
          {'id': 1, 'attributes': {'pa_size': '7'}, 'price': '12.50'},
        ],
      }));
      expect(p.variations.single.price, const Money(1250, 'SAR'));
    });

    test('stock null and version null parse without error', () {
      final p = Product.fromRecord(_record(1, 'A', extra: {'stock': null, 'version': null}));
      expect(p.stock, isNull);
      expect(p.isSoldOut, isFalse);
    });
  });
}

/// A non-memory store: only the [FeedStore] interface is available to the repository.
class _ListStore implements FeedStore {
  _ListStore(this.rows);

  final List<Map<String, dynamic>> rows;

  @override
  Future<String> readCursor() async => '';

  @override
  Future<List<Map<String, dynamic>>> readAll() async => rows;

  @override
  Future<void> apply({
    required List<Map<String, dynamic>> upserts,
    required List<int> deletedIds,
    required String cursor,
    required bool initial,
  }) async {}
}
