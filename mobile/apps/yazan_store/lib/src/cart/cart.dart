import 'package:yazan_domain/yazan_domain.dart';

/// Parses a WooCommerce Store API amount into [Money].
///
/// The Store API sends prices as integer strings in the currency's minor unit (e.g. "24000" with
/// `currency_minor_unit: 2` is 240.00). [Money] always holds hundredths, so other minor units are
/// rescaled: 0 decimals are multiplied up exactly; 3 decimals are rounded half away from zero to
/// the nearest hundredth (display only - the server still decides every total).
Money? storeMoney(Object? value, {required String currency, required int minorUnit}) {
  int? raw;
  if (value is int) {
    raw = value;
  } else if (value is String) {
    raw = int.tryParse(value.trim());
  }
  if (raw == null) return null;
  return Money(_toHundredths(raw, minorUnit), currency);
}

int _toHundredths(int raw, int minorUnit) {
  if (minorUnit == 2) return raw;
  if (minorUnit < 2) {
    var factor = 1;
    for (var i = minorUnit; i < 2; i++) {
      factor *= 10;
    }
    return raw * factor;
  }
  var divisor = 1;
  for (var i = 2; i < minorUnit; i++) {
    divisor *= 10;
  }
  final rounded = (raw.abs() + divisor ~/ 2) ~/ divisor;
  return raw < 0 ? -rounded : rounded;
}

/// Strips tags and decodes the HTML entities the Store API leaves in names and messages.
String plainText(String html) {
  final noTags = html.replaceAll(RegExp(r'<[^>]*>'), '');
  return noTags.replaceAllMapped(
    RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp);'),
    (m) {
      final entity = m.group(1) ?? '';
      int? code;
      if (entity.startsWith('#x') || entity.startsWith('#X')) {
        code = int.tryParse(entity.substring(2), radix: 16);
      } else if (entity.startsWith('#')) {
        code = int.tryParse(entity.substring(1));
      } else {
        switch (entity) {
          case 'amp':
            return '&';
          case 'lt':
            return '<';
          case 'gt':
            return '>';
          case 'quot':
            return '"';
          case 'apos':
            return "'";
          case 'nbsp':
            return ' ';
        }
      }
      if (code == null || code < 0 || code > 0x10FFFF) return m.group(0) ?? '';
      return String.fromCharCode(code);
    },
  ).trim();
}

Map<String, dynamic> _map(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map<String, dynamic>((k, val) => MapEntry('$k', val));
  return const <String, dynamic>{};
}

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String _currency(Map<String, dynamic> totals) {
  final c = totals['currency_code'];
  return c is String && c.isNotEmpty ? c : 'USD';
}

int _minorUnit(Map<String, dynamic> totals) => _int(totals['currency_minor_unit']) ?? 2;

Map<String, String> _address(Object? v) {
  final m = _map(v);
  return {
    for (final e in m.entries)
      if (e.value is String) e.key: e.value as String,
  };
}

/// One line of the server cart.
class CartItem {
  const CartItem({
    required this.key,
    required this.id,
    required this.name,
    required this.quantity,
    required this.lineTotal,
    this.lineSubtotal,
    this.imageUrl,
    this.minQuantity = 1,
    this.maxQuantity,
    this.editable = true,
  });

  factory CartItem.fromJson(Map<String, dynamic> j) {
    final totals = _map(j['totals']);
    final currency = _currency(totals);
    final unit = _minorUnit(totals);
    final limits = _map(j['quantity_limits']);
    String? image;
    final images = j['images'];
    if (images is List && images.isNotEmpty) {
      final thumb = _map(images.first)['thumbnail'];
      if (thumb is String && thumb.isNotEmpty) image = thumb;
    }
    return CartItem(
      key: _str(j['key']),
      id: _int(j['id']) ?? 0,
      name: plainText(_str(j['name'])),
      quantity: _int(j['quantity']) ?? 0,
      lineTotal: storeMoney(totals['line_total'], currency: currency, minorUnit: unit) ??
          Money(0, currency),
      lineSubtotal: storeMoney(totals['line_subtotal'], currency: currency, minorUnit: unit),
      imageUrl: image,
      minQuantity: _int(limits['minimum']) ?? 1,
      maxQuantity: _int(limits['maximum']),
      editable: limits['editable'] != false,
    );
  }

  /// Store API cart item key, used by update-item and remove-item.
  final String key;

  /// Product (or variation) id.
  final int id;
  final String name;
  final int quantity;

  /// Line total after discounts, before tax, as the server computed it.
  final Money lineTotal;
  final Money? lineSubtotal;
  final String? imageUrl;
  final int minQuantity;
  final int? maxQuantity;
  final bool editable;

  bool get canIncrease {
    final max = maxQuantity;
    return editable && (max == null || quantity < max);
  }
}

/// Cart totals exactly as the server reported them. The app never adds them up itself.
class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    this.shipping,
  });

  factory CartTotals.fromJson(Map<String, dynamic> j) {
    final currency = _currency(j);
    final unit = _minorUnit(j);
    Money money(String key) =>
        storeMoney(j[key], currency: currency, minorUnit: unit) ?? Money(0, currency);
    return CartTotals(
      subtotal: money('total_items'),
      discount: money('total_discount'),
      tax: money('total_tax'),
      total: money('total_price'),
      // Null until the customer's address lets the server calculate shipping.
      shipping: storeMoney(j['total_shipping'], currency: currency, minorUnit: unit),
    );
  }

  static const zero = CartTotals(
    subtotal: Money(0),
    discount: Money(0),
    tax: Money(0),
    total: Money(0),
  );

  final Money subtotal;
  final Money discount;
  final Money tax;
  final Money total;
  final Money? shipping;
}

/// The WooCommerce Store API cart (`/wc/store/v1/cart`).
class Cart {
  const Cart({
    required this.items,
    required this.itemsCount,
    required this.totals,
    this.errors = const [],
    this.paymentMethods = const [],
    this.needsShipping = true,
    this.billing = const {},
    this.shipping = const {},
  });

  factory Cart.fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'];
    final items = <CartItem>[
      if (rawItems is List)
        for (final i in rawItems)
          if (i is Map) CartItem.fromJson(_map(i)),
    ];
    final errors = <String>[];
    final rawErrors = j['errors'];
    if (rawErrors is List) {
      for (final e in rawErrors) {
        final message = plainText(_str(_map(e)['message']));
        if (message.isNotEmpty) errors.add(message);
      }
    }
    final rawMethods = j['payment_methods'];
    var count = 0;
    for (final i in items) {
      count += i.quantity;
    }
    return Cart(
      items: items,
      itemsCount: _int(j['items_count']) ?? count,
      totals: CartTotals.fromJson(_map(j['totals'])),
      errors: errors,
      paymentMethods: [
        if (rawMethods is List)
          for (final m in rawMethods)
            if (m is String) m,
      ],
      needsShipping: j['needs_shipping'] != false,
      billing: _address(j['billing_address']),
      shipping: _address(j['shipping_address']),
    );
  }

  static const empty = Cart(items: [], itemsCount: 0, totals: CartTotals.zero);

  final List<CartItem> items;
  final int itemsCount;
  final CartTotals totals;

  /// Problems the server found with the cart (e.g. an item went out of stock). Checkout is blocked.
  final List<String> errors;

  /// Enabled payment gateway ids.
  final List<String> paymentMethods;
  final bool needsShipping;
  final Map<String, String> billing;
  final Map<String, String> shipping;

  bool get isEmpty => items.isEmpty;

  bool get acceptsCashOnDelivery => paymentMethods.contains('cod');

  /// The country the server has for this cart, or [fallback] when it has none.
  String countryOr(String fallback) {
    final s = shipping['country'];
    if (s != null && s.isNotEmpty) return s;
    final b = billing['country'];
    if (b != null && b.isNotEmpty) return b;
    return fallback;
  }
}

/// What the customer typed on the checkout screen.
class CheckoutDetails {
  const CheckoutDetails({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.address,
    required this.city,
    required this.country,
    this.state = '',
    this.postcode = '',
    this.note = '',
  });

  final String firstName;
  final String lastName;
  final String phone;
  final String email;
  final String address;
  final String city;
  final String state;
  final String postcode;
  final String country;
  final String note;

  /// Body for `POST /wc/store/v1/checkout`. Payment is always cash on delivery.
  Map<String, dynamic> toJson() {
    final addr = <String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      'company': '',
      'address_1': address,
      'address_2': '',
      'city': city,
      'state': state,
      'postcode': postcode,
      'country': country,
      'phone': phone,
    };
    return {
      'billing_address': {...addr, 'email': email},
      'shipping_address': addr,
      'payment_method': 'cod',
      'customer_note': note,
    };
  }
}

/// The order the server created at checkout.
class PlacedOrder {
  const PlacedOrder({
    required this.orderId,
    required this.orderNumber,
    this.status = '',
    this.paymentStatus = '',
  });

  factory PlacedOrder.fromJson(Map<String, dynamic> j) {
    final id = _int(j['order_id']) ?? 0;
    final number = j['order_number'];
    return PlacedOrder(
      orderId: id,
      orderNumber: number is String && number.isNotEmpty ? number : '$id',
      status: _str(j['status']),
      paymentStatus: _str(_map(j['payment_result'])['payment_status']),
    );
  }

  final int orderId;
  final String orderNumber;
  final String status;
  final String paymentStatus;
}
