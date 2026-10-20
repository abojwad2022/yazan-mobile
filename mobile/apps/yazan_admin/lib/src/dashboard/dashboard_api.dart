import 'package:yazan_api_client/yazan_api_client.dart';

// Production wiring of the dashboard's injected functions. Routes are the web dashboard's
// (`Yazan_REST_Dashboard_Bootstrap`, `Yazan_REST_Orders::alerts`). Nothing is ever written.

/// `GET /yazan/v1/dashboard/bootstrap?days=`: every landing-page section the account may read.
/// A section the account may not read is left out of the answer.
typedef DashboardFetch = Future<Map<String, dynamic>> Function(int days);

/// `GET /yazan/v1/orders/alerts[?since=]`. Without `since` the server only reports the newest
/// order id (it seeds the baseline); with it, the orders that arrived after that id.
typedef AlertsFetch = Future<Map<String, dynamic>> Function(int? since);

DashboardFetch dashboardFetch(YazanApiClient client) =>
    (days) => client.getJson('/yazan/v1/dashboard/bootstrap', query: {'days': days});

AlertsFetch alertsFetch(YazanApiClient client) => (since) => client.getJson(
      '/yazan/v1/orders/alerts',
      query: since == null ? null : {'since': since},
    );
