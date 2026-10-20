import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

// Production wiring of the customer screens' injected functions. Routes are the web dashboard's
// (`Yazan_REST_Customers`). Customers are read-only here: nothing is ever written.

/// Loads one customer: `GET /yazan/v1/customers/{id}`.
typedef CustomerLoader = Future<Map<String, dynamic>> Function(int id);

/// Fetches one delta page of customers for a cursor.
typedef CustomersFetch = Future<DeltaPage> Function(String cursor);

/// One page of `GET /yazan/v1/customers`, given its query.
typedef CustomersPageGet = Future<Map<String, dynamic>> Function(Map<String, dynamic> query);

/// `GET /yazan/v1/customers/{id}`: billing, last order, order count and lifetime spend.
CustomerLoader customerLoader(YazanApiClient client) =>
    (id) => client.getJson('/yazan/v1/customers/$id');

/// The list endpoint over the client.
CustomersPageGet customersPageGet(YazanApiClient client) =>
    (query) => client.getJson('/yazan/v1/customers', query: query);

/// Presents the numbered pages of `GET /yazan/v1/customers` as a delta feed, so the list reads
/// through the same `pullFeed` + `FeedStore` path as orders.
///
/// The server has no `/yazan-mobile/v1/sync/customers` feed yet, so every refresh is a full
/// snapshot: the cursor is the next page number while a pull is in progress and empty once the last
/// page has been read, which makes the next refresh start again from page 1 as an `initial` page
/// (the store replaces its rows, so a deleted customer disappears). A pull that is cut short
/// resumes at the page it stopped on. Only customers (role `customer`) are listed, never staff.
CustomersFetch pagedCustomersFetch(CustomersPageGet get, {int limit = 50}) {
  return (cursor) async {
    final parsed = int.tryParse(cursor) ?? 1;
    final page = parsed < 1 ? 1 : parsed;
    final body = await get({
      'page': page,
      'per_page': limit,
      'stats': '1',
      'role': 'customer',
    });
    final raw = body['items'];
    final totalPages = _int(body['total_pages']) ?? 1;
    final hasMore = page < totalPages;
    return DeltaPage(
      items: [
        if (raw is List)
          for (final i in raw)
            if (i is Map && i['id'] is int) Map<String, dynamic>.from(i),
      ],
      cursor: hasMore ? '${page + 1}' : '',
      hasMore: hasMore,
      initial: page == 1,
    );
  };
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}');
}
