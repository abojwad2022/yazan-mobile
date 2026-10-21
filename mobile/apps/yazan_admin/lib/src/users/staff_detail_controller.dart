import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../more/staff_permissions.dart';
import 'staff_api.dart';
import 'staff_member.dart';

/// What happened to a "sign out on all devices" request.
enum StaffSignOutResult { done, offline, busy, noAccess, failed }

/// State and actions of one staff account screen. Everything that talks to the network is injected.
///
/// Read-only apart from one action: [signOutEverywhere]. It is online-only (never queued); a network
/// failure keeps the attempt, and so its `Idempotency-Key`, for [retry]. The role permission summary
/// comes from `GET /yazan/v1/roles` and needs `roles.view`; without it the screen shows role names
/// only.
class StaffDetailController extends ChangeNotifier {
  StaffDetailController({
    required this.member,
    required StaffRolesLoader loadRoles,
    required StaffSignOutEverywhere signOut,
    StaffPermissions permissions = const StaffPermissions.unknown(),
    String Function()? newKey,
  })  : _loadRoles = loadRoles,
        _signOut = signOut,
        _permissions = permissions,
        _newKey = newKey ?? YazanApiClient.newIdempotencyKey;

  final StaffMember member;
  final StaffRolesLoader _loadRoles;
  final StaffSignOutEverywhere _signOut;
  final String Function() _newKey;
  final StaffPermissions _permissions;

  Map<int, RolePermissionSummary> _summaries = const {};
  bool _rolesLoading = false;
  bool _rolesFailed = false;
  bool _rolesDenied = false;
  bool _sending = false;
  bool _disposed = false;
  String? _openKey;
  StaffSignOutResult? _lastResult;
  String _lastMessage = '';

  bool get rolesLoading => _rolesLoading;
  bool get rolesFailed => _rolesFailed;

  /// The account may not read roles, so no summary is offered.
  bool get rolesDenied => _rolesDenied || !_permissions.allows('roles.view');
  bool get sending => _sending;
  StaffSignOutResult? get lastResult => _lastResult;
  String get lastMessage => _lastMessage;
  bool get canRetry => _openKey != null;

  /// The action is offered only when the permission map says so; the server re-checks.
  bool get canSignOut => _permissions.known && _permissions.allows('users.force_logout');

  /// The summary of one of the member's roles, or null before it loaded.
  RolePermissionSummary? summaryFor(StaffRoleRef role) => _summaries[role.id];

  Future<void> loadRoles() async {
    if (!_permissions.allows('roles.view')) return;
    _rolesLoading = true;
    _rolesFailed = false;
    _rolesDenied = false;
    _notify();
    try {
      final body = await _loadRoles();
      final raw = body['items'];
      final next = <int, RolePermissionSummary>{};
      if (raw is List) {
        for (final r in raw) {
          if (r is Map && r['id'] is num) {
            next[(r['id'] as num).toInt()] = RolePermissionSummary.fromJson(Map<String, dynamic>.from(r));
          }
        }
      }
      _summaries = next;
    } on ApiError catch (e) {
      if (e.action == ErrorAction.hideFeature || e.status == 403) {
        _rolesDenied = true;
      } else {
        _rolesFailed = true;
      }
    } on Exception {
      _rolesFailed = true;
    }
    _rolesLoading = false;
    _notify();
  }

  /// Ends every WordPress session of the account. One `Idempotency-Key` per intent: a retry after a
  /// lost answer reuses it, a new request after success gets a new one.
  Future<StaffSignOutResult> signOutEverywhere() {
    if (!canSignOut) return Future<StaffSignOutResult>.value(StaffSignOutResult.noAccess);
    _openKey ??= _newKey();
    return _send();
  }

  /// Resends the open request with the same Idempotency-Key.
  Future<StaffSignOutResult> retry() {
    if (_openKey == null) return Future<StaffSignOutResult>.value(StaffSignOutResult.failed);
    return _send();
  }

  /// Dismisses the inline message and forgets the open attempt.
  void dismiss() {
    _openKey = null;
    _lastResult = null;
    _notify();
  }

  Future<StaffSignOutResult> _send() async {
    _sending = true;
    _lastResult = null;
    _lastMessage = '';
    _notify();
    final result = await _sendOnce(_openKey!);
    _lastResult = result;
    _sending = false;
    _notify();
    return result;
  }

  Future<StaffSignOutResult> _sendOnce(String key) async {
    try {
      final answer = await _signOut(member.id, idempotencyKey: key);
      if (answer['ok'] != true) {
        _openKey = null;
        return StaffSignOutResult.failed;
      }
      _openKey = null;
      return StaffSignOutResult.done;
    } on ApiError catch (e) {
      if (e.action == ErrorAction.waitAndRetrySameKey) return StaffSignOutResult.busy;
      if (e.action == ErrorAction.hideFeature || e.status == 403) {
        _openKey = null;
        return StaffSignOutResult.noAccess;
      }
      _lastMessage = e.message;
      return StaffSignOutResult.failed;
    } on Exception {
      // No network. Nothing is queued: the key waits for "Try again".
      return StaffSignOutResult.offline;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
