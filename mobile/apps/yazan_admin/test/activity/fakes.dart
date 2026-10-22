import 'package:yazan_admin/src/activity/activity_repository.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../dashboard/fakes.dart' show fixedNow;

/// One `items[]` row of `GET /yazan/v1/audit`, as the server sends it.
Map<String, dynamic> auditRow({
  required int id,
  required int userId,
  required String user,
  required String action,
  String objectType = '',
  int objectId = 0,
  Object changes = const <dynamic>[],
  String ip = '',
  String userAgent = '',
  required String date,
}) =>
    {
      'id': id,
      'user_id': userId,
      'user': user,
      'action': action,
      'object_type': objectType,
      'object_id': objectId,
      'changes': changes,
      'ip': ip,
      'user_agent': userAgent,
      'store_id': 1,
      'date': date,
    };

/// The log, newest first:
///  5. Sara (#7) updated product #12: price and a stock diff, from the app, with IP and browser.
///  4. Omar (#9) deleted product #13, nothing recorded (PHP's empty `[]`).
///  3. owner@yazan.test (#1) signed in.
///  2. The system pushed a new-order notice for order #55.
///  1. Sara (#7) created order #55.
List<Map<String, dynamic>> auditLog() => [
      auditRow(
        id: 5,
        userId: 7,
        user: 'Sara',
        action: 'product.update',
        objectType: 'product',
        objectId: 12,
        changes: {
          'regular_price': '120.00',
          'stock': {'old': 3, 'new': 5},
        },
        ip: '203.0.113.9',
        userAgent: 'YazanAdmin/0.1 (Android 14)',
        date: '2026-10-20 14:05:00',
      ),
      auditRow(
        id: 4,
        userId: 9,
        user: 'Omar',
        action: 'product.delete',
        objectType: 'product',
        objectId: 13,
        date: '2026-10-20 13:00:00',
      ),
      auditRow(
        id: 3,
        userId: 1,
        user: 'owner@yazan.test',
        action: 'auth.login',
        objectType: 'auth',
        date: '2026-10-20 09:30:00',
      ),
      auditRow(
        id: 2,
        userId: 0,
        user: 'System',
        action: 'mobile.push',
        objectType: 'order',
        objectId: 55,
        changes: {'type': 'new_order', 'sent': 2},
        date: '2026-10-19 18:00:00',
      ),
      auditRow(
        id: 1,
        userId: 7,
        user: 'Sara',
        action: 'order.create',
        objectType: 'order',
        objectId: 55,
        date: '2026-10-19 17:59:00',
      ),
    ];

/// A scripted stand-in for `GET /yazan/v1/audit` that filters and pages like the server (newest
/// first, `total_pages` = ceil(total / per_page), facets over the whole log). No network anywhere.
class FakeAuditServer {
  List<Map<String, dynamic>> rows = auditLog();

  /// When set, every call throws it (and it stays set until cleared).
  Object? failure;

  /// The query of every call, in order.
  final List<Map<String, dynamic>> asked = [];

  Future<Map<String, dynamic>> fetch(Map<String, dynamic> query) async {
    asked.add(Map<String, dynamic>.from(query));
    if (failure != null) throw failure!;
    return answer(query);
  }

  Map<String, dynamic> answer(Map<String, dynamic> query) {
    final perPage = int.parse('${query['per_page'] ?? 50}');
    final page = int.parse('${query['page'] ?? 1}');
    final action = '${query['action_filter'] ?? ''}';
    final type = '${query['object_type'] ?? ''}';
    final user = int.tryParse('${query['user_id'] ?? ''}') ?? 0;
    final matching = [
      for (final r in rows)
        if ((action.isEmpty || r['action'] == action) &&
            (type.isEmpty || r['object_type'] == type) &&
            (user == 0 || r['user_id'] == user))
          r,
    ];
    final start = (page - 1) * perPage;
    final end = start + perPage > matching.length ? matching.length : start + perPage;
    return {
      'items': start >= matching.length ? <dynamic>[] : matching.sublist(start, end),
      'total': matching.length,
      'total_pages': (matching.length / perPage).ceil(),
      'page': page,
      'per_page': perPage,
      'facets': {
        'actions': ({for (final r in rows) '${r['action']}'}.toList()..sort()),
        'object_types': ({for (final r in rows) '${r['object_type']}'}.toList()..sort()),
      },
    };
  }

  void goOffline() => failure = Exception('offline');

  ActivityRepository repository({FeedStore? store, int perPage = 50}) => ActivityRepository(
        fetch: fetch,
        store: store,
        clock: () => fixedNow,
        perPage: perPage,
      );
}
