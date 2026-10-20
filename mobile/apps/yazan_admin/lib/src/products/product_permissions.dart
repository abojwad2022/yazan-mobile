/// Loads `GET /yazan-mobile/v1/me` (an admin session's answer carries a `permissions` map).
typedef PermissionsLoader = Future<Map<String, dynamic>> Function();

/// What this staff member may do with products, as the server last said. A hint for hiding
/// controls only: the server re-checks every request, and the app also checks that a change really
/// took effect (see `ProductDetailController`).
class ProductPermissions {
  const ProductPermissions._(this.known, this._slugs);

  /// Nothing is known yet (offline, or the answer had no map). Reading stays allowed from the
  /// cache; edits stay off.
  const ProductPermissions.unknown()
      : known = false,
        _slugs = const <String>{};

  /// For tests and previews.
  factory ProductPermissions.of(Iterable<String> slugs) => ProductPermissions._(true, Set<String>.of(slugs));

  /// Reads the `/me` payload. The map is `{slug: true}`; PHP encodes an empty one as `[]`.
  factory ProductPermissions.fromMe(Map<String, dynamic> me) {
    final raw = me['permissions'];
    if (raw is Map) {
      return ProductPermissions._(true, {
        for (final e in raw.entries)
          if (e.value == true) '${e.key}',
      });
    }
    if (raw is List) return const ProductPermissions._(true, <String>{});
    return const ProductPermissions.unknown();
  }

  final bool known;
  final Set<String> _slugs;

  bool _has(String slug) => _slugs.contains(slug);

  /// False only when the server said so.
  bool get canView => !known || _has('products.view');

  bool get canEditPrice => known && _has('products.edit') && _has('products.change_price');

  bool get canEditStock => known && _has('products.edit') && _has('products.change_stock');
}
