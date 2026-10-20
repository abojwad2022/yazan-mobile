import 'dart:convert';

import 'package:yazan_store/src/cart/store_api.dart';

/// A realistic `GET /wc/store/v1/cart` response (WooCommerce 10.x shape, trimmed of extensions).
const storeCartJson = r'''
{
  "items": [
    {
      "key": "c51ce410c124a10e0db5e4b97fc2af39",
      "id": 13,
      "type": "simple",
      "quantity": 2,
      "quantity_limits": {"minimum": 1, "maximum": 5, "multiple_of": 1, "editable": true},
      "name": "Carnelian &amp; Silver Ring",
      "short_description": "<p>Yemeni agate in sterling silver.</p>",
      "description": "",
      "sku": "YZ-013",
      "low_stock_remaining": 3,
      "backorders_allowed": false,
      "show_backorder_badge": false,
      "sold_individually": false,
      "permalink": "https://yazan.test/product/carnelian-silver-ring/",
      "images": [
        {
          "id": 101,
          "src": "https://yazan.test/wp-content/uploads/ring-13.jpg",
          "thumbnail": "https://yazan.test/wp-content/uploads/ring-13-300x300.jpg",
          "srcset": "",
          "sizes": "",
          "name": "ring-13",
          "alt": ""
        }
      ],
      "variation": [],
      "item_data": [],
      "prices": {
        "price": "12000",
        "regular_price": "12000",
        "sale_price": "12000",
        "price_range": null,
        "currency_code": "USD",
        "currency_symbol": "$",
        "currency_minor_unit": 2,
        "currency_decimal_separator": ".",
        "currency_thousand_separator": ",",
        "currency_prefix": "$",
        "currency_suffix": "",
        "raw_prices": {"precision": 6, "price": "120000000", "regular_price": "120000000", "sale_price": "120000000"}
      },
      "totals": {
        "line_subtotal": "24000",
        "line_subtotal_tax": "0",
        "line_total": "24000",
        "line_total_tax": "0",
        "currency_code": "USD",
        "currency_symbol": "$",
        "currency_minor_unit": 2,
        "currency_decimal_separator": ".",
        "currency_thousand_separator": ",",
        "currency_prefix": "$",
        "currency_suffix": ""
      },
      "catalog_visibility": "visible",
      "extensions": {}
    },
    {
      "key": "aab3238922bcc25a6f606eb525ffdc56",
      "id": 14,
      "type": "simple",
      "quantity": 1,
      "quantity_limits": {"minimum": 1, "maximum": 1, "multiple_of": 1, "editable": true},
      "name": "Aqeeq Signet &#8211; Black",
      "images": [],
      "variation": [],
      "item_data": [],
      "prices": {
        "price": "9000",
        "regular_price": "11000",
        "sale_price": "9000",
        "currency_code": "USD",
        "currency_minor_unit": 2
      },
      "totals": {
        "line_subtotal": "9000",
        "line_subtotal_tax": "0",
        "line_total": "9000",
        "line_total_tax": "0",
        "currency_code": "USD",
        "currency_minor_unit": 2
      },
      "extensions": {}
    }
  ],
  "coupons": [],
  "fees": [],
  "totals": {
    "total_items": "33000",
    "total_items_tax": "0",
    "total_fees": "0",
    "total_fees_tax": "0",
    "total_discount": "0",
    "total_discount_tax": "0",
    "total_shipping": "1000",
    "total_shipping_tax": "0",
    "total_price": "34000",
    "total_tax": "0",
    "tax_lines": [],
    "currency_code": "USD",
    "currency_symbol": "$",
    "currency_minor_unit": 2,
    "currency_decimal_separator": ".",
    "currency_thousand_separator": ",",
    "currency_prefix": "$",
    "currency_suffix": ""
  },
  "shipping_address": {
    "first_name": "Yazan",
    "last_name": "Ali",
    "company": "",
    "address_1": "12 Market Street",
    "address_2": "",
    "city": "Dearborn",
    "state": "MI",
    "postcode": "48126",
    "country": "US",
    "phone": "+13135550100"
  },
  "billing_address": {
    "first_name": "Yazan",
    "last_name": "Ali",
    "company": "",
    "address_1": "12 Market Street",
    "address_2": "",
    "city": "Dearborn",
    "state": "MI",
    "postcode": "48126",
    "country": "US",
    "email": "customer@yazan.test",
    "phone": "+13135550100"
  },
  "needs_payment": true,
  "needs_shipping": true,
  "payment_requirements": ["products"],
  "has_calculated_shipping": true,
  "shipping_rates": [
    {
      "package_id": 0,
      "name": "Shipment 1",
      "destination": {"address_1": "12 Market Street", "city": "Dearborn", "state": "MI", "postcode": "48126", "country": "US"},
      "items": [{"key": "c51ce410c124a10e0db5e4b97fc2af39", "name": "Carnelian &amp; Silver Ring", "quantity": 2}],
      "shipping_rates": [
        {
          "rate_id": "flat_rate:1",
          "name": "Flat rate",
          "price": "1000",
          "taxes": "0",
          "selected": true,
          "currency_code": "USD",
          "currency_minor_unit": 2
        }
      ]
    }
  ],
  "items_count": 3,
  "items_weight": 0,
  "cross_sells": [],
  "errors": [],
  "payment_methods": ["cod"],
  "extensions": {}
}
''';

/// The fixture as a fresh mutable map; `images: false` drops item images (no network in widget tests).
Map<String, dynamic> storeCart({bool images = true}) {
  final m = jsonDecode(storeCartJson) as Map<String, dynamic>;
  if (!images) {
    for (final item in m['items'] as List<dynamic>) {
      (item as Map<String, dynamic>)['images'] = <Object>[];
    }
  }
  return m;
}

/// A `POST /wc/store/v1/checkout` success for cash on delivery.
Map<String, dynamic> checkoutSuccess() => {
      'order_id': 1042,
      'status': 'processing',
      'order_key': 'wc_order_abc123',
      'order_number': '1042',
      'customer_note': '',
      'customer_id': 7,
      'billing_address': <String, dynamic>{},
      'shipping_address': <String, dynamic>{},
      'payment_method': 'cod',
      'payment_result': {
        'payment_status': 'success',
        'payment_details': <Object>[],
        'redirect_url': 'https://yazan.test/checkout/order-received/1042/?key=wc_order_abc123',
      },
    };

/// One captured request.
class SentRequest {
  SentRequest(this.method, this.path, this.body, this.headers);

  final String method;
  final String path;
  final Object? body;
  final Map<String, String> headers;
}

/// Answers a request: return a response, or throw to simulate the network failing.
typedef FakeHandler = StoreResponse Function(SentRequest request);

/// In-memory [StoreTransport] that records every request.
class FakeTransport {
  FakeTransport(this.handler);

  FakeHandler handler;
  final List<SentRequest> requests = [];

  Future<StoreResponse> call(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final r = SentRequest(method, path, body, Map<String, String>.of(headers));
    requests.add(r);
    return handler(r);
  }
}

StoreResponse ok(Map<String, dynamic> body, {Map<String, String> headers = const {}}) =>
    (status: 200, body: body, headers: headers);

StoreResponse failResponse(int status, String code, String message) =>
    (status: status, body: <String, dynamic>{'code': code, 'message': message, 'data': {'status': status}}, headers: const <String, String>{});
