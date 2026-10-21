import 'package:yazan_domain/yazan_domain.dart';

import '../products/product_input.dart' show normalizeDigits;

/// One row of the orders feed (`/yazan-mobile/v1/sync/orders`). Parsing never throws:
/// a record with missing or odd fields still renders.
class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    required this.itemCount,
    required this.customerName,
    required this.created,
    required this.modified,
    required this.version,
    this.email = '',
    this.phone = '',
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    final id = _int(json['id']) ?? 0;
    final currency = _str(json['currency']);
    return OrderSummary(
      id: id,
      number: _str(json['number']).isEmpty ? '$id' : _str(json['number']),
      status: _str(json['status']),
      total: _money(_str(json['total']), currency.isEmpty ? 'USD' : currency),
      itemCount: _int(json['items']) ?? 0,
      customerName: _str(json['name']).trim(),
      created: DateTime.tryParse(_str(json['created'])),
      modified: _str(json['modified']),
      version: _str(json['version']),
      // The feed does not send these today; they are read only when a row carries them.
      email: _str(json['email']).trim(),
      phone: _str(json['phone']).trim(),
    );
  }

  final int id;
  final String number;

  /// WooCommerce status slug without the `wc-` prefix, for example `processing`.
  final String status;
  final Money total;
  final int itemCount;
  final String customerName;
  final DateTime? created;
  final String modified;

  /// Version token. Sent back as `If-Match` on writes.
  final String version;

  /// Empty unless the feed row carries it (field policy: never guessed).
  final String email;
  final String phone;

  /// Case-insensitive match on the order number (a leading `#` and Arabic-Indic digits are fine),
  /// the customer name, and the email or phone when the row has them. Empty query matches all.
  bool matches(String query) {
    final q = normalizeDigits(query.trim().toLowerCase()).replaceFirst(RegExp(r'^#\s*'), '');
    if (q.isEmpty) return true;
    if (number.toLowerCase().contains(q) || '$id' == q) return true;
    if (customerName.toLowerCase().contains(q) || email.toLowerCase().contains(q)) return true;
    if (phone.isEmpty || !RegExp(r'^[0-9\s+\-().]+$').hasMatch(q)) return false;
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isNotEmpty && normalizeDigits(phone).replaceAll(RegExp(r'[^0-9]'), '').contains(digits);
  }

  static String _str(Object? v) => v == null ? '' : '$v';

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_str(v));
  }

  static Money _money(String raw, String currency) {
    // The server may send more than two decimals ("129.500"); drop trailing zeros.
    final trimmed = raw.replaceFirstMapped(RegExp(r'(\.\d{2})0+$'), (m) => m.group(1)!);
    try {
      return Money.parse(trimmed, currency: currency);
    } on FormatException {
      return Money(0, currency);
    }
  }
}
