/// One product line of the stock report.
class StockRow {
  const StockRow({
    required this.id,
    required this.name,
    required this.sku,
    required this.qty,
    required this.managed,
  });

  final int id;
  final String name;
  final String sku;

  /// Units in stock; null when the store does not track a quantity for the product.
  final int? qty;
  final bool managed;

  factory StockRow.fromJson(Map<String, dynamic> j) => StockRow(
        id: _int(j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        sku: '${j['sku'] ?? ''}',
        qty: _int(j['qty']),
        managed: j['managed'] == true || j['managed'] == 1,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'sku': sku, 'qty': qty, 'managed': managed};

  /// True when [query] (already lower-cased and trimmed) is part of the name or the SKU.
  bool matches(String query) =>
      query.isEmpty || name.toLowerCase().contains(query) || sku.toLowerCase().contains(query);
}

/// `GET /yazan/v1/reports/stock` as last seen: what is out of stock and what is running low.
/// Parsing never throws.
class StockSnapshot {
  const StockSnapshot({
    required this.fetchedAt,
    required this.lowThreshold,
    required this.outOfStock,
    required this.lowStock,
  });

  final DateTime fetchedAt;

  /// Products at or below this many units are listed as low; null when the server did not say.
  final int? lowThreshold;
  final List<StockRow> outOfStock;
  final List<StockRow> lowStock;

  bool get isEmpty => outOfStock.isEmpty && lowStock.isEmpty;

  factory StockSnapshot.fromServer(Map<String, dynamic> j, {required DateTime fetchedAt}) =>
      StockSnapshot(
        fetchedAt: fetchedAt,
        lowThreshold: _int(j['low_threshold']),
        outOfStock: _rows(j['out_of_stock']),
        lowStock: _rows(j['low_stock']),
      );

  factory StockSnapshot.fromJson(Map<String, dynamic> j) => StockSnapshot(
        fetchedAt: DateTime.tryParse('${j['fetched_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        lowThreshold: _int(j['low_threshold']),
        outOfStock: _rows(j['out_of_stock']),
        lowStock: _rows(j['low_stock']),
      );

  Map<String, dynamic> toJson() => {
        'fetched_at': fetchedAt.toIso8601String(),
        'low_threshold': lowThreshold,
        'out_of_stock': [for (final r in outOfStock) r.toJson()],
        'low_stock': [for (final r in lowStock) r.toJson()],
      };

  static List<StockRow> _rows(Object? v) => v is List
      ? [for (final e in v) if (e is Map) StockRow.fromJson(Map<String, dynamic>.from(e))]
      : const [];
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}');
}
