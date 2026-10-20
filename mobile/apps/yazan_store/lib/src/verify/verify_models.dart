import '../cart/cart.dart' show plainText;
import '../json_read.dart';

/// The certificate data the server returns for a serial (`GET /yazan-mobile/v1/verify/{serial}`).
///
/// It is exactly what the website's verification page shows. The app displays these fields as the
/// server sent them and adds no claim of its own: it never says where a stone is from or how pure
/// the silver is beyond a field's own text.
class RingCertificate {
  const RingCertificate({
    required this.serial,
    this.name = '',
    this.image = '',
    this.stone = '',
    this.color = '',
    this.metal = '',
    this.purity = '',
    this.origin = '',
    this.shape = '',
    this.carat = '',
    this.wearer = '',
    this.collection = '',
    this.oneOfOne = false,
    this.year = '',
  });

  /// Throws a [FormatException] when the answer has no serial, so an empty or foreign answer is
  /// never shown as a genuine ring.
  factory RingCertificate.fromJson(Map<String, dynamic> j) {
    final serial = asStr(j['serial']).trim();
    if (serial.isEmpty) throw const FormatException('verify answer without a serial');
    String text(String key) => plainText(_text(j[key])).trim();
    return RingCertificate(
      serial: serial,
      name: text('name'),
      image: asStr(j['image']),
      stone: text('stone'),
      color: text('color'),
      metal: text('metal'),
      purity: text('purity'),
      origin: text('origin'),
      shape: text('shape'),
      carat: text('carat'),
      wearer: text('wearer'),
      collection: text('collection'),
      oneOfOne: j['one_of_one'] == true,
      year: text('year'),
    );
  }

  final String serial;
  final String name;
  final String image;
  final String stone;
  final String color;
  final String metal;

  /// The silver purity field as the server wrote it (for example "925"); empty when none is recorded.
  final String purity;

  /// The origin field as the server wrote it.
  final String origin;
  final String shape;
  final String carat;
  final String wearer;
  final String collection;
  final bool oneOfOne;

  /// The certified year.
  final String year;

  /// The picture URL, or null when there is none.
  String? get imageUrl => image.isEmpty ? null : image;
}

String _text(Object? v) {
  if (v is String) return v;
  if (v is num) return '$v';
  return '';
}
