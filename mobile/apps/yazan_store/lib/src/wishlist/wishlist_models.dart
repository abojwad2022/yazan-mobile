import '../cart/cart.dart' show plainText;
import '../json_read.dart';

/// One saved piece: the card the server returns for `GET /yazan/v1/wishlist`.
///
/// [price] is the server's display text (for example "$120.00"), not an amount to compute with.
class WishlistItem {
  const WishlistItem({
    required this.id,
    required this.name,
    this.price = '',
    this.thumb = '',
  });

  /// Reads a server card or a stored copy of one. Returns an item with id 0 when it is unusable.
  factory WishlistItem.fromJson(Map<String, dynamic> j) => WishlistItem(
        id: asInt(j['id']) ?? 0,
        name: plainText(asStr(j['name'])),
        price: plainText(asStr(j['price'])),
        thumb: asStr(j['thumb']),
      );

  final int id;
  final String name;
  final String price;
  final String thumb;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'price': price,
        'thumb': thumb,
      };

  /// The thumbnail URL, or null when there is none.
  String? get thumbUrl => thumb.isEmpty ? null : thumb;
}

/// Answer of `POST /yazan/v1/wishlist/toggle`: whether the piece is now saved.
class WishlistToggle {
  const WishlistToggle({required this.inList, required this.count});

  factory WishlistToggle.fromJson(Map<String, dynamic> j) =>
      WishlistToggle(inList: j['in'] == true, count: asInt(j['count']) ?? 0);

  final bool inList;
  final int count;
}

/// Parses the `items` array of the list answer, dropping unusable rows.
List<WishlistItem> parseWishlistItems(Object? raw) {
  final out = <WishlistItem>[];
  for (final i in asList(raw)) {
    if (i is Map) {
      final item = WishlistItem.fromJson(asMap(i));
      if (item.id > 0) out.add(item);
    }
  }
  return out;
}
