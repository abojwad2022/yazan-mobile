/// A role as `Yazan_Users::payload` lists it on an account.
class StaffRoleRef {
  const StaffRoleRef({required this.id, required this.slug, required this.name, required this.isSuper});

  final int id;
  final String slug;
  final String name;
  final bool isSuper;
}

/// One staff account from `GET /yazan/v1/users` (`items[]`). Parsing never throws: a record with
/// missing or odd fields still renders. The route exposes no two-factor state, so there is none here.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.email,
    required this.suspended,
    required this.roles,
    required this.isSuper,
    required this.lastLogin,
    required this.isSelf,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    final rawRoles = json['roles'];
    final name = _str(json['name']).trim();
    return StaffMember(
      id: _int(json['id']) ?? 0,
      name: name.isEmpty ? _str(json['login']).trim() : name,
      email: _str(json['email']).trim(),
      suspended: _str(json['status']) == 'suspended',
      roles: [
        if (rawRoles is List)
          for (final r in rawRoles)
            if (r is Map)
              StaffRoleRef(
                id: _int(r['id']) ?? 0,
                slug: _str(r['slug']),
                name: _str(r['name']).trim().isEmpty ? _str(r['slug']) : _str(r['name']).trim(),
                isSuper: r['is_super'] == true,
              ),
      ],
      isSuper: json['is_super'] == true,
      lastLogin: _str(json['last_login']).trim(),
      isSelf: json['is_self'] == true,
    );
  }

  final int id;
  final String name;
  final String email;
  final bool suspended;
  final List<StaffRoleRef> roles;
  final bool isSuper;

  /// The site's local time as the server stored it ("2026-10-20 14:05:33"), or empty (never).
  final String lastLogin;
  final bool isSelf;

  /// "2026-10-20 14:05", or empty.
  String get lastLoginShort => lastLogin.length >= 16 ? lastLogin.substring(0, 16) : lastLogin;

  /// Case-insensitive match on the name, the email or a role name.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        email.toLowerCase().contains(q) ||
        roles.any((r) => r.name.toLowerCase().contains(q));
  }

  static String _str(Object? v) => v == null ? '' : '$v';

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_str(v));
  }
}

/// The permissions one role grants, grouped by area (the part of the slug before the dot).
class RolePermissionSummary {
  const RolePermissionSummary({required this.roleName, required this.isSuper, required this.groups});

  /// Reads one `items[]` entry of `GET /yazan/v1/roles`.
  factory RolePermissionSummary.fromJson(Map<String, dynamic> json) {
    final groups = <String, List<String>>{};
    final raw = json['permissions'];
    if (raw is List) {
      for (final p in raw) {
        final slug = '$p';
        final dot = slug.indexOf('.');
        final area = dot > 0 ? slug.substring(0, dot) : slug;
        final action = dot > 0 ? slug.substring(dot + 1) : '';
        final list = groups.putIfAbsent(area, () => <String>[]);
        if (action.isNotEmpty) list.add(action);
      }
    }
    final keys = groups.keys.toList()..sort();
    return RolePermissionSummary(
      roleName: '${json['name'] ?? json['slug'] ?? ''}',
      isSuper: json['is_super'] == true,
      groups: {
        for (final k in keys) k: (groups[k]!..sort()),
      },
    );
  }

  final String roleName;
  final bool isSuper;

  /// Area -> actions, both sorted: `orders: [edit, view]`.
  final Map<String, List<String>> groups;

  int get count => groups.values.fold(0, (a, b) => a + (b.isEmpty ? 1 : b.length));
}
