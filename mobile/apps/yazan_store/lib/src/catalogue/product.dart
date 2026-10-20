import 'package:yazan_domain/yazan_domain.dart';

/// One product image: a small thumbnail for lists and a larger one for the product page.
class ProductImage {
  const ProductImage({required this.thumb, required this.medium});

  final String thumb;
  final String medium;
}

/// One purchasable variation of a variable product (for rings: one size), from the feed's
/// `variations` list: `{id, attributes, price, stock_status, stock}`.
///
/// `attributes` maps the attribute key (`size` or `pa_size`, no `attribute_` prefix) to the chosen
/// value as the server stores it (a slug such as `7`). The feed carries no display labels, so the
/// value is shown as it is.
class ProductVariation {
  const ProductVariation({
    required this.id,
    this.attributes = const {},
    this.price,
    this.stockStatus = 'instock',
    this.stock,
  });

  factory ProductVariation.fromRecord(Map<String, dynamic> r) {
    final raw = r['attributes'];
    final attributes = <String, String>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final key = '${e.key}'.replaceFirst(RegExp(r'^attribute_'), '');
        final value = e.value;
        if (key.isNotEmpty && value is String) attributes[key] = value;
      }
    }
    return ProductVariation(
      id: Product._asInt(r['id']) ?? 0,
      attributes: attributes,
      price: Product._money(r['price']),
      stockStatus: Product._asString(r['stock_status'], 'instock'),
      stock: Product._asInt(r['stock']),
    );
  }

  final int id;
  final Map<String, String> attributes;
  final Money? price;
  final String stockStatus;
  final int? stock;

  bool get isSoldOut => stockStatus == 'outofstock';

  /// True when every attribute has a value. A variation with an "any" attribute (empty value)
  /// would need the customer's own pick, which the feed gives no options for, so it is not offered.
  bool get isSelectable => id > 0 && attributes.isNotEmpty && !attributes.values.any((v) => v.isEmpty);

  /// What the picker shows: the values in key order, e.g. `7` or `Silver / 7`.
  String get label => attributes.values.join(' / ');

  /// The `variation` array the Store API's add-item route expects.
  List<({String attribute, String value})> get cartAttributes => [
        for (final e in attributes.entries) (attribute: e.key, value: e.value),
      ];
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
    this.type = 'simple',
    this.variations = const [],
  });

  factory Product.fromRecord(Map<String, dynamic> r) {
    final rawImages = r['images'];
    final rawCategories = r['categories'];
    final rawVariations = r['variations'];
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
      type: _asString(r['type'], 'simple'),
      variations: [
        if (rawVariations is List)
          for (final v in rawVariations)
            if (v is Map) ProductVariation.fromRecord(Map<String, dynamic>.from(v)),
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

  /// WooCommerce product type (`simple`, `variable`, ...).
  final String type;

  /// Purchasable variations; only filled for variable products.
  final List<ProductVariation> variations;

  /// A variable product (rings with sizes) is bought by choosing one of its variations.
  bool get isVariable => type == 'variable' || variations.isNotEmpty;

  /// The variations a customer can pick from (complete attributes only).
  List<ProductVariation> get selectableVariations =>
      [for (final v in variations) if (v.isSelectable) v];

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
