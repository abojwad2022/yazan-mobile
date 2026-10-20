import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

// Production wiring of the customer screens' injected functions. Routes are the web dashboard's
// (`Yazan_REST_Customers`). Customers are read-only here: nothing is ever written.

/// Loads one customer: `GET /yazan/v1/customers/{id}`.
typedef CustomerLoader = Future<Map<String, dynamic>> Function(int id);

/// Fetches one delta page of customers for a cursor.
typedef CustomersFetch = Future<DeltaPage> Function(String cursor);

/// One page of `GET /yazan-mobile/v1/sync/customers`, given its query (`cursor`, `limit`).
typedef CustomersFeedGet = Future<Map<String, dynamic>> Function(Map<String, dynamic> query);

/// `GET /yazan/v1/customers/{id}`: billing, last order, order count and lifetime spend.
CustomerLoader customerLoader(YazanApiClient client) =>
    (id) => client.getJson('/yazan/v1/customers/$id');

/// The feed endpoint over the client.
CustomersFeedGet customersFeedGet(YazanApiClient client) =>
    (query) => client.getJson('/yazan-mobile/v1/sync/customers', query: query);

/// The customer delta feed (`GET /yazan-mobile/v1/sync/customers`, admin scope, `customers.view`).
///
/// An empty cursor is the first sync (`initial`); after that the server sends keyset deltas and
/// bare tombstones (`{id, deleted: true}`) for deleted accounts. `email` and `phone` are absent
/// without `customers.view_pii`, `total_spent` without `reports.view`. A malformed body throws
/// [FormatException] (see `DeltaPage.fromJson`), which the repository counts as a failed refresh.
CustomersFetch customersFeedFetch(CustomersFeedGet get, {int limit = 50}) {
  return (cursor) async => DeltaPage.fromJson(await get({'cursor': cursor, 'limit': limit}));
}
