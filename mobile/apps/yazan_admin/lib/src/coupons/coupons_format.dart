import '../../l10n/app_localizations.dart';
import 'coupon_summary.dart';

/// Localised name of a WooCommerce discount type; an unknown type is shown as it is.
String couponTypeLabel(AppLocalizations l, String type) {
  switch (type) {
    case 'percent':
      return l.couponTypePercent;
    case 'fixed_cart':
      return l.couponTypeFixedCart;
    case 'fixed_product':
      return l.couponTypeFixedProduct;
  }
  return type;
}

/// "Used 3" or "Used 3 of 10".
String couponUsageText(AppLocalizations l, int count, int? limit) =>
    limit == null ? l.couponUsageCount(count) : l.couponUsageLimit(count, limit);

/// "Expires 2026-12-31" or "No expiry".
String couponExpiryText(AppLocalizations l, CouponSummary c) =>
    c.expires.isEmpty ? l.couponNoExpiry : l.couponExpiresOn(c.expires);
