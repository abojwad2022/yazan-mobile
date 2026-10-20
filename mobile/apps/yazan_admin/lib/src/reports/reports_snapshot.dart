/// One day of the sales chart.
class DaySales {
  const DaySales({required this.date, required this.total, required this.orders});

  final String date;
  final double total;
  final int orders;

  factory DaySales.fromJson(Map<String, dynamic> j) =>
      DaySales(date: '${j['date'] ?? ''}', total: _num(j['total']) ?? 0, orders: _int(j['orders']) ?? 0);

  Map<String, dynamic> toJson() => {'date': date, 'total': total, 'orders': orders};
}

/// A best seller of the period.
class TopProduct {
  const TopProduct({required this.id, required this.name, required this.qty, required this.revenue});

  final int id;
  final String name;
  final int qty;
  final String revenue;

  factory TopProduct.fromJson(Map<String, dynamic> j) => TopProduct(
        id: _int(j['product_id'] ?? j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        qty: _int(j['qty']) ?? 0,
        revenue: '${j['revenue'] ?? '0'}',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'qty': qty, 'revenue': revenue};
}

/// `GET /yazan/v1/reports/sales`, reduced to what the page shows. Parsing never throws.
class SalesReport {
  const SalesReport({
    required this.netRevenue,
    required this.grossRevenue,
    required this.refunded,
    required this.orders,
    required this.refundedOrders,
    required this.itemsSold,
    required this.averageOrder,
    required this.symbol,
    required this.decimals,
    required this.rangeFrom,
    required this.rangeTo,
    required this.series,
    required this.top,
  });

  final String netRevenue;
  final String grossRevenue;
  final String refunded;
  final int orders;
  final int refundedOrders;
  final int itemsSold;
  final String averageOrder;
  final String symbol;
  final int decimals;
  final String rangeFrom;
  final String rangeTo;
  final List<DaySales> series;
  final List<TopProduct> top;

  factory SalesReport.fromServer(Map<String, dynamic> j) {
    final totals = _map(j['totals']) ?? const <String, dynamic>{};
    final currency = _map(j['currency']) ?? const <String, dynamic>{};
    final range = _map(j['range']) ?? const <String, dynamic>{};
    return SalesReport(
      netRevenue: '${totals['net_revenue'] ?? '0'}',
      grossRevenue: '${totals['gross_revenue'] ?? '0'}',
      refunded: '${totals['refunded'] ?? '0'}',
      orders: _int(totals['orders']) ?? 0,
      refundedOrders: _int(totals['refunded_orders']) ?? 0,
      itemsSold: _int(totals['items_sold']) ?? 0,
      averageOrder: '${totals['average_order'] ?? '0'}',
      symbol: '${currency['symbol'] ?? ''}',
      decimals: _int(currency['decimals']) ?? 2,
      rangeFrom: '${range['from'] ?? ''}',
      rangeTo: '${range['to'] ?? ''}',
      series: _maps(j['series']).map(DaySales.fromJson).toList(),
      top: _maps(j['top']).map(TopProduct.fromJson).toList(),
    );
  }

  factory SalesReport.fromJson(Map<String, dynamic> j) => SalesReport(
        netRevenue: '${j['net'] ?? '0'}',
        grossRevenue: '${j['gross'] ?? '0'}',
        refunded: '${j['refunded'] ?? '0'}',
        orders: _int(j['orders']) ?? 0,
        refundedOrders: _int(j['refunded_orders']) ?? 0,
        itemsSold: _int(j['items']) ?? 0,
        averageOrder: '${j['average'] ?? '0'}',
        symbol: '${j['symbol'] ?? ''}',
        decimals: _int(j['decimals']) ?? 2,
        rangeFrom: '${j['from'] ?? ''}',
        rangeTo: '${j['to'] ?? ''}',
        series: _maps(j['series']).map(DaySales.fromJson).toList(),
        top: _maps(j['top']).map(TopProduct.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => {
        'net': netRevenue,
        'gross': grossRevenue,
        'refunded': refunded,
        'orders': orders,
        'refunded_orders': refundedOrders,
        'items': itemsSold,
        'average': averageOrder,
        'symbol': symbol,
        'decimals': decimals,
        'from': rangeFrom,
        'to': rangeTo,
        'series': [for (final d in series) d.toJson()],
        'top': [for (final t in top) t.toJson()],
      };
}

/// The reports of one reporting window as last fetched. Each section is null when the server did
/// not give it to this account (sales need `reports.view`, status counts `orders.view`).
class ReportsSnapshot {
  const ReportsSnapshot({
    required this.days,
    required this.fetchedAt,
    this.sales,
    this.statusCounts,
  });

  final int days;
  final DateTime fetchedAt;
  final SalesReport? sales;

  /// Orders created in the window, by WooCommerce status slug.
  final Map<String, int>? statusCounts;

  bool get isEmpty => sales == null && statusCounts == null;

  factory ReportsSnapshot.fromJson(Map<String, dynamic> j) {
    final sales = _map(j['sales']);
    final counts = _map(j['status_counts']);
    return ReportsSnapshot(
      days: _int(j['days']) ?? _int(j['id']) ?? 30,
      fetchedAt: DateTime.tryParse('${j['fetched_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      sales: sales == null ? null : SalesReport.fromJson(sales),
      statusCounts: counts == null ? null : {for (final e in counts.entries) e.key: _int(e.value) ?? 0},
    );
  }

  /// The row stored in the feed; the id is the window, so each window keeps its own copy.
  Map<String, dynamic> toJson() => {
        'id': days,
        'days': days,
        'fetched_at': fetchedAt.toIso8601String(),
        if (sales != null) 'sales': sales!.toJson(),
        if (statusCounts != null) 'status_counts': statusCounts,
      };
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}');
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}');
}

Map<String, dynamic>? _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];
