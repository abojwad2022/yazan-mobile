import 'package:yazan_domain/yazan_domain.dart';

import '../cart/cart.dart' show plainText;
import '../json_read.dart';

/// "USD 90.00" from the server's decimal string, or "USD <raw>" when it is not a plain amount.
/// Empty when the server sent nothing. Display only: the server decided every figure.
String amountText(Object? value, String currency) {
  if (value == null) return '';
  final raw = value.toString().trim();
  if (raw.isEmpty) return '';
  try {
    return Money.parse(raw, currency: currency).toString();
  } on FormatException {
    return '$currency $raw';
  }
}

bool _isZero(Object? value) {
  if (value == null) return true;
  final n = num.tryParse(value.toString().trim());
  return n != null && n == 0;
}

/// `GET /yazan-mobile/v1/me/profile`.
class Profile {
  const Profile({
    required this.id,
    required this.email,
    this.firstName = '',
    this.lastName = '',
    this.displayName = '',
    this.phone = '',
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: asInt(j['id']) ?? 0,
        email: asStr(j['email']),
        firstName: asStr(j['first_name']),
        lastName: asStr(j['last_name']),
        displayName: asStr(j['display_name']),
        phone: asStr(j['phone']),
      );

  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final String displayName;
  final String phone;

  /// First and last name, or the display name when the customer has not set them.
  String get name {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : displayName;
  }
}

/// One row of `GET /me/orders` (also the head of an order's detail).
class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.label,
    required this.total,
    required this.currency,
    required this.count,
    this.created,
    this.image,
  });

  factory OrderSummary.fromJson(Map<String, dynamic> j) {
    final cur = asStr(j['currency']);
    final currency = cur.isEmpty ? 'USD' : cur;
    final image = asStr(j['image']);
    final id = asInt(j['id']) ?? 0;
    final number = asStr(j['number']);
    return OrderSummary(
      id: id,
      number: number.isEmpty ? '$id' : number,
      status: asStr(j['status']),
      label: asStr(j['label']),
      total: amountText(j['total'], currency),
      currency: currency,
      count: asInt(j['count']) ?? 0,
      created: DateTime.tryParse(asStr(j['created'])),
      image: image.isEmpty ? null : image,
    );
  }

  final int id;
  final String number;

  /// WooCommerce status slug without the `wc-` prefix: `processing`, `completed`...
  final String status;

  /// The server's own name for the status (used when the app has no translation for it).
  final String label;
  final String total;
  final String currency;
  final int count;
  final DateTime? created;
  final String? image;
}

/// One page of `GET /me/orders`.
class OrderPage {
  const OrderPage({required this.orders, required this.total, required this.pages});

  factory OrderPage.fromJson(Map<String, dynamic> j) => OrderPage(
        orders: [
          for (final o in asList(j['orders']))
            if (o is Map) OrderSummary.fromJson(asMap(o)),
        ],
        total: asInt(j['total']) ?? 0,
        pages: asInt(j['pages']) ?? 0,
      );

  final List<OrderSummary> orders;
  final int total;
  final int pages;
}

class OrderLine {
  const OrderLine({required this.name, required this.quantity, required this.total, this.image});

  factory OrderLine.fromJson(Map<String, dynamic> j, String currency) {
    final image = asStr(j['image']);
    return OrderLine(
      name: plainText(asStr(j['name'])),
      quantity: asInt(j['quantity']) ?? 0,
      total: amountText(j['total'], currency),
      image: image.isEmpty ? null : image,
    );
  }

  final String name;
  final int quantity;
  final String total;
  final String? image;
}

class OrderShipment {
  const OrderShipment({required this.carrier, required this.number});

  final String carrier;
  final String number;
}

/// `GET /me/orders/{id}`: read only.
class OrderDetail {
  const OrderDetail({
    required this.summary,
    this.items = const [],
    this.subtotal = '',
    this.shipping = '',
    this.tax = '',
    this.discount = '',
    this.paymentMethod = '',
    this.address = const [],
    this.shipments = const [],
  });

  factory OrderDetail.fromJson(Map<String, dynamic> j) {
    final summary = OrderSummary.fromJson(j);
    final currency = summary.currency;
    var address = _addressLines(j['shipping']);
    if (address.isEmpty) address = _addressLines(j['billing']);
    final shipments = <OrderShipment>[];
    for (final s in asList(j['shipments'])) {
      final m = asMap(s);
      final number = asStr(m['number']);
      if (number.isNotEmpty) {
        shipments.add(OrderShipment(carrier: asStr(m['label']), number: number));
      }
    }
    return OrderDetail(
      summary: summary,
      items: [
        for (final i in asList(j['items']))
          if (i is Map) OrderLine.fromJson(asMap(i), currency),
      ],
      subtotal: amountText(j['subtotal'], currency),
      shipping: _isZero(j['shipping_total']) ? '' : amountText(j['shipping_total'], currency),
      tax: _isZero(j['tax_total']) ? '' : amountText(j['tax_total'], currency),
      discount: _isZero(j['discount_total']) ? '' : amountText(j['discount_total'], currency),
      paymentMethod: asStr(j['payment_method']),
      address: address,
      shipments: shipments,
    );
  }

  final OrderSummary summary;
  final List<OrderLine> items;
  final String subtotal;

  /// Empty when the amount is zero or missing (the screen then hides the row).
  final String shipping;
  final String tax;
  final String discount;
  final String paymentMethod;

  /// Delivery address, one entry per printed line.
  final List<String> address;
  final List<OrderShipment> shipments;
}

List<String> _addressLines(Object? raw) {
  final a = asMap(raw);
  String field(String key) => asStr(a[key]).trim();
  final first = field('first_name');
  final last = field('last_name');
  final name = '$first $last'.trim();
  final cityLine = [field('city'), field('state'), field('postcode')]
      .where((s) => s.isNotEmpty)
      .join(' ');
  final lines = <String>[
    name,
    field('company'),
    field('address_1'),
    field('address_2'),
    cityLine,
    field('country'),
  ];
  return lines.where((s) => s.isNotEmpty).toList();
}
