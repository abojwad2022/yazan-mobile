// Number and time wording for the dashboard. Digits stay Latin in both languages, like every other
// amount in the app, and values that mix digits with signs are wrapped in a left-to-right isolate so
// they read the same inside an Arabic sentence.

const _lri = '\u2066';
const _pdi = '\u2069';

/// "1,234.50 $": the server's decimal string with thousands separators, then the store symbol.
String formatAmount(String amount, String symbol) {
  final text = groupThousands(amount.trim());
  return symbol.isEmpty ? text : '$text $symbol';
}

/// [value] with [decimals] places, grouped and followed by the store symbol.
String formatSum(double value, int decimals, String symbol) =>
    formatAmount(value.toStringAsFixed(decimals), symbol);

/// Inserts "," between thousands of the whole part of a plain decimal string. Anything that is not
/// a plain decimal is returned as it is.
String groupThousands(String raw) {
  final m = RegExp(r'^(-?)(\d+)(\.\d+)?$').firstMatch(raw);
  if (m == null) return raw;
  final whole = m.group(2)!;
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  return '${m.group(1)}$buf${m.group(3) ?? ''}';
}

/// "+12.5%" / "-3.0%" / "0.0%".
String formatDelta(double percent) {
  final rounded = percent.abs() < 0.05 ? 0.0 : percent;
  final sign = rounded > 0 ? '+' : '';
  return '$sign${rounded.toStringAsFixed(1)}%';
}

/// Local date and time, "2026-10-20 14:05", isolated left to right.
String formatAsOf(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '$_lri${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}$_pdi';
}

/// Wraps a value so its digits and signs keep their order inside right-to-left text.
String isolate(String value) => '$_lri$value$_pdi';
