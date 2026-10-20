import 'package:yazan_domain/yazan_domain.dart';

/// One product image: a small thumbnail for lists and a larger one for the product page.
class ProductImage {
  const ProductImage({required this.thumb, required this.medium});

  final String thumb;
  final String medium;
}

/// A catalogue product parsed from a `/sync/catalog` record. Tolerant of missing fields.
class Product {
  const Product({
    required this.id,
    required this.name,
    this.price,
    this.regularPrice,
    this.salePrice,
    this.onSale = false,
    this.stockStatus = 'instock',
    this.stock,
    this.summary = '',
    this.images = const [],
    this.categories = const [],
  });

  factory Product.fromRecord(Map<String, dynamic> r) {
    final rawImages = r['images'];
    final rawCategories = r['categories'];
    return Product(
      id: _asInt(r['id']) ?? 0,
      name: _asString(r['name']),
      price: _money(r['price']),
      regularPrice: _money(r['regular_price']),
      salePrice: _money(r['sale_price']),
      onSale: r['on_sale'] == true,
      stockStatus: _asString(r['stock_status'], 'instock'),
      stock: _asInt(r['stock']),
      summary: _asString(r['summary']),
      images: [
        if (rawImages is List)
          for (final i in rawImages)
            if (i is Map)
              ProductImage(
                thumb: _asString(i['thumb']),
                medium: _asString(i['medium']),
              ),
      ],
      categories: [
        if (rawCategories is List)
          for (final c in rawCategories)
            if (_asInt(c) != null) _asInt(c)!,
      ],
    );
  }

  final int id;
  final String name;
  final Money? price;
  final Money? regularPrice;
  final Money? salePrice;
  final bool onSale;
  final String stockStatus;
  final int? stock;
  final String summary;
  final List<ProductImage> images;
  final List<int> categories;

  bool get isSoldOut => stockStatus == 'outofstock';

  /// A sale only shows when the server says so and both prices are known.
  bool get hasSalePrice =>
      onSale && regularPrice != null && price != null && price!.minor < regularPrice!.minor;

  /// First image URL for lists, or null when the product has none.
  String? get thumbUrl => _first((i) => i.thumb);

  /// First image URL for the product page, falling back to the thumbnail.
  String? get mediumUrl => _first((i) => i.medium) ?? thumbUrl;

  String? _first(String Function(ProductImage) pick) {
    for (final i in images) {
      final u = pick(i);
      if (u.isNotEmpty) return u;
    }
    return null;
  }

  static String _asString(Object? v, [String fallback = '']) => v is String ? v : fallback;

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static Money? _money(Object? v) {
    if (v is! String || v.trim().isEmpty) return null;
    try {
      return Money.parse(v);
    } on FormatException {
      return null;
    }
  }
}
