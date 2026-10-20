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
