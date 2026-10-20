import '../products/product_input.dart' show normalizeDigits;

/// One row of the customer list. Parsing never throws: a record with missing or odd fields still
/// renders.
///
/// The fields follow `GET /yazan/v1/customers?stats=1` (`id`, `name`, `email`, `registered`,
/// `order_count`, `total_spent`). A delta feed would use the same names, plus `phone`. Fields the
/// server withholds from this account (the lifetime spend needs `reports.view`) are simply empty.
class CustomerSummary {
  const CustomerSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.orderCount,
    required this.totalSpent,
    required this.registered,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> json) {
    final email = _str(json['email']).trim();
    final name = _str(json['name']).trim();
    return CustomerSummary(
      id: _int(json['id']) ?? 0,
      name: name.isEmpty ? email : name,
      email: email,
      phone: _str(json['phone'] ?? json['billing_phone']).trim(),
      orderCount: _int(json['order_count'] ?? json['orders']),
      totalSpent: _str(json['total_spent'] ?? json['spent']).trim(),
      registered: _str(json['registered'] ?? json['created']).trim(),
    );
  }

  final int id;

  /// The display name, or the email when the account has none.
  final String name;
  final String email;

  /// Empty when the feed does not carry it (the list endpoint does not).
  final String phone;

  /// Null when the server did not say.
  final int? orderCount;

  /// A plain decimal string without currency, or empty.
  final String totalSpent;

  /// `YYYY-MM-DD` of the sign-up, or empty.
  final String registered;

  /// Case-insensitive match on the name, the email or the phone. A phone matches on its digits, so
  /// "0555 12" finds "+966 55-512 3456" and Arabic-Indic digits work; an empty query matches all.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q) || email.toLowerCase().contains(q)) return true;
    // Only a phone-looking query (digits and separators) is compared with the phone.
    if (!_phoneLike.hasMatch(q)) return false;
    final digits = _digitsOnly(q);
    if (digits.isEmpty) return false;
    return _digitsOnly(phone).contains(digits);
  }

  static final RegExp _phoneLike = RegExp(r'^[\d\s+\-().٠-٩۰-۹]+$');

  static String _digitsOnly(String s) => normalizeDigits(s).replaceAll(RegExp(r'[^0-9]'), '');

  static String _str(Object? v) => v == null ? '' : '$v';

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_str(v));
  }
}
