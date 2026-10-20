import 'package:yazan_api_client/yazan_api_client.dart';

// Production wiring of the coupon screens' injected functions. Routes are the web dashboard's
// (`Yazan_REST_Coupons`, namespace `yazan/v1`). That route does not take `If-Match` (coupons have
// no version token), so a write is protected by its `Idempotency-Key` only: last write wins.

/// One page of `GET /yazan/v1/coupons` (`items`, `total_pages`, ...).
typedef CouponsFetch = Future<Map<String, dynamic>> Function(int page);

/// `GET /yazan/v1/coupons/{id}`: the full coupon.
typedef CouponLoader = Future<Map<String, dynamic>> Function(int id);

/// `PUT /yazan/v1/coupons/{id}` with only the fields being changed and an `Idempotency-Key`.
/// Throws [ApiError] for a server answer; any other exception means "no network".
typedef CouponWriter = Future<Map<String, dynamic>> Function(
  int id,
  Map<String, dynamic> fields, {
  required String idempotencyKey,
});

/// How many coupons one page asks for (the route caps it at 100).
const int couponsPerPage = 100;

CouponsFetch couponsFetch(YazanApiClient client) => (page) =>
    client.getJson('/yazan/v1/coupons', query: {'page': page, 'per_page': couponsPerPage});

CouponLoader couponLoader(YazanApiClient client) =>
    (id) => client.getJson('/yazan/v1/coupons/$id');

CouponWriter couponWriter(YazanApiClient client) => (
      int id,
      Map<String, dynamic> fields, {
      required String idempotencyKey,
    }) =>
        client.sendJson('PUT', '/yazan/v1/coupons/$id', data: fields, idempotencyKey: idempotencyKey);
