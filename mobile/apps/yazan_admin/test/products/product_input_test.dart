import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/products/product_input.dart';
import 'package:yazan_admin/src/products/product_summary.dart';

void main() {
  group('normalizeDigits', () {
    test('turns Arabic-Indic digits and the Arabic decimal mark into ASCII', () {
      expect(normalizeDigits('١٢٣٫٥٠'), '123.50');
      expect(normalizeDigits('۱۲۳'), '123');
    });

    test('drops spaces, the Arabic thousands mark and direction marks', () {
      expect(normalizeDigits(' 1٬200 ‏'), '1200');
    });
  });

  group('parsePriceInput', () {
    test('accepts whole and decimal amounts', () {
      expect(parsePriceInput('129')!.minor, 12900);
      expect(parsePriceInput('129.5')!.minor, 12950);
      expect(parsePriceInput('١٢٩٫٥٠')!.minor, 12950);
      expect(parsePriceInput('1,299.00')!.minor, 129900);
    });

    test('rejects text, empty input, three decimals and absurd lengths', () {
      expect(parsePriceInput(''), isNull);
      expect(parsePriceInput('abc'), isNull);
      expect(parsePriceInput('1.234'), isNull);
      expect(parsePriceInput('1234567890123'), isNull);
    });

    test('keeps the sign so the caller can refuse zero and negatives', () {
      expect(parsePriceInput('0')!.minor, 0);
      expect(parsePriceInput('-5')!.minor, -500);
    });
  });

  group('parseStockInput', () {
    test('accepts whole numbers including Arabic digits', () {
      expect(parseStockInput('0'), 0);
      expect(parseStockInput(' 12 '), 12);
      expect(parseStockInput('٣٥'), 35);
    });

    test('rejects everything else', () {
      expect(parseStockInput(''), isNull);
      expect(parseStockInput('-1'), isNull);
      expect(parseStockInput('1.5'), isNull);
      expect(parseStockInput('abc'), isNull);
      expect(parseStockInput('1234567'), isNull);
    });
  });

  group('plainPrice / samePrice', () {
    test('normalises what the server sends', () {
      expect(plainPrice('129'), '129.00');
      expect(plainPrice('129.5'), '129.50');
      expect(plainPrice('129.500'), '129.50');
      expect(plainPrice(''), '');
      expect(plainPrice('n/a'), 'n/a');
    });

    test('compares amounts, not spellings', () {
      expect(samePrice('129', '129.00'), isTrue);
      expect(samePrice('', ''), isTrue);
      expect(samePrice('', '0.00'), isFalse);
      expect(samePrice('129.00', '130.00'), isFalse);
    });
  });

  group('ProductSummary', () {
    test('parses a catalogue feed record', () {
      final p = ProductSummary.fromJson({
        'id': 7,
        'type': 'simple',
        'name': 'Agate Ring',
        'sku': 'YZ-100',
        'price': '99.00',
        'regular_price': '120.00',
        'sale_price': '99.00',
        'on_sale': true,
        'stock_status': 'instock',
        'stock': 3,
        'images': [
          {'id': 1, 'thumb': 'https://example.test/t.jpg', 'medium': 'https://example.test/m.jpg'},
        ],
        'modified': '2026-10-01T09:00:00+00:00',
      });
      expect(p.id, 7);
      expect(p.sku, 'YZ-100');
      expect(p.onSale, isTrue);
      expect(p.stock, 3);
      expect(p.level, StockLevel.inStock);
      expect(p.thumbUrl, 'https://example.test/t.jpg');
      expect(p.modifiedAt, isNotNull);
    });

    test('tolerates missing and odd fields', () {
      final p = ProductSummary.fromJson({'id': '5', 'stock': '2', 'images': 'x'});
      expect(p.id, 5);
      expect(p.name, '');
      expect(p.stock, 2);
      expect(p.thumbUrl, '');
      expect(p.level, StockLevel.inStock);
      expect(ProductSummary.fromJson({'id': 1}).level, StockLevel.unknown);
    });

    test('a variable product shows the units tracked across its sizes', () {
      final p = ProductSummary.fromJson({
        'id': 9,
        'type': 'variable',
        'stock_status': 'instock',
        'stock': null,
        'variations': [
          {'id': 91, 'stock': 2},
          {'id': 92, 'stock': 1},
          {'id': 93, 'stock': null},
        ],
      });
      expect(p.isVariable, isTrue);
      expect(p.stock, 3);
    });

    test('stock status decides the level', () {
      expect(ProductSummary.fromJson({'stock_status': 'outofstock', 'stock': 5}).level, StockLevel.outOfStock);
      expect(ProductSummary.fromJson({'stock_status': 'onbackorder'}).level, StockLevel.onBackorder);
      expect(ProductSummary.fromJson({'stock': 0}).level, StockLevel.outOfStock);
    });

    test('matches by name or SKU, ignoring case, and by Arabic digits', () {
      final p = ProductSummary.fromJson({'id': 1, 'name': 'Agate Ring', 'sku': 'YZ-100'});
      expect(p.matches(''), isTrue);
      expect(p.matches('agate'), isTrue);
      expect(p.matches('yz-1'), isTrue);
      expect(p.matches('١٠٠'), isTrue);
      expect(p.matches('silver'), isFalse);
    });
  });
}
