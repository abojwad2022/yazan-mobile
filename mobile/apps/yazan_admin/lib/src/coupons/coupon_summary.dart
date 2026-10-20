import '../products/product_input.dart' show normalizeDigits;

/// One row of the coupon list, from `GET /yazan/v1/coupons` (`items[]`). Parsing never throws: a
/// record with missing or odd fields still renders.
class CouponSummary {
  const CouponSummary({
    required this.id,
    required this.code,
    required this.description,
    required this.discountType,
    required this.amount,
    required this.amountText,
    required this.usageCount,
    required this.usageLimit,
    required this.expires,
    required this.expired,
    required this.freeShipping,
  });

  factory CouponSummary.fromJson(Map<String, dynamic> json) {
    final amount = _str(json['amount']).trim();
    final html = _str(json['amount_html']).trim();
    final limit = _int(json['usage_limit']);
    return CouponSummary(
      id: _int(json['id']) ?? 0,
      code: _str(json['code']).trim(),
      description: _str(json['description']).trim(),
      discountType: _str(json['discount_type']).trim(),
      amount: amount,
      amountText: html.isEmpty ? amount : html,
      usageCount: _int(json['usage_count']) ?? 0,
      // WooCommerce sends 0 for "no limit".
      usageLimit: limit == null || limit <= 0 ? null : limit,
      expires: _day(_str(json['expires'] ?? json['date_expires']).trim()),
      expired: json['expired'] == true,
      freeShipping: json['free_shipping'] == true,
    );
  }

  final int id;
  final String code;
  final String description;

  /// `percent`, `fixed_cart` or `fixed_product` (or a type added by a plugin).
  final String discountType;
  final String amount;

  /// The server's rendering of the discount ("20%", "$15.00").
  final String amountText;
  final int usageCount;

  /// Null when the coupon has no overall limit.
  final int? usageLimit;

  /// `YYYY-MM-DD`, or empty when it never expires.
  final String expires;
  final bool expired;
  final bool freeShipping;

  bool get isPercent => discountType == 'percent';

  /// Case-insensitive match on the code or the description.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return code.toLowerCase().contains(q) || description.toLowerCase().contains(q);
  }

  static String _str(Object? v) => v == null ? '' : '$v';

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(normalizeDigits(_str(v)));
  }

  static String _day(String s) => s.length >= 10 ? s.substring(0, 10) : s;
}
