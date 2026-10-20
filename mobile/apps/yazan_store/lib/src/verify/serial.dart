/// The shortest serial the server's route accepts (`/yazan-mobile/v1/verify/{serial}`).
const int serialMinLength = 3;

/// The longest serial the server keeps.
const int serialMaxLength = 40;

/// Cleans what a customer typed or pasted the way the server does (`Yazan_Core_Verify::clean_serial`):
/// trimmed, upper case, only letters, digits and hyphens, at most 40 characters.
///
/// Two conveniences on top: Arabic-Indic digits become ordinary digits and the dash characters that
/// copy and paste bring in become a plain hyphen, so a serial typed on an Arabic keyboard still matches.
String cleanSerial(String raw) {
  final out = StringBuffer();
  for (final rune in raw.trim().runes) {
    var r = rune;
    if (r >= 0x0660 && r <= 0x0669) {
      r = 0x30 + (r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      r = 0x30 + (r - 0x06F0);
    } else if ((r >= 0x2010 && r <= 0x2015) || r == 0x2212) {
      r = 0x2D;
    }
    out.writeCharCode(r);
  }
  final cleaned = out.toString().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), '');
  return cleaned.length > serialMaxLength ? cleaned.substring(0, serialMaxLength) : cleaned;
}

/// Reads the serial out of what a QR code held: either the serial itself, or the address of the
/// verification page (`.../verify-ring/{serial}/`, or a `serial` / `yz_serial` query value).
///
/// Returns null when the code is anything else, so a stray QR code (a Wi-Fi login, a shop sign) is
/// never sent to the server as if it were a serial.
String? serialFromScan(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text.length > 2048) return null;
  final looksLikeAddress = text.contains('://') || text.toLowerCase().startsWith('www.');
  if (!looksLikeAddress) return _plainSerial(text);
  try {
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null) return null;
    for (final key in const ['serial', 'yz_serial']) {
      final value = uri.queryParameters[key];
      if (value != null) return _plainSerial(value);
    }
    final segments = [
      for (final s in uri.pathSegments)
        if (s.isNotEmpty) s,
    ];
    final at = segments.indexWhere((s) => s.toLowerCase() == 'verify-ring');
    if (at >= 0 && at + 1 < segments.length) return _plainSerial(segments[at + 1]);
  } on FormatException {
    return null;
  }
  return null;
}

String? _plainSerial(String s) {
  final t = s.trim();
  if (!RegExp(r'^[A-Za-z0-9\-]{3,40}$').hasMatch(t)) return null;
  return t.toUpperCase();
}
