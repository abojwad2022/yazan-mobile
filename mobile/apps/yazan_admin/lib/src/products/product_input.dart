import 'package:yazan_domain/yazan_domain.dart';

// Pure helpers for what staff type into the price and stock fields. No Flutter, no localisation:
// they run the same under a test as on the phone. An Arabic keyboard types Arabic-Indic digits and
// the Arabic decimal separator; the server only understands ASCII, so everything is normalised first.

/// Arabic-Indic (U+0660..0669) and Persian (U+06F0..06F9) digits become ASCII, the Arabic decimal
/// separator (U+066B) becomes ".", and the Arabic thousands separator, spaces and direction marks
/// are dropped.
String normalizeDigits(String input) {
  final out = StringBuffer();
  for (final r in input.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      out.writeCharCode(0x30 + (r - 0x0660));
      continue;
    }
    if (r >= 0x06F0 && r <= 0x06F9) {
      out.writeCharCode(0x30 + (r - 0x06F0));
      continue;
    }
    if (r == 0x066B) {
      out.write('.');
      continue;
    }
    if (r == 0x066C || r == 0x20 || r == 0xA0 || r == 0x200E || r == 0x200F) {
      continue;
    }
    out.writeCharCode(r);
  }
  return out.toString();
}

/// A typed price as [Money] (currency is a placeholder: the product feed carries none), or null
/// when it is not a decimal amount with at most two decimals. The caller decides about zero.
Money? parsePriceInput(String raw) {
  final cleaned = normalizeDigits(raw);
  if (cleaned.isEmpty || cleaned.length > 12) return null;
  try {
    return Money.parse(cleaned, currency: 'X');
  } on FormatException {
    return null;
  }
}

/// A typed stock quantity: whole number, 0 to 999999. Null when anything else.
int? parseStockInput(String raw) {
  final cleaned = normalizeDigits(raw).trim();
  if (!RegExp(r'^\d{1,6}$').hasMatch(cleaned)) return null;
  return int.parse(cleaned);
}

/// A price string from the server ("129", "129.5", "129.500") as "129.00" / "129.50"; an empty
/// string stays empty; anything unreadable is returned as it came.
String plainPrice(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  final trimmed = t.replaceFirstMapped(RegExp(r'(\.\d{2})0+$'), (m) => m.group(1)!);
  try {
    return Money.parse(trimmed, currency: 'X').toDecimalString();
  } on FormatException {
    return t;
  }
}

/// True when two price strings mean the same amount ("129" and "129.00"); two empties are equal.
bool samePrice(String a, String b) => plainPrice(a) == plainPrice(b);
