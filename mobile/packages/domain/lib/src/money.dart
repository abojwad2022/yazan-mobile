/// Money in minor units (cents). Never a double: the server decides every total.
class Money implements Comparable<Money> {
  const Money(this.minor, [this.currency = 'USD']);

  /// Parses a decimal string such as "129.50" or "1,299.00" (comma = thousands).
  factory Money.parse(String value, {String currency = 'USD'}) {
    final cleaned = value.trim().replaceAll(',', '');
    final m = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (m == null) {
      throw FormatException('Not a money amount', value);
    }
    final whole = int.parse(m.group(2)!);
    final frac = int.parse((m.group(3) ?? '').padRight(2, '0'));
    final minor = whole * 100 + frac;
    return Money(m.group(1) == null ? minor : -minor, currency);
  }

  final int minor;
  final String currency;

  Money operator +(Money o) => Money(minor + _same(o).minor, currency);
  Money operator -(Money o) => Money(minor - _same(o).minor, currency);
  Money times(int qty) => Money(minor * qty, currency);

  Money _same(Money o) {
    if (o.currency != currency) {
      throw ArgumentError('Currency mismatch: $currency vs ${o.currency}');
    }
    return o;
  }

  /// "129.50" — no symbol; the UI formats with the locale.
  String toDecimalString() {
    final abs = minor.abs();
    final s = '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
    return minor < 0 ? '-$s' : s;
  }

  @override
  int compareTo(Money other) => minor.compareTo(_same(other).minor);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => '$currency ${toDecimalString()}';
}
