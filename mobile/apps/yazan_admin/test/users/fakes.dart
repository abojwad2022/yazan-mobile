import 'package:yazan_admin/src/users/staff_api.dart';

/// Rows as `GET /yazan/v1/users` sends them (`items[]`, `Yazan_Users::payload`).
const List<Map<String, dynamic>> staffRows = [
  {
    'id': 5,
    'name': 'Sara Manager',
    'login': 'sara',
    'email': 'sara@example.test',
    'status': 'active',
    'roles': [
      {'id': 2, 'slug': 'manager', 'name': 'Manager', 'is_super': false},
    ],
    'is_super': false,
    'last_login': '2026-10-20 14:05:33',
    'is_self': true,
  },
  {
    'id': 6,
    'name': 'Omar Packer',
    'login': 'omar',
    'email': 'omar@example.test',
    'status': 'suspended',
    'roles': [
      {'id': 3, 'slug': 'packer', 'name': 'Packer', 'is_super': false},
    ],
    'is_super': false,
    'last_login': '',
    'is_self': false,
  },
  {
    'id': 7,
    'name': 'المالك',
    'login': 'owner',
    'email': 'owner@example.test',
    'status': 'active',
    'roles': [
      {'id': 1, 'slug': 'owner', 'name': 'Owner', 'is_super': true},
    ],
    'is_super': true,
    'last_login': '2026-10-21 09:00:00',
    'is_self': false,
  },
];

/// One page of the list route.
Map<String, dynamic> staffPage(List<Map<String, dynamic>> items, {int totalPages = 1}) =>
    {'items': items, 'total': items.length, 'total_pages': totalPages, 'page': 1};

/// `GET /yazan/v1/roles`.
Map<String, dynamic> rolesBody() => {
      'is_super': false,
      'items': [
        {'id': 1, 'slug': 'owner', 'name': 'Owner', 'is_super': true, 'permissions': <String>[]},
        {
          'id': 2,
          'slug': 'manager',
          'name': 'Manager',
          'is_super': false,
          'permissions': ['orders.view', 'orders.edit', 'products.view', 'reports.view'],
        },
        {'id': 3, 'slug': 'packer', 'name': 'Packer', 'is_super': false, 'permissions': <String>[]},
      ],
    };

/// One recorded sign-out request.
class SignOutCall {
  SignOutCall(this.id, this.key);

  final int id;
  final String key;
}

/// An in-memory stand-in for the roles and force-logout routes. No network anywhere.
class FakeStaffServer {
  /// When set, the roles load throws it.
  Exception? rolesError;

  /// Thrown by the next sign-outs, in order; `null` means "accept".
  final List<Exception?> signOutFailures = [];
  final List<SignOutCall> signOuts = [];
  Map<String, dynamic> signOutAnswer = {'ok': true};

  StaffRolesLoader get roles => () async {
        final err = rolesError;
        if (err != null) throw err;
        return rolesBody();
      };

  StaffSignOutEverywhere get signOut => (id, {required String idempotencyKey}) async {
        signOuts.add(SignOutCall(id, idempotencyKey));
        final failure = signOutFailures.isEmpty ? null : signOutFailures.removeAt(0);
        if (failure != null) throw failure;
        return signOutAnswer;
      };
}
