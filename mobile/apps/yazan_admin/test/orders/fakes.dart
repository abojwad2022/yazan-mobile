import 'package:yazan_admin/src/orders/order_detail_controller.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

/// One recorded status write.
class StatusCall {
  StatusCall(this.status, this.version, this.key);

  final String status;
  final String version;
  final String key;
}

/// An in-memory stand-in for the order endpoints. No network anywhere.
class FakeOrderServer {
  String status = 'processing';
  String? version = 'v1';
  bool includeNotes = true;
  final List<Map<String, dynamic>> notes = [];

  /// Thrown by the next status writes, in order; `null` means "accept".
  final List<Exception?> statusFailures = [];
  final List<StatusCall> statusCalls = [];

  /// When false, the outbox sender fails as if there were no network.
  bool online = true;
  final List<OutboxOp> sentOps = [];
  int loads = 0;

  Future<VersionedOrder> load(int id) async {
    loads++;
    final Map<String, dynamic> body = {
      'id': id,
      'status': status,
      'payment_method': 'Card',
      if (includeNotes) 'notes': [for (final n in notes) Map<String, dynamic>.from(n)],
    };
    return (body: body, version: version);
  }

  Future<Map<String, dynamic>> sendStatus(
    int id,
    String status, {
    required String version,
    required String idempotencyKey,
  }) async {
    statusCalls.add(StatusCall(status, version, idempotencyKey));
    final failure = statusFailures.isEmpty ? null : statusFailures.removeAt(0);
    if (failure != null) throw failure;
    this.status = status;
    this.version = 'v-after-$status';
    final Map<String, dynamic> body = {'id': id, 'status': status};
    return body;
  }

  Future<void> sendOp(OutboxOp op) async {
    if (!online) throw Exception('offline');
    sentOps.add(op);
    notes.insert(0, {
      'id': 100 + sentOps.length,
      'author': 'Sara',
      'date': '2026-10-20 10:00',
      'content': '${op.body?['note'] ?? ''}',
      'customer_note': false,
      'system': false,
    });
  }
}

/// Deterministic Idempotency-Keys: key-1, key-2, ...
class KeySeq {
  int _n = 0;

  String next() => 'key-${++_n}';
}
