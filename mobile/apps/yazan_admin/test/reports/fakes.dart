import 'package:yazan_admin/src/reports/reports_repository.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

/// The moment the fake phone clock reads when an answer arrives.
final DateTime reportsNow = DateTime(2026, 10, 20, 14, 5);

/// `GET /yazan/v1/reports/sales`: 450.00 net over 3 orders, one top product, 10.00 refunded.
Map<String, dynamic> salesAnswer({double scale = 1}) => {
      'range': {'from': '2026-10-18', 'to': '2026-10-20'},
      'totals': {
        'net_revenue': '450.00',
        'gross_revenue': '460.00',
        'refunded': '10.00',
        'orders': 3,
        'refunded_orders': 1,
        'items_sold': 5,
        'average_order': '150.00',
      },
      'series': [
        {'date': '2026-10-18', 'total': 100.0 * scale, 'orders': 1},
        {'date': '2026-10-19', 'total': 199.5 * scale, 'orders': 1},
        {'date': '2026-10-20', 'total': 150.5 * scale, 'orders': 1},
      ],
      'top': [
        {'product_id': 7, 'name': 'Agate ring', 'thumb': '', 'qty': 3, 'revenue': '300.00'},
        {'product_id': 9, 'name': 'Silver band', 'thumb': '', 'qty': 2, 'revenue': '150.00'},
      ],
      'currency': {'symbol': r'$', 'decimals': 2},
    };

/// A scripted stand-in for the reports routes. No network anywhere.
class FakeReportsServer {
  Map<String, dynamic> sales = salesAnswer();

  /// Order counts by status; a status not listed counts 0.
  Map<String, int> counts = {'processing': 4, 'completed': 12, 'refunded': 1};

  /// When set, the sales route throws it (and keeps throwing until cleared).
  Object? salesFailure;

  /// When set, the order-count route throws it.
  Object? countFailure;

  final List<int> daysAsked = [];

  Future<Map<String, dynamic>> fetchSales(int days) async {
    daysAsked.add(days);
    if (salesFailure != null) throw salesFailure!;
    return sales;
  }

  Future<int> fetchCount(String status, int days) async {
    if (countFailure != null) throw countFailure!;
    return counts[status] ?? 0;
  }

  ReportsRepository repository({FeedStore? store, int days = 30}) => ReportsRepository(
        fetchSales: fetchSales,
        fetchStatusCount: fetchCount,
        store: store,
        clock: () => reportsNow,
        days: days,
      );
}
