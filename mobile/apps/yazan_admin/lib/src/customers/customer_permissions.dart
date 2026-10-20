/// What this staff member may see of customers, as the server last said in the `/me` permission
/// map (`{slug: true}`; PHP encodes an empty one as `[]`). A hint for hiding the section only: the
/// server re-checks every request.
class CustomerPermissions {
  const CustomerPermissions._(this.known, this._slugs);

  /// Nothing is known yet (offline, or the answer had no map). Reading stays allowed from the
  /// cache.
  const CustomerPermissions.unknown()
      : known = false,
        _slugs = const <String>{};

  /// For tests and previews.
  factory CustomerPermissions.of(Iterable<String> slugs) =>
      CustomerPermissions._(true, Set<String>.of(slugs));

  /// Reads the `/me` payload.
  factory CustomerPermissions.fromMe(Map<String, dynamic> me) {
    final raw = me['permissions'];
    if (raw is Map) {
      return CustomerPermissions._(true, {
        for (final e in raw.entries)
          if (e.value == true) '${e.key}',
      });
    }
    if (raw is List) return const CustomerPermissions._(true, <String>{});
    return const CustomerPermissions.unknown();
  }

  final bool known;
  final Set<String> _slugs;

  /// False only when the server said so (`customers.view`).
  bool get canView => !known || _slugs.contains('customers.view');

  /// `customers.view_pii`: the server strips addresses, emails and phones from a response for
  /// anyone without it, so the screens say so instead of looking broken.
  bool get canViewPii => !known || _slugs.contains('customers.view_pii');
}
