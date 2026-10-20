/// "250.00 $"; an empty amount reads as a dash. Digits stay Latin; the server decides every amount.
String customerMoney(String amount, [String symbol = '']) {
  if (amount.isEmpty) return '—';
  return symbol.isEmpty ? amount : '$amount $symbol';
}
