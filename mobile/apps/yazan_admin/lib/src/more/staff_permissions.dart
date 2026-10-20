/// What this staff member may do, as the server last said in the `/me` permission map
/// (`{slug: true}`; PHP encodes an empty one as `[]`). A hint for hiding menus only: the server
/// re-checks every request.
class StaffPermissions {
  const StaffPermissions._(this.known, this._slugs);

  /// Nothing is known yet (offline, or the answer had no map). Everything is then allowed in the
  /// UI and the server decides.
  const StaffPermissions.unknown()
      : known = false,
        _slugs = const <String>{};

  /// For tests and previews.
  factory StaffPermissions.of(Iterable<String> slugs) => StaffPermissions._(true, Set<String>.of(slugs));

  /// Reads the `/me` payload.
  factory StaffPermissions.fromMe(Map<String, dynamic> me) {
    final raw = me['permissions'];
    if (raw is Map) {
      return StaffPermissions._(true, {
        for (final e in raw.entries)
          if (e.value == true) '${e.key}',
      });
    }
    if (raw is List) return const StaffPermissions._(true, <String>{});
    return const StaffPermissions.unknown();
  }

  final bool known;
  final Set<String> _slugs;

  /// True when [slug] is null (no permission needed), unknown, or granted.
  bool allows(String? slug) => slug == null || !known || _slugs.contains(slug);
}
