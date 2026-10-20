import 'product_input.dart';

/// How a product's stock reads at a glance.
enum StockLevel { inStock, outOfStock, onBackorder, unknown }

/// One row of the catalogue feed (`/yazan-mobile/v1/sync/catalog`). Parsing never throws: a record
/// with missing or odd fields still renders. The feed carries no currency and no version token, so
/// prices are plain decimal strings and every edit reads the record again first.
class ProductSummary {
  const ProductSummary({
    required this.id,
    required this.name,
    required this.sku,
    required this.type,
    required this.price,
    required this.regularPrice,
    required this.salePrice,
    required this.onSale,
    required this.stockStatus,
    required this.stock,
    required this.thumbUrl,
    required this.modified,
  });

  factory ProductSummary.fromJson(Map<String, dynamic> json) {
    var stock = _int(json['stock']);
    final rawVariations = json['variations'];
    if (stock == null && rawVariations is List) {
      // A variable product holds its units in its sizes: show the tracked total.
      var total = 0;
      var any = false;
      for (final v in rawVariations) {
        if (v is Map) {
          final s = _int(v['stock']);
          if (s != null) {
            total += s;
            any = true;
          }
        }
      }
      if (any) stock = total;
    }
    var thumb = '';
    final images = json['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) thumb = _str(first['thumb']);
    }
    return ProductSummary(
      id: _int(json['id']) ?? 0,
      name: _str(json['name']).trim(),
      sku: _str(json['sku']).trim(),
      type: _str(json['type']),
      price: _str(json['price']),
      regularPrice: _str(json['regular_price']),
      salePrice: _str(json['sale_price']),
      onSale: json['on_sale'] == true,
      stockStatus: _str(json['stock_status']),
      stock: stock,
      thumbUrl: thumb,
      modified: _str(json['modified']),
    );
  }

  final int id;
  final String name;
  final String sku;

  /// WooCommerce product type: `simple`, `variable`, ...
  final String type;

  /// The price a customer pays now (sale price when on sale), as the server sent it.
  final String price;
  final String regularPrice;
  final String salePrice;
  final bool onSale;

  /// `instock`, `outofstock` or `onbackorder`.
  final String stockStatus;

  /// Units, or null when the product does not count units.
  final int? stock;
  final String thumbUrl;
  final String modified;

  bool get isVariable => type == 'variable';

  DateTime? get modifiedAt => DateTime.tryParse(modified);

  StockLevel get level {
    switch (stockStatus) {
      case 'outofstock':
        return StockLevel.outOfStock;
      case 'onbackorder':
        return StockLevel.onBackorder;
      case 'instock':
        return StockLevel.inStock;
    }
    final s = stock;
    if (s == null) return StockLevel.unknown;
    return s > 0 ? StockLevel.inStock : StockLevel.outOfStock;
  }

  /// Case-insensitive match on the name or the SKU; an empty query matches everything.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final n = name.toLowerCase();
    final s = sku.toLowerCase();
    if (n.contains(q) || s.contains(q)) return true;
    // Staff on an Arabic keyboard type Arabic-Indic digits; SKUs are stored with ASCII ones.
    final ascii = normalizeDigits(q);
    return ascii != q && (n.contains(ascii) || s.contains(ascii));
  }

  static String _str(Object? v) => v == null ? '' : '$v';

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_str(v));
  }
}
