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
/// value as the server stores it (a slug such as `7-5`). The display text (`7.5`) comes from the
/// item's `variation_attributes`; without it the slug is shown as it is.
class ProductVariation {
  const ProductVariation({
    required this.id,
    this.attributes = const {},
    this.price,
    this.stockStatus = 'instock',
    this.stock,
    this.displayLabel,
  });

  /// [currency] is the item's currency code; [labels] maps attribute key -> slug -> display label.
  factory ProductVariation.fromRecord(
    Map<String, dynamic> r, {
    String currency = 'USD',
    Map<String, Map<String, String>> labels = const {},
  }) {
    final raw = r['attributes'];
    final attributes = <String, String>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final key = '${e.key}'.replaceFirst(RegExp(r'^attribute_'), '');
        final value = e.value;
        if (key.isNotEmpty && value is String) attributes[key] = value;
      }
    }
    final shown = <String>[];
    for (final e in attributes.entries) {
      final named = labels[e.key]?[e.value];
      shown.add(named == null || named.isEmpty ? e.value : named);
    }
    return ProductVariation(
      id: Product._asInt(r['id']) ?? 0,
      attributes: attributes,
      price: Product._money(r['price'], currency),
      stockStatus: Product._asString(r['stock_status'], 'instock'),
      stock: Product._asInt(r['stock']),
      displayLabel: labels.isEmpty ? null : shown.join(' / '),
    );
  }

  final int id;
  final Map<String, String> attributes;
  final Money? price;
  final String stockStatus;
  final int? stock;

  /// The values as labels (`7.5`), or null when the item carried no `variation_attributes`.
  final String? displayLabel;

  bool get isSoldOut => stockStatus == 'outofstock';

  /// True when every attribute has a value. A variation with an "any" attribute (empty value)
  /// would need the customer's own pick, which the feed gives no options for, so it is not offered.
  bool get isSelectable => id > 0 && attributes.isNotEmpty && !attributes.values.any((v) => v.isEmpty);

  /// What the picker shows: the value labels in key order, e.g. `7.5` or `Silver / 7`; the raw
  /// slugs when the server sent no labels.
  String get label => displayLabel ?? attributes.values.join(' / ');

  /// The `variation` array the Store API's add-item route expects.
  List<({String attribute, String value})> get cartAttributes => [
        for (final e in attributes.entries) (attribute: e.key, value: e.value),
      ];
}

/// One attribute a variable product varies by, from the item's `variation_attributes`:
/// `{key, label, options: [{value, label}]}`. `key` matches the keys of a variation's
/// `attributes`; each option `value` is the slug stored on the variation.
class VariationAttribute {
  const VariationAttribute({required this.key, required this.label, this.options = const {}});

  /// Null when the entry has no usable key.
  static VariationAttribute? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final key = Product._asString(raw['key']).replaceFirst(RegExp(r'^attribute_'), '');
    if (key.isEmpty) return null;
    final options = <String, String>{};
    final rawOptions = raw['options'];
    if (rawOptions is List) {
      for (final o in rawOptions) {
        if (o is! Map) continue;
        final value = Product._asString(o['value']);
        final label = Product._asString(o['label']);
        if (value.isNotEmpty && label.isNotEmpty) options[value] = label;
      }
    }
    return VariationAttribute(key: key, label: Product._asString(raw['label']), options: options);
  }

  final String key;

  /// The attribute's display name (`Size`), possibly empty.
  final String label;

  /// Slug -> display label (`7-5` -> `7.5`).
  final Map<String, String> options;
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
    this.variationAttributes = const [],
    this.currency = 'USD',
  });

  factory Product.fromRecord(Map<String, dynamic> r) {
    final rawImages = r['images'];
    final rawCategories = r['categories'];
    final rawVariations = r['variations'];
    final rawAttributes = r['variation_attributes'];
    final currency = _currency(r['currency']);
    final attributes = <VariationAttribute>[];
    if (rawAttributes is List) {
      for (final a in rawAttributes) {
        final parsed = VariationAttribute.tryParse(a);
        if (parsed != null) attributes.add(parsed);
      }
    }
    final labels = {for (final a in attributes) a.key: a.options};
    return Product(
      id: _asInt(r['id']) ?? 0,
      name: _asString(r['name']),
      currency: currency,
      variationAttributes: attributes,
      price: _money(r['price'], currency),
      regularPrice: _money(r['regular_price'], currency),
      salePrice: _money(r['sale_price'], currency),
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
            if (v is Map)
              ProductVariation.fromRecord(
                Map<String, dynamic>.from(v),
                currency: currency,
                labels: labels,
              ),
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

  /// The attributes the variations differ by, with display labels.
  final List<VariationAttribute> variationAttributes;

  /// ISO currency code the item's prices are in (the server's `currency`).
  final String currency;

  /// The server's display name for attribute [key] (`Size`), or null when unknown.
  String? attributeLabel(String key) {
    for (final a in variationAttributes) {
      if (a.key == key && a.label.isNotEmpty) return a.label;
    }
    return null;
  }

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

  static String _currency(Object? v) {
    final code = v is String ? v.trim().toUpperCase() : '';
    return RegExp(r'^[A-Z]{3}$').hasMatch(code) ? code : 'USD';
  }

  static Money? _money(Object? v, [String currency = 'USD']) {
    if (v is! String || v.trim().isEmpty) return null;
    try {
      return Money.parse(v, currency: currency);
    } on FormatException {
      return null;
    }
  }
}
