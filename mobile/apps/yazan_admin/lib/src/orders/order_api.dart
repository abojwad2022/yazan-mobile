import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'order_detail_controller.dart';
import 'order_refund.dart';

// Production wiring of the order screen's injected functions. Routes and bodies are the web
// dashboard's (`dashboard-app/src/api/endpoints.js` -> `Yazan_REST_Orders`).

/// `GET /yazan/v1/orders/{id}`; a phone admin session gets the version token as the ETag.
VersionedOrderLoader orderLoader(YazanApiClient client) =>
    (id) => client.getJsonWithVersion('/yazan/v1/orders/$id');

/// `PUT /yazan/v1/orders/{id}` `{status}` — what the dashboard's `ordersApi.update` sends.
StatusSender statusSender(YazanApiClient client) => (
      int id,
      String status, {
      required String version,
      required String idempotencyKey,
    }) =>
        client.sendJson(
          'PUT',
          '/yazan/v1/orders/$id',
          data: {'status': status},
          idempotencyKey: idempotencyKey,
          ifMatch: version,
        );

/// `POST /yazan/v1/orders/{id}/refunds` `{amount, reason, restock, refund_payment}` — what the
/// dashboard's `ordersApi.createRefund` sends. Online only, never through the outbox. The route is
/// version-guarded for a phone session (`If-Match`, else 428) and exactly-once per
/// `Idempotency-Key`; it answers 201 with the order detail.
RefundSender refundSender(YazanApiClient client) => (
      int id,
      RefundDraft draft, {
      required String version,
      required String idempotencyKey,
    }) =>
        client.sendJson(
          'POST',
          '/yazan/v1/orders/$id/refunds',
          data: draft.toJson(),
          idempotencyKey: idempotencyKey,
          ifMatch: version,
        );

/// Sends one outbox op (order notes: `POST /yazan/v1/orders/{id}/notes` `{note, customer_note}`).
/// Notes are append-only, so no If-Match unless the op carries a base version.
OpSender outboxSender(YazanApiClient client) => (OutboxOp op) async {
      try {
        await client.sendJson(
          op.method,
          op.path,
          data: op.body,
          idempotencyKey: op.idempotencyKey,
          ifMatch: op.baseVersion,
        );
      } on TypeError {
        // The notes route answers 201 with a JSON list, which `sendJson` cannot return as a map.
        // A TypeError is only raised after a 2xx answer, so the note was accepted.
      }
    };
