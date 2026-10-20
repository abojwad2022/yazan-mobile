/// The dashboard home as the staff member last saw it: what `GET /yazan/v1/dashboard/bootstrap`
/// returned, reduced to the numbers the app shows.
///
/// The server decides who may see what. A section the account may not read is OMITTED from the
/// answer (never nulled), so an absent section here means "not allowed or not available" and the
/// matching card is simply not drawn. Parsing never throws: an odd or missing field becomes
/// "absent" instead of an error.
///
/// What is kept on the phone is this reduced shape, not the raw answer: no order emails, no
/// addresses, no product rows.
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.days,
    required this.fetchedAt,
    this.sales,
    this.outOfStock,
    this.lowStock,
    this.lowThreshold,
    this.processing,
    this.onHold,
    this.recentOrders,
    this.alerts,
    this.alertBaseline,
  });

  /// Reads the bootstrap answer ([json]). [alerts] and [alertBaseline] are carried over from the
  /// caller, because they come from a different route (`/orders/alerts`).
  factory DashboardSnapshot.fromBootstrap(
    Map<String, dynamic> json, {
    required DateTime fetchedAt,
    int? requestedDays,
    NewOrdersAlert? alerts,
    int? alertBaseline,
  }) {
    final days = _int(json['days']) ?? requestedDays ?? 30;
    final stats = _map(json['stats']);
    final stockCounts = _map(json['stock']);
    // The landing page of the website falls back to the product counters for "out of stock" when
    // the account may read stats but not stock; this does the same.
    final outOfStock = _int(stockCounts?['out_of_stock_count']) ?? _int(stats?['outofstock']);
    return DashboardSnapshot(
      days: days,
      fetchedAt: fetchedAt,
      sales: SalesSummary.fromReports(_map(json['sales']), _map(json['sales2x'])),
      outOfStock: outOfStock,
      lowStock: _int(stockCounts?['low_stock_count']),
      lowThreshold: _int(stockCounts?['low_threshold']),
      processing: _total(json['processing']),
      onHold: _total(json['onHold']),
      recentOrders: _recent(json['recentOrders']),
      alerts: alerts,
      alertBaseline: alertBaseline,
    );
  }

  /// Reads the shape written by [toJson] (the on-phone copy). Never throws.
  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    final recent = json['recent_orders'];
    return DashboardSnapshot(
      days: _int(json['days']) ?? 30,
      fetchedAt: DateTime.tryParse('${json['fetched_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      sales: _map(json['sales']) == null ? null : SalesSummary.fromJson(_map(json['sales'])!),
      outOfStock: _int(json['out_of_stock']),
      lowStock: _int(json['low_stock']),
      lowThreshold: _int(json['low_threshold']),
      processing: _int(json['processing']),
      onHold: _int(json['on_hold']),
      recentOrders: recent is List
          ? [
              for (final r in recent)
                if (r is Map) RecentOrder.fromJson(Map<String, dynamic>.from(r)),
            ]
          : null,
      alerts: _map(json['alerts']) == null ? null : NewOrdersAlert.fromJson(_map(json['alerts'])!),
      alertBaseline: _int(json['alert_baseline']),
    );
  }

  /// The reporting window the sales figures cover, in days.
  final int days;

  /// When the phone received this answer (UTC or local; shown as local time).
  final DateTime fetchedAt;

  /// Sales and order totals (`reports.view`).
  final SalesSummary? sales;

  /// Product counts (`inventory.view`, or `dashboard.view` for the out-of-stock number).
  final int? outOfStock;
  final int? lowStock;
  final int? lowThreshold;

  /// Order counts by status (`orders.view`).
  final int? processing;
  final int? onHold;

  /// The newest few orders (`orders.view`).
  final List<RecentOrder>? recentOrders;

  /// Orders that arrived after [alertBaseline] (`orders.view`); null when there are none.
  final NewOrdersAlert? alerts;

  /// The order id the person has already acknowledged. New-order alerts are counted after it.
  final int? alertBaseline;

  /// True when the account may see at least one order figure.
  bool get hasOrders => processing != null || onHold != null || recentOrders != null;

  /// True when the server gave this account nothing to show: the dashboard is hidden.
  bool get isEmpty =>
      sales == null &&
      outOfStock == null &&
      lowStock == null &&
      processing == null &&
      onHold == null &&
      recentOrders == null;

  DashboardSnapshot copyWith({
    NewOrdersAlert? alerts,
    bool clearAlerts = false,
    int? alertBaseline,
  }) {
    return DashboardSnapshot(
      days: days,
      fetchedAt: fetchedAt,
      sales: sales,
      outOfStock: outOfStock,
      lowStock: lowStock,
      lowThreshold: lowThreshold,
      processing: processing,
      onHold: onHold,
      recentOrders: recentOrders,
      alerts: clearAlerts ? null : (alerts ?? this.alerts),
      alertBaseline: alertBaseline ?? this.alertBaseline,
    );
  }

  Map<String, dynamic> toJson() => {
        'days': days,
        'fetched_at': fetchedAt.toUtc().toIso8601String(),
        if (sales != null) 'sales': sales!.toJson(),
        if (outOfStock != null) 'out_of_stock': outOfStock,
        if (lowStock != null) 'low_stock': lowStock,
        if (lowThreshold != null) 'low_threshold': lowThreshold,
        if (processing != null) 'processing': processing,
        if (onHold != null) 'on_hold': onHold,
        if (recentOrders != null) 'recent_orders': [for (final r in recentOrders!) r.toJson()],
        if (alerts != null) 'alerts': alerts!.toJson(),
        if (alertBaseline != null) 'alert_baseline': alertBaseline,
      };

  /// The `total` of an orders page (the endpoint is asked for one row, to count).
  static int? _total(Object? section) {
    final m = _map(section);
    return m == null ? null : _int(m['total']);
  }

  static List<RecentOrder>? _recent(Object? section) {
    final m = _map(section);
    final items = m?['items'];
    if (items is! List) return null;
    return [
      for (final i in items)
        if (i is Map && _int(i['id']) != null) RecentOrder.fromServer(Map<String, dynamic>.from(i)),
    ];
  }
}

/// Totals for the reporting window (`GET /yazan/v1/reports/sales`).
///
/// Amounts stay the server's strings (it formats them with the store's decimals); only the
/// percentage change against the previous window is worked out here, the same way the website's
/// dashboard does it: the server is asked for twice the window and the older half of the daily
/// series is the previous period.
class SalesSummary {
  const SalesSummary({
    required this.netRevenue,
    required this.orders,
    required this.itemsSold,
    required this.averageOrder,
    required this.refunded,
    required this.symbol,
    required this.decimals,
    required this.rangeFrom,
    required this.rangeTo,
    this.todayRevenue,
    this.todayOrders,
    this.previousRevenue,
    this.previousOrders,
  });

  /// [sales] is the `sales` section, [sales2x] the same report over twice the window.
  static SalesSummary? fromReports(Map<String, dynamic>? sales, Map<String, dynamic>? sales2x) {
    if (sales == null) return null;
    final totals = _map(sales['totals']) ?? const <String, dynamic>{};
    final currency = _map(sales['currency']) ?? const <String, dynamic>{};
    final range = _map(sales['range']) ?? const <String, dynamic>{};
    final series = _series(sales['series']);
    final rangeTo = _str(range['to']);

    // "Today" is the last day of the window the server cut (site time), not the phone's date.
    _Day? today;
    for (final d in series) {
      if (d.date == rangeTo) today = d;
    }
    today ??= series.isEmpty ? null : series.last;

    double? previousRevenue;
    int? previousOrders;
    if (sales2x != null) {
      final longer = _series(sales2x['series']);
      final keep = longer.length - series.length;
      if (keep > 0) {
        final previous = longer.take(keep);
        previousRevenue = previous.fold<double>(0, (a, d) => a + d.total);
        previousOrders = previous.fold<int>(0, (a, d) => a + d.orders);
      }
    }

    return SalesSummary(
      netRevenue: _str(totals['net_revenue'], '0'),
      orders: _int(totals['orders']) ?? 0,
      itemsSold: _int(totals['items_sold']) ?? 0,
      averageOrder: _str(totals['average_order'], '0'),
      refunded: _str(totals['refunded'], '0'),
      symbol: _str(currency['symbol']),
      decimals: (_int(currency['decimals']) ?? 2).clamp(0, 6).toInt(),
      rangeFrom: _str(range['from']),
      rangeTo: rangeTo,
      todayRevenue: today?.total,
      todayOrders: today?.orders,
      previousRevenue: previousRevenue,
      previousOrders: previousOrders,
    );
  }

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    return SalesSummary(
      netRevenue: _str(json['net_revenue'], '0'),
      orders: _int(json['orders']) ?? 0,
      itemsSold: _int(json['items_sold']) ?? 0,
      averageOrder: _str(json['average_order'], '0'),
      refunded: _str(json['refunded'], '0'),
      symbol: _str(json['symbol']),
      decimals: (_int(json['decimals']) ?? 2).clamp(0, 6).toInt(),
      rangeFrom: _str(json['from']),
      rangeTo: _str(json['to']),
      todayRevenue: _double(json['today_revenue']),
      todayOrders: _int(json['today_orders']),
      previousRevenue: _double(json['previous_revenue']),
      previousOrders: _int(json['previous_orders']),
    );
  }

  final String netRevenue;
  final int orders;
  final int itemsSold;
  final String averageOrder;
  final String refunded;

  /// The store's currency symbol, as the server sends it (it has no code here).
  final String symbol;
  final int decimals;
  final String rangeFrom;
  final String rangeTo;

  /// The last day of the window (net of refunds), and its order count.
  final double? todayRevenue;
  final int? todayOrders;

  /// The window before this one, when the server answered the longer report.
  final double? previousRevenue;
  final int? previousOrders;

  /// Percent change of net revenue against the previous window; null without a base to compare.
  double? get revenueDelta => _delta(double.tryParse(netRevenue), previousRevenue);

  /// Percent change of the order count against the previous window.
  double? get ordersDelta => _delta(orders.toDouble(), previousOrders?.toDouble());

  Map<String, dynamic> toJson() => {
        'net_revenue': netRevenue,
        'orders': orders,
        'items_sold': itemsSold,
        'average_order': averageOrder,
        'refunded': refunded,
        'symbol': symbol,
        'decimals': decimals,
        'from': rangeFrom,
        'to': rangeTo,
        if (todayRevenue != null) 'today_revenue': todayRevenue,
        if (todayOrders != null) 'today_orders': todayOrders,
        if (previousRevenue != null) 'previous_revenue': previousRevenue,
        if (previousOrders != null) 'previous_orders': previousOrders,
      };

  static double? _delta(double? current, double? previous) {
    if (current == null || previous == null || previous == 0) return null;
    return (current - previous) / previous * 100;
  }

  static List<_Day> _series(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final r in raw)
        if (r is Map)
          _Day(_str(r['date']), _double(r['total']) ?? 0.0, _int(r['orders']) ?? 0),
    ];
  }
}

class _Day {
  const _Day(this.date, this.total, this.orders);

  final String date;
  final double total;
  final int orders;
}

/// One of the newest orders (`recentOrders` of the bootstrap answer), without the email.
class RecentOrder {
  const RecentOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.customer,
    required this.total,
    required this.date,
  });

  factory RecentOrder.fromServer(Map<String, dynamic> json) {
    final id = _int(json['id']) ?? 0;
    return RecentOrder(
      id: id,
      number: _str(json['number'], '$id'),
      status: _str(json['status']),
      customer: _str(json['customer']).trim(),
      total: _str(json['total_html'], _str(json['total'])),
      date: _str(json['date']),
    );
  }

  factory RecentOrder.fromJson(Map<String, dynamic> json) {
    final id = _int(json['id']) ?? 0;
    return RecentOrder(
      id: id,
      number: _str(json['number'], '$id'),
      status: _str(json['status']),
      customer: _str(json['customer']),
      total: _str(json['total']),
      date: _str(json['date']),
    );
  }

  final int id;
  final String number;

  /// WooCommerce status slug without the `wc-` prefix.
  final String status;
  final String customer;

  /// The total as the server formats it, symbol included ("$770.00").
  final String total;
  final String date;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'status': status,
        'customer': customer,
        'total': total,
        'date': date,
      };
}

/// Orders that arrived after the last one the person acknowledged (`GET /orders/alerts?since=`).
class NewOrdersAlert {
  const NewOrdersAlert({required this.count, required this.latest, required this.orders});

  /// Null when the server reports nothing new.
  static NewOrdersAlert? fromServer(Map<String, dynamic> json) {
    final count = _int(json['count']) ?? 0;
    if (count <= 0) return null;
    return NewOrdersAlert.fromJson(json);
  }

  factory NewOrdersAlert.fromJson(Map<String, dynamic> json) {
    final raw = json['orders'];
    return NewOrdersAlert(
      count: _int(json['count']) ?? 0,
      latest: _int(json['latest']) ?? 0,
      orders: [
        if (raw is List)
          for (final o in raw)
            if (o is Map) RecentOrder.fromJson(Map<String, dynamic>.from(o)),
      ],
    );
  }

  final int count;

  /// The newest order id the server knows; becomes the baseline once the alert is acknowledged.
  final int latest;

  /// A short summary of the newest few.
  final List<RecentOrder> orders;

  Map<String, dynamic> toJson() => {
        'count': count,
        'latest': latest,
        'orders': [for (final o in orders) o.toJson()],
      };
}

Map<String, dynamic>? _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

String _str(Object? v, [String fallback = '']) => v == null ? fallback : '$v';

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(_str(v));
}

double? _double(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse(_str(v));
}
