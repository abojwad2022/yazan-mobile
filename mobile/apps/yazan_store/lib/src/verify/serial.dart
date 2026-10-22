import '../config.dart';

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
  final cleaned =
      _latinDigitsAndHyphens(raw.trim()).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), '');
  return cleaned.length > serialMaxLength ? cleaned.substring(0, serialMaxLength) : cleaned;
}

/// Arabic-Indic and Eastern Arabic-Indic digits become ordinary digits, and the dash characters that
/// copy and paste bring in become a plain hyphen. Everything else is left as it is.
String _latinDigitsAndHyphens(String s) {
  final out = StringBuffer();
  for (final rune in s.runes) {
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
  return out.toString();
}

/// The host of the site this build talks to (`YAZAN_BASE_URL`), so a staging or local build also
/// accepts the codes its own site prints. Null when the setting is not an address.
String? _configuredHost() {
  final host = Uri.tryParse(AppConfig.baseUrl)?.host.toLowerCase() ?? '';
  return host.isEmpty ? null : host;
}

bool _isYazanHost(String host, String? siteHost) {
  final h = host.toLowerCase();
  if (h == 'yazanus.com' || h.endsWith('.yazanus.com')) return true;
  return siteHost != null && siteHost.isNotEmpty && h == siteHost.toLowerCase();
}

/// Reads the serial out of what a QR code or barcode held: either the serial itself, or the address
/// of YAZAN's verification page (`yazanus.com/verify-ring/{serial}/`, or its `yz_serial` / `serial`
/// query value).
///
/// What counts:
/// * An address only when it is http(s), on a YAZAN host, and points at `verify-ring`; any other
///   address (a shop's site, another site's verification page) returns null.
/// * Plain text only when it is already serial-shaped: 3 to 40 letters, digits and hyphens, nothing
///   else (so a Wi-Fi login or a sentence returns null). The app does not know the server's serial
///   format, so any such text is passed on, including a stray code that merely looks like one (a
///   product barcode's digits, say); the server decides whether it is a real serial.
///
/// Arabic-Indic digits and pasted dashes are accepted the same way [cleanSerial] accepts them; nothing
/// else is "cleaned" into a serial.
///
/// [siteHost] is the one host besides `yazanus.com` (and its subdomains) whose addresses count; it
/// defaults to the host of the build's `YAZAN_BASE_URL`.
String? serialFromScan(String raw, {String? siteHost}) {
  final text = raw.trim();
  if (text.isEmpty || text.length > 2048) return null;
  // A serial is letters, digits and hyphens only, so anything with a slash or a scheme is an address.
  final looksLikeAddress = text.contains('://') || text.contains('/');
  if (!looksLikeAddress) return _plainSerial(text);
  try {
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    if (!_isYazanHost(uri.host, siteHost ?? _configuredHost())) return null;
    final segments = [
      for (final s in uri.pathSegments)
        if (s.isNotEmpty) s,
    ];
    final at = segments.indexWhere((s) => s.toLowerCase() == 'verify-ring');
    if (at < 0) return null;
    for (final key in const ['yz_serial', 'serial']) {
      final value = uri.queryParameters[key];
      if (value != null) return _plainSerial(value);
    }
    // Exactly one segment after verify-ring: `/verify-ring/{serial}/`, nothing deeper.
    if (at + 2 == segments.length) return _plainSerial(segments[at + 1]);
    return null;
  } on FormatException {
    // Broken percent-encoding in the path or query.
    return null;
  }
}

String? _plainSerial(String s) {
  final t = _latinDigitsAndHyphens(s.trim());
  if (t.length < serialMinLength || t.length > serialMaxLength) return null;
  if (!RegExp(r'^[A-Za-z0-9\-]+$').hasMatch(t)) return null;
  return t.toUpperCase();
}
