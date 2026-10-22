import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../dashboard/dashboard_format.dart' show isolate;
import '../more/staff_permissions.dart';
import '../security/app_lock_scope.dart';
import 'staff_api.dart';
import 'staff_detail_controller.dart';
import 'staff_list_page.dart' show staffRoleText;
import 'staff_member.dart';

/// One staff account: who they are, their roles with a read-only summary of what each role can do,
/// and one online-only action, "Sign out on all devices", behind a confirmation and an
/// `Idempotency-Key`. Roles and permissions cannot be edited here.
class StaffDetailPage extends StatefulWidget {
  const StaffDetailPage({
    super.key,
    required this.member,
    required this.loadRoles,
    required this.signOut,
    this.permissions = const StaffPermissions.unknown(),
    this.newKey,
  });

  final StaffMember member;
  final StaffRolesLoader loadRoles;
  final StaffSignOutEverywhere signOut;
  final StaffPermissions permissions;

  /// Key factory for tests.
  final String Function()? newKey;

  @override
  State<StaffDetailPage> createState() => _StaffDetailPageState();
}

class _StaffDetailPageState extends State<StaffDetailPage> {
  late final StaffDetailController _c = StaffDetailController(
    member: widget.member,
    loadRoles: widget.loadRoles,
    signOut: widget.signOut,
    permissions: widget.permissions,
    newKey: widget.newKey,
  );

  @override
  void initState() {
    super.initState();
    _c.loadRoles();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    final l = AppLocalizations.of(context);
    final m = widget.member;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(m.isSelf ? l.staffSignOutConfirmSelf : l.staffSignOutConfirm(m.name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l.cancel)),
          FilledButton(
            key: const ValueKey('confirm-signout'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.staffSignOutAll),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    // Refused or cancelled: nothing is sent.
    if (!await confirmSensitive(context, l.securityReasonSignOut) || !mounted) return;
    _handle(await _c.signOutEverywhere());
  }

  /// "Try again" resends the sign-out, so it asks for the identity check again. Refused or
  /// cancelled: nothing is sent and the open key stays for the button.
  Future<void> _retry() async {
    final l = AppLocalizations.of(context);
    if (!await confirmSensitive(context, l.securityReasonSignOut) || !mounted) return;
    _handle(await _c.retry());
  }

  void _handle(StaffSignOutResult result) {
    if (!mounted) return;
    if (result == StaffSignOutResult.done) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.staffSignOutDone)));
    }
    // Every other outcome is shown inline from the controller's state.
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final m = widget.member;
    final login = m.lastLoginShort;
    return Scaffold(
      appBar: AppBar(title: Text(m.name)),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => ListView(
          padding: const EdgeInsetsDirectional.all(16),
          children: [
            Text(m.isSelf ? '${m.name} (${l.staffYou})' : m.name, style: t.titleMedium),
            const SizedBox(height: 12),
            if (m.email.isNotEmpty)
              _line(l.staffEmailLabel, m.email, key: const ValueKey('staff-email'), ltr: true),
            _line(l.staffStatusLabel, m.suspended ? l.staffSuspended : l.staffActive,
                key: const ValueKey('staff-status')),
            _line(l.staffRolesLabel, staffRoleText(l, m), key: const ValueKey('staff-roles')),
            _line(
              l.staffLastLoginLabel,
              login.isEmpty ? l.staffNeverSignedIn : isolate(login),
              key: const ValueKey('staff-login'),
            ),
            const SizedBox(height: 16),
            Text(l.staffPermissionsTitle, style: t.titleSmall),
            const SizedBox(height: 8),
            _permissions(context, l),
            const SizedBox(height: 16),
            _actionCard(context, l),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value, {Key? key, bool ltr = false}) {
    return Padding(
      key: key,
      padding: const EdgeInsetsDirectional.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              textDirection: ltr ? TextDirection.ltr : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissions(BuildContext context, AppLocalizations l) {
    final m = widget.member;
    if (_c.rolesDenied) return Text(l.staffPermissionsHidden, key: const ValueKey('perm-hidden'));
    if (_c.rolesLoading) return const Center(child: CircularProgressIndicator());
    if (_c.rolesFailed) {
      return Row(
        children: [
          Expanded(child: Text(l.staffPermissionsFailed, key: const ValueKey('perm-failed'))),
          TextButton(key: const ValueKey('perm-retry'), onPressed: _c.loadRoles, child: Text(l.retry)),
        ],
      );
    }
    if (m.roles.isEmpty) {
      return Text(m.isSuper ? l.staffPermissionsFull : l.staffPermissionsNone, key: const ValueKey('perm-empty'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final role in m.roles) _roleCard(context, l, role),
      ],
    );
  }

  Widget _roleCard(BuildContext context, AppLocalizations l, StaffRoleRef role) {
    final t = Theme.of(context).textTheme;
    final summary = _c.summaryFor(role);
    final Widget body;
    if (role.isSuper || (summary?.isSuper ?? false)) {
      body = Text(l.staffPermissionsFull, key: ValueKey('perm-full-${role.id}'));
    } else if (summary == null || summary.groups.isEmpty) {
      body = Text(l.staffPermissionsNone, key: ValueKey('perm-none-${role.id}'));
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.staffPermissionsCount(summary.count), style: t.labelMedium),
          const SizedBox(height: 4),
          for (final e in summary.groups.entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 2),
              child: Text(
                e.value.isEmpty ? e.key : '${e.key}: ${e.value.join(', ')}',
                key: ValueKey('perm-${role.id}-${e.key}'),
                style: t.bodySmall,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
              ),
            ),
        ],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(role.name, style: t.titleSmall),
            const SizedBox(height: 4),
            body,
          ],
        ),
      ),
    );
  }

  Widget _actionCard(BuildContext context, AppLocalizations l) {
    String? message;
    var retry = false;
    switch (_c.lastResult) {
      case StaffSignOutResult.offline:
        message = l.staffSignOutOffline;
        retry = _c.canRetry;
      case StaffSignOutResult.busy:
        message = l.statusBusy;
        retry = _c.canRetry;
      case StaffSignOutResult.noAccess:
        message = l.staffSignOutNoPermission;
      case StaffSignOutResult.failed:
        message = _c.lastMessage.isEmpty ? l.staffSignOutFailed : _c.lastMessage;
        retry = _c.canRetry;
      case StaffSignOutResult.done:
      case null:
        message = null;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.staffReadOnlyNote, key: const ValueKey('staff-readonly-note')),
            if (_c.canSignOut) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.wifi_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l.staffSignOutOnlineOnly)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonal(
                    key: const ValueKey('staff-signout'),
                    onPressed: _c.sending ? null : _signOut,
                    child: Text(l.staffSignOutAll),
                  ),
                  if (_c.sending)
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message, key: const ValueKey('signout-message')),
              if (retry)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey('signout-retry'),
                    onPressed: _c.sending ? null : _retry,
                    child: Text(l.retry),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
