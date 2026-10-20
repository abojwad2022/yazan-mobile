import '../../l10n/app_localizations.dart';
import 'product_input.dart';
import 'product_summary.dart';

/// "129.50", or "129.50 SAR" when the currency is known; an empty price reads as a dash. The
/// amount and the code are joined by a no-break space so the pair holds together in any layout.
String priceText(String raw, [String currency = '']) {
  final p = plainPrice(raw);
  if (p.isEmpty) return '\u2014';
  final c = currency.trim();
  return c.isEmpty ? p : '$p\u00a0$c';
}

/// Localised stock line for a product row: "In stock: 3", "Out of stock", ...
String stockLabel(AppLocalizations l, ProductSummary p) {
  switch (p.level) {
    case StockLevel.outOfStock:
      return l.stockOut;
    case StockLevel.onBackorder:
      return l.stockBackorder;
    case StockLevel.inStock:
      final n = p.stock;
      return n == null ? l.stockIn : l.stockInCount(n);
    case StockLevel.unknown:
      return '';
  }
}

/// Same for a bare status slug and quantity (the detail screen).
String stockLabelFor(AppLocalizations l, String status, int? quantity) {
  return stockLabel(
    l,
    ProductSummary(
      id: 0,
      name: '',
      sku: '',
      type: '',
      price: '',
      regularPrice: '',
      salePrice: '',
      onSale: false,
      stockStatus: status,
      stock: quantity,
      thumbUrl: '',
      modified: '',
    ),
  );
}
