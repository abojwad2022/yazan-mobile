import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import '../dashboard/dashboard_format.dart';
import '../orders/no_access_view.dart';
import 'activity_repository.dart';
import 'activity_snapshot.dart';

/// The dashboard's activity log: who did what, newest first, a page at a time. Read only: entries
/// can never be edited here, and purging old ones stays in the web dashboard.
///
/// The log can be narrowed by action and by object type (the server's own lists), and to one
/// person from an entry's sheet. Action slugs, object references, times, IP addresses and browser
/// strings are machine data and keep left-to-right order in both languages. With [showAppBar] the
/// page brings its own title bar, for use as a pushed route.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.repository, this.showAppBar = false});

  final ActivityRepository repository;
  final bool showAppBar;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  @override
  void initState() {
    super.initState();
    widget.repository.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final body = ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) => _content(context, l),
    );
    if (!widget.showAppBar) return body;
    return Scaffold(appBar: AppBar(title: Text(l.activityTitle)), body: body);
  }

  Widget _content(BuildContext context, AppLocalizations l) {
    final repo = widget.repository;
    if (repo.noAccess) return NoAccessView(body: l.activityNoAccessBody);
    final snap = repo.snapshot;
    final filter = repo.filter;
    if (snap == null && !repo.loaded && filter.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final t = Theme.of(context).textTheme;
    final items = <Widget>[];
    if (snap == null) {
      if (repo.loading) {
        items.add(const Padding(
          padding: EdgeInsetsDirectional.all(24),
          child: Center(child: CircularProgressIndicator()),
        ));
      } else {
        items.add(Padding(
          padding: const EdgeInsetsDirectional.all(24),
          child: Text(l.activityLoadFailed, key: const ValueKey('activity-failed'), textAlign: TextAlign.center),
        ));
      }
    } else if (snap.entries.isEmpty) {
      items.add(Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Text(
          filter.isEmpty ? l.activityEmpty : l.activityNoMatch,
          key: const ValueKey('activity-empty'),
          textAlign: TextAlign.center,
        ),
      ));
    } else {
      for (final e in snap.entries) {
        items.add(_EntryTile(entry: e, onTap: () => _show(e)));
      }
      items.add(_Footer(repository: repo, snapshot: snap));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (snap != null)
                    Text(
                      l.dashboardAsOf(formatAsOf(snap.fetchedAt)),
                      key: const ValueKey('activity-asof'),
                      style: t.bodySmall,
                    ),
                  if (repo.lastRefreshFailed)
                    StaleBadge(key: const ValueKey('activity-stale'), label: l.ordersRefreshFailed),
                ],
              ),
              Text(l.activityReadOnly, key: const ValueKey('activity-readonly'), style: t.bodySmall),
              if (!repo.facets.isEmpty || !filter.isEmpty) _Filters(repository: repo),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: repo.refresh,
            child: ListView(
              key: const ValueKey('activity-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
              children: items,
            ),
          ),
        ),
      ],
    );
  }

  void _show(AuditEntry entry) {
    final repo = widget.repository;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        final l = AppLocalizations.of(sheet);
        final t = Theme.of(sheet).textTheme;
        final canNarrow = !entry.isSystem && repo.filter.userId != entry.userId;
        return SafeArea(
          child: SingleChildScrollView(
            key: const ValueKey('activity-detail'),
            padding: const EdgeInsetsDirectional.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isolate(entry.action), style: t.titleMedium),
                const SizedBox(height: 8),
                _Line(label: l.activityWhen, value: isolate(shortLogTime(entry.date))),
                _Line(
                  key: const ValueKey('activity-detail-actor'),
                  label: l.activityActor,
                  value: actorText(l, entry),
                ),
                if (entry.objectType.isNotEmpty)
                  _Line(
                    key: const ValueKey('activity-detail-object'),
                    label: l.activityObject,
                    value: isolate(objectText(entry)),
                  ),
                if (entry.ip.isNotEmpty)
                  _Line(
                    key: const ValueKey('activity-detail-ip'),
                    label: l.activityIp,
                    value: isolate(entry.ip),
                  ),
                if (entry.userAgent.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(l.activityBrowser, style: t.labelMedium),
                  Text(isolate(entry.userAgent), key: const ValueKey('activity-detail-browser'), style: t.bodySmall),
                ],
                const Divider(height: 24),
                Text(l.activityDetails, style: t.titleSmall),
                const SizedBox(height: 4),
                if (entry.changes.isEmpty)
                  Text(l.activityNoDetails, key: const ValueKey('activity-detail-none'))
                else
                  for (final c in entry.changes.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(vertical: 2),
                      child: Text(
                        // The field slug and its value form one machine line: one isolate.
                        isolate('${c.key}: ${changeValueText(c.value)}'),
                        key: ValueKey('activity-change-${c.key}'),
                        style: t.bodySmall,
                      ),
                    ),
                if (canNarrow) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    key: const ValueKey('activity-filter-actor'),
                    icon: const Icon(Icons.person_search_outlined),
                    label: Text(l.activityShowActorOnly),
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      repo.setFilter(repo.filter.withActor(entry.userId, entry.user));
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Sara #7" in the person's language, the id (and a name that is an email address) isolated left
/// to right; "System" for entries with no actor.
String actorText(AppLocalizations l, AuditEntry e) {
  if (e.isSystem) return l.activitySystem;
  final name = e.user.trim();
  final id = isolate('#${e.userId}');
  if (name.isEmpty || name == '#${e.userId}') return id;
  return '${name.contains('@') ? isolate(name) : name} $id';
}

/// "product #12", or the type alone when the action has no object.
String objectText(AuditEntry e) => e.objectId > 0 ? '${e.objectType} #${e.objectId}' : e.objectType;

class _Filters extends StatelessWidget {
  const _Filters({required this.repository});

  final ActivityRepository repository;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final repo = repository;
    final filter = repo.filter;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SlugDropdown(
                  key: const ValueKey('activity-filter-action'),
                  label: l.activityFilterAction,
                  allLabel: l.activityAllActions,
                  value: filter.action,
                  options: repo.facets.actions,
                  onChanged: (v) => repo.setFilter(filter.withAction(v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SlugDropdown(
                  key: const ValueKey('activity-filter-type'),
                  label: l.activityFilterType,
                  allLabel: l.activityAllTypes,
                  value: filter.objectType,
                  options: repo.facets.objectTypes,
                  onChanged: (v) => repo.setFilter(filter.withObjectType(v)),
                ),
              ),
            ],
          ),
          if (!filter.isEmpty)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (filter.userId > 0)
                  InputChip(
                    key: const ValueKey('activity-actor-filter'),
                    label: Text(l.activityOnlyActor(
                      filter.userName.isEmpty ? isolate('#${filter.userId}') : filter.userName,
                    )),
                    onDeleted: () => repo.setFilter(filter.withActor(0, '')),
                  ),
                TextButton(
                  key: const ValueKey('activity-clear-filters'),
                  onPressed: () => repo.setFilter(const ActivityFilter()),
                  child: Text(l.activityClearFilters),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A choice among machine slugs, with "all" first. The current value is always offered, even when
/// the server's list no longer has it.
class _SlugDropdown extends StatelessWidget {
  const _SlugDropdown({
    super.key,
    required this.label,
    required this.allLabel,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String allLabel;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final slugs = <String>{...options, if (value.isNotEmpty) value}.toList();
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 4, 8, 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            DropdownMenuItem(value: '', child: Text(allLabel, overflow: TextOverflow.ellipsis)),
            for (final s in slugs)
              DropdownMenuItem(value: s, child: Text(isolate(s), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null && v != value) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final AuditEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final id = entry.id;
    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      child: ListTile(
        key: ValueKey('activity-entry-$id'),
        onTap: onTap,
        leading: _ToneIcon(tone: actionTone(entry.action)),
        title: Text(
          isolate(entry.action),
          key: ValueKey('activity-entry-$id-action'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.objectType.isNotEmpty)
              Text(isolate(objectText(entry)), key: ValueKey('activity-entry-$id-object')),
            Text(
              l.activityBy(actorText(l, entry)),
              key: ValueKey('activity-entry-$id-actor'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              isolate(shortLogTime(entry.date)),
              key: ValueKey('activity-entry-$id-time'),
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToneIcon extends StatelessWidget {
  const _ToneIcon({required this.tone});

  final ActionTone tone;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final (icon, color) = switch (tone) {
      ActionTone.danger => (Icons.delete_outline, c.error),
      ActionTone.ok => (Icons.add_circle_outline, c.primary),
      ActionTone.warn => (Icons.warning_amber_outlined, c.tertiary),
      ActionTone.muted => (Icons.login, c.outline),
      ActionTone.info => (Icons.edit_note_outlined, c.secondary),
    };
    return Icon(icon, color: color);
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.repository, required this.snapshot});

  final ActivityRepository repository;
  final ActivitySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final repo = repository;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 8),
      child: Column(
        children: [
          Text(
            l.activityShown(snapshot.entries.length, snapshot.total),
            key: const ValueKey('activity-count'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (repo.loadMoreFailed)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 8),
              child: Text(l.activityLoadMoreFailed, key: const ValueKey('activity-more-failed')),
            ),
          const SizedBox(height: 8),
          if (repo.loadingMore)
            const SizedBox(
              key: ValueKey('activity-loading-more'),
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (snapshot.hasMore)
            OutlinedButton(
              key: const ValueKey('activity-load-more'),
              onPressed: repo.loading ? null : repo.loadMore,
              child: Text(repo.loadMoreFailed ? l.retry : l.activityLoadMore),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Flexible(
              flex: 2,
              child: Text(value, textAlign: TextAlign.end, style: Theme.of(context).textTheme.titleSmall),
            ),
          ],
        ),
      );
}
