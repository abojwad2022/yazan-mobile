import 'package:yazan_api_client/yazan_api_client.dart';

// Production wiring of the reports page's injected functions. Routes are the web dashboard's
// (`Yazan_REST_Reports::sales`, `Yazan_REST_Orders::index`). Nothing is ever written.

/// `GET /yazan/v1/reports/sales?days=` (needs `reports.view`).
typedef SalesFetch = Future<Map<String, dynamic>> Function(int days);

/// How many orders were created in the last `days` days with `status`
/// (`GET /yazan/v1/orders?status=&per_page=1&date_from=&date_to=`, needs `orders.view`).
typedef StatusCountFetch = Future<int> Function(String status, int days);

SalesFetch salesFetch(YazanApiClient client) =>
    (days) => client.getJson('/yazan/v1/reports/sales', query: {'days': days});

StatusCountFetch statusCountFetch(YazanApiClient client, {DateTime Function()? clock}) {
  final now = clock ?? DateTime.now;
  return (status, days) async {
    final today = now();
    final from = today.subtract(Duration(days: days));
    final body = await client.getJson('/yazan/v1/orders', query: {
      'status': status,
      'per_page': 1,
      'date_from': _day(from),
      'date_to': _day(today),
    });
    final total = body['total'];
    return total is num ? total.toInt() : int.tryParse('${total ?? 0}') ?? 0;
  };
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
