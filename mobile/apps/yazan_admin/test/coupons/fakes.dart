import 'package:yazan_admin/src/coupons/coupon_api.dart';

/// Rows as `GET /yazan/v1/coupons` sends them (`items[]`).
const List<Map<String, dynamic>> couponRows = [
  {
    'id': 21,
    'code': 'SPRING20',
    'description': 'Spring sale',
    'discount_type': 'percent',
    'amount': '20',
    'amount_html': '20%',
    'usage_count': 3,
    'usage_limit': 10,
    'expires': '2099-12-31',
    'expired': false,
    'free_shipping': false,
  },
  {
    'id': 22,
    'code': 'OLD5',
    'description': 'Finished promotion',
    'discount_type': 'fixed_cart',
    'amount': '5',
    'amount_html': r'$5.00',
    'usage_count': 40,
    'usage_limit': 0,
    'expires': '2020-01-01',
    'expired': true,
    'free_shipping': false,
  },
  {
    'id': 23,
    'code': 'RAMADAN',
    'description': 'خصم رمضان',
    'discount_type': 'percent',
    'amount': '15',
    'amount_html': '15%',
    'usage_count': 0,
    'usage_limit': 0,
    'expires': '',
    'expired': false,
    'free_shipping': true,
  },
];

/// One page of the list route.
Map<String, dynamic> couponsPage(List<Map<String, dynamic>> items, {int totalPages = 1}) =>
    {'items': items, 'total': items.length, 'total_pages': totalPages, 'page': 1, 'per_page': 100};

/// One recorded coupon write.
class CouponWrite {
  CouponWrite(this.id, this.fields, this.key);

  final int id;
  final Map<String, dynamic> fields;
  final String key;
}

/// An in-memory stand-in for `GET/PUT /yazan/v1/coupons/{id}`. No network anywhere.
class FakeCouponServer {
  String code = 'SPRING20';
  String type = 'percent';
  String amount = '20';
  String expires = '2099-12-31';
  int used = 3;
  int limit = 10;

  /// When set, `load` throws it.
  Exception? loadError;

  /// Thrown by the next writes, in order; `null` means "accept".
  final List<Exception?> writeFailures = [];
  final List<CouponWrite> writes = [];

  /// A server that answers 200 but ignores the fields.
  bool ignoreWrites = false;

  Map<String, dynamic> body() => {
        'id': 21,
        'code': code,
        'description': 'Spring sale',
        'discount_type': type,
        'amount': amount,
        'amount_html': type == 'percent' ? '$amount%' : '$amount.00',
        'date_expires': expires,
        'free_shipping': false,
        'usage_count': used,
        'usage_limit': limit,
      };

  CouponLoader get loader => (id) async {
        final err = loadError;
        if (err != null) throw err;
        return body();
      };

  CouponWriter get writer => (id, fields, {required String idempotencyKey}) async {
        writes.add(CouponWrite(id, Map<String, dynamic>.from(fields), idempotencyKey));
        final failure = writeFailures.isEmpty ? null : writeFailures.removeAt(0);
        if (failure != null) throw failure;
        if (!ignoreWrites) {
          if (fields.containsKey('amount')) amount = '${fields['amount']}';
          if (fields.containsKey('date_expires')) expires = '${fields['date_expires']}';
        }
        return body();
      };
}
