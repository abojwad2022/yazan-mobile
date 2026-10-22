import 'package:yazan_admin/src/orders/order_detail_controller.dart';
import 'package:yazan_admin/src/orders/order_refund.dart';
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

/// One recorded refund POST.
class RefundCall {
  RefundCall(this.id, this.body, this.version, this.key);

  final int id;
  final Map<String, dynamic> body;
  final String version;
  final String key;
}

/// [FakeOrderServer] plus `POST /orders/{id}/refunds` and the refund fields of the order detail.
class FakeRefundServer extends FakeOrderServer {
  String remaining = '129.50';
  bool gatewaySupported = false;
  bool canGateway = false;
  final List<Map<String, dynamic>> refunds = [];

  /// Thrown by the next refund POSTs, in order; `null` means "accept".
  final List<Exception?> refundFailures = [];
  final List<RefundCall> refundCalls = [];

  @override
  Future<VersionedOrder> load(int id) async {
    final r = await super.load(id);
    return (
      body: {
        ...r.body,
        'currency': 'USD',
        'remaining_refund': remaining,
        'gateway_refund_supported': gatewaySupported,
        'can_gateway_refund': canGateway,
        'refunds': [for (final x in refunds) Map<String, dynamic>.from(x)],
      },
      version: r.version,
    );
  }

  Future<Map<String, dynamic>> sendRefund(
    int id,
    RefundDraft draft, {
    required String version,
    required String idempotencyKey,
  }) async {
    refundCalls.add(RefundCall(id, draft.toJson(), version, idempotencyKey));
    final failure = refundFailures.isEmpty ? null : refundFailures.removeAt(0);
    if (failure != null) throw failure;
    final left = (refundMinor(remaining) ?? 0) - (refundMinor(draft.amount) ?? 0);
    remaining = '${left ~/ 100}.${(left % 100).toString().padLeft(2, '0')}';
    refunds.insert(0, {
      'id': 500 + refundCalls.length,
      'amount': draft.amount,
      'reason': draft.reason,
      'date': '2026-10-22 10:00',
      'by': 'Sara',
    });
    version = 'v-after-refund-${refundCalls.length}';
    return (await load(id)).body;
  }
}
