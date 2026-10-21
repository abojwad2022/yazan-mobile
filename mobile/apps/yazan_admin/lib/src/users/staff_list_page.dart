import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import '../dashboard/dashboard_format.dart' show formatAsOf, isolate;
import '../orders/no_access_view.dart';
import 'staff_member.dart';
import 'staff_repository.dart';

/// The staff accounts as the phone last saw them: search by name, email or role, a role badge, a
/// Suspended badge and the last sign-in. It shows the offline copy first, with "As of <time>"
/// while the last refresh failed; pulling down refreshes.
class StaffListPage extends StatefulWidget {
  const StaffListPage({super.key, required this.repository, required this.onOpen});

  final StaffRepository repository;
  final void Function(StaffMember member) onOpen;

  @override
  State<StaffListPage> createState() => _StaffListPageState();
}

class _StaffListPageState extends State<StaffListPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.repository.refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final repo = widget.repository;
        if (repo.noAccess) return NoAccessView(body: l.noAccessStaffBody);
        final everything = repo.all;
        if (!repo.loaded && everything.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final shown = repo.members;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
              child: TextField(
                key: const ValueKey('staff-search'),
                controller: _search,
                onChanged: repo.setQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l.staffSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: repo.refresh,
                child: shown.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsetsDirectional.all(24),
                        children: [
                          if (repo.lastRefreshFailed) _stale(l, repo),
                          const SizedBox(height: 16),
                          Text(_emptyText(l, repo, everything.isEmpty), textAlign: TextAlign.center),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: shown.length + 1,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return repo.lastRefreshFailed
                                ? Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
                                    child: Align(
                                      alignment: AlignmentDirectional.centerStart,
                                      child: _stale(l, repo),
                                    ),
                                  )
                                : const SizedBox.shrink();
                          }
                          return _StaffRow(member: shown[i - 1], onTap: widget.onOpen);
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// "Offline copy" and, when the snapshot has a time, "As of <time>".
  Widget _stale(AppLocalizations l, StaffRepository repo) {
    final at = repo.fetchedAt;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StaleBadge(label: l.ordersRefreshFailed),
        if (at != null) Text(l.dashboardAsOf(formatAsOf(at)), key: const ValueKey('staff-as-of')),
      ],
    );
  }

  String _emptyText(AppLocalizations l, StaffRepository repo, bool cacheEmpty) {
    if (!cacheEmpty) return l.staffNoMatch(repo.query.trim());
    return repo.lastRefreshFailed ? l.staffLoadFailed : l.staffEmpty;
  }
}

/// The names of a member's roles, or "Full access" for an owner, or "No role".
String staffRoleText(AppLocalizations l, StaffMember m) {
  if (m.roles.isEmpty) return m.isSuper ? l.staffFullAccess : l.staffNoRole;
  return m.roles.map((r) => r.name).join(' · ');
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.member, required this.onTap});

  final StaffMember member;
  final void Function(StaffMember member) onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final login = member.lastLoginShort;
    return ListTile(
      key: ValueKey('staff-${member.id}'),
      onTap: () => onTap(member),
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(member.isSelf ? '${member.name} (${l.staffYou})' : member.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (member.email.isNotEmpty)
            Text(member.email, style: t.bodySmall, textDirection: TextDirection.ltr, textAlign: TextAlign.start),
          Text(
            login.isEmpty ? l.staffNeverSignedIn : l.staffLastLogin(isolate(login)),
            style: t.bodySmall,
          ),
        ],
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              staffRoleText(l, member),
              key: ValueKey('staff-role-${member.id}'),
              style: t.labelMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
            if (member.suspended)
              Text(l.staffSuspended, key: ValueKey('staff-suspended-${member.id}'), style: t.labelSmall),
          ],
        ),
      ),
    );
  }
}
