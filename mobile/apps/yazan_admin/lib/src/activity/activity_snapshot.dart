import 'dart:convert';

// The dashboard's activity log (`GET /yazan/v1/audit`) as the app shows it, kept for offline
// viewing. Parsing never throws: a field the server leaves out reads as empty.

/// One row of the log (`items[]`).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.userId,
    required this.user,
    required this.action,
    required this.objectType,
    required this.objectId,
    required this.changes,
    required this.ip,
    required this.userAgent,
    required this.date,
  });

  final int id;

  /// Who did it; 0 for the system (a scheduled job, a webhook).
  final int userId;

  /// The actor's display name as the server resolved it.
  final String user;

  /// Dotted machine slug, `product.update`, `auth.login`… Never translated.
  final String action;
  final String objectType;

  /// 0 when the action has no object.
  final int objectId;

  /// The recorded diff or context, as the server decoded it (scalars, lists and maps).
  final Map<String, dynamic> changes;
  final String ip;
  final String userAgent;

  /// The store's local time as the server stores it, `2026-10-20 14:05:00`.
  final String date;

  bool get isSystem => userId == 0;

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: _int(j['id']) ?? 0,
        userId: _int(j['user_id']) ?? 0,
        user: '${j['user'] ?? ''}',
        action: '${j['action'] ?? ''}',
        objectType: '${j['object_type'] ?? ''}',
        objectId: _int(j['object_id']) ?? 0,
        changes: _changes(j['changes']),
        ip: '${j['ip'] ?? ''}',
        userAgent: '${j['user_agent'] ?? ''}',
        date: '${j['date'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'user': user,
        'action': action,
        'object_type': objectType,
        'object_id': objectId,
        'changes': changes,
        'ip': ip,
        'user_agent': userAgent,
        'date': date,
      };
}

/// The distinct action and object-type slugs in the log, for the filters (`facets`).
class AuditFacets {
  const AuditFacets({this.actions = const [], this.objectTypes = const []});

  final List<String> actions;
  final List<String> objectTypes;

  bool get isEmpty => actions.isEmpty && objectTypes.isEmpty;

  factory AuditFacets.fromJson(Object? v) {
    if (v is! Map) return const AuditFacets();
    return AuditFacets(actions: _slugs(v['actions']), objectTypes: _slugs(v['object_types']));
  }

  Map<String, dynamic> toJson() => {'actions': actions, 'object_types': objectTypes};
}

/// What the log is narrowed to. Every part is optional; the empty filter is the whole log.
class ActivityFilter {
  const ActivityFilter({this.action = '', this.objectType = '', this.userId = 0, this.userName = ''});

  final String action;
  final String objectType;

  /// One actor's entries only (0: everyone). [userName] is only for the chip that shows it.
  final int userId;
  final String userName;

  bool get isEmpty => action.isEmpty && objectType.isEmpty && userId == 0;

  ActivityFilter withAction(String value) =>
      ActivityFilter(action: value, objectType: objectType, userId: userId, userName: userName);

  ActivityFilter withObjectType(String value) =>
      ActivityFilter(action: action, objectType: value, userId: userId, userName: userName);

  ActivityFilter withActor(int id, String name) =>
      ActivityFilter(action: action, objectType: objectType, userId: id, userName: name);

  /// The query parameters of `GET /yazan/v1/audit` (the action filter is `action_filter` there).
  Map<String, dynamic> toQuery() => {
        if (action.isNotEmpty) 'action_filter': action,
        if (objectType.isNotEmpty) 'object_type': objectType,
        if (userId > 0) 'user_id': '$userId',
      };

  @override
  bool operator ==(Object other) =>
      other is ActivityFilter &&
      other.action == action &&
      other.objectType == objectType &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(action, objectType, userId);
}

/// The pages of the log read so far, newest first.
class ActivitySnapshot {
  const ActivitySnapshot({
    required this.fetchedAt,
    required this.entries,
    required this.page,
    required this.totalPages,
    required this.total,
    required this.facets,
  });

  /// When the first page arrived.
  final DateTime fetchedAt;
  final List<AuditEntry> entries;

  /// The last page read.
  final int page;
  final int totalPages;

  /// Matching entries on the server.
  final int total;
  final AuditFacets facets;

  bool get hasMore => page < totalPages;

  factory ActivitySnapshot.fromServer(Map<String, dynamic> j, {required DateTime fetchedAt}) =>
      ActivitySnapshot(
        fetchedAt: fetchedAt,
        entries: _entries(j['items']),
        page: _int(j['page']) ?? 1,
        totalPages: _int(j['total_pages']) ?? 0,
        total: _int(j['total']) ?? 0,
        facets: AuditFacets.fromJson(j['facets']),
      );

  /// [next] read after this one. Rows already shown are not repeated: newer entries push older ones
  /// down the server's pages, so the next page can begin with rows this one already has.
  ActivitySnapshot append(ActivitySnapshot next) {
    final seen = {for (final e in entries) e.id};
    return ActivitySnapshot(
      fetchedAt: fetchedAt,
      entries: [
        ...entries,
        for (final e in next.entries)
          if (seen.add(e.id)) e,
      ],
      page: next.page,
      totalPages: next.totalPages,
      total: next.total,
      facets: next.facets.isEmpty ? facets : next.facets,
    );
  }

  factory ActivitySnapshot.fromJson(Map<String, dynamic> j) => ActivitySnapshot(
        fetchedAt: DateTime.tryParse('${j['fetched_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        entries: _entries(j['items']),
        page: _int(j['page']) ?? 1,
        totalPages: _int(j['total_pages']) ?? 0,
        total: _int(j['total']) ?? 0,
        facets: AuditFacets.fromJson(j['facets']),
      );

  Map<String, dynamic> toJson() => {
        'fetched_at': fetchedAt.toIso8601String(),
        'items': [for (final e in entries) e.toJson()],
        'page': page,
        'total_pages': totalPages,
        'total': total,
        'facets': facets.toJson(),
      };
}

/// How an action reads at a glance, so destructive events stand out (the web dashboard's colours).
enum ActionTone { danger, ok, warn, muted, info }

ActionTone actionTone(String action) {
  if (RegExp('delete|purge|refund_failed').hasMatch(action)) return ActionTone.danger;
  if (action.contains('create')) return ActionTone.ok;
  if (RegExp('refund|bulk').hasMatch(action)) return ActionTone.warn;
  if (RegExp('login|logout').hasMatch(action)) return ActionTone.muted;
  return ActionTone.info;
}

/// One recorded value as text: a list one entry per line, anything structured as JSON (never
/// Dart's `{a: 1}`), empty as "-".
String changeValueText(Object? value) {
  if (value == null) return '-';
  if (value is List) {
    if (value.isEmpty) return '-';
    return [for (final v in value) v is Map || v is List ? jsonEncode(v) : '$v'].join('\n');
  }
  if (value is Map) return jsonEncode(value);
  final text = '$value';
  return text.isEmpty ? '-' : text;
}

/// `2026-10-20 14:05:00` → `2026-10-20 14:05`; anything else as sent.
String shortLogTime(String date) {
  final m = RegExp(r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})').firstMatch(date.trim());
  return m == null ? date.trim() : '${m.group(1)} ${m.group(2)}';
}

List<AuditEntry> _entries(Object? v) => v is List
    ? [for (final e in v) if (e is Map) AuditEntry.fromJson(Map<String, dynamic>.from(e))]
    : const [];

/// PHP sends an empty diff as `[]`; a non-empty list keeps its positions as keys.
Map<String, dynamic> _changes(Object? v) {
  if (v is Map) return {for (final e in v.entries) '${e.key}': e.value};
  if (v is List) return {for (var i = 0; i < v.length; i++) '$i': v[i]};
  return const {};
}

List<String> _slugs(Object? v) => v is List
    ? [for (final e in v) if (e != null && '$e'.isNotEmpty) '$e']
    : const [];

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}');
}
