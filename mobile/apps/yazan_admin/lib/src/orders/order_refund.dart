import 'package:yazan_domain/yazan_domain.dart';

import '../products/product_input.dart' show parsePriceInput, plainPrice;
import 'order_detail_controller.dart' show OrderNote;

// Refunds from the order screen. The route and body are the web dashboard's
// (`dashboard-app/src/pages/OrderDetail.jsx` RefundCard -> `ordersApi.createRefund`):
//
//   POST /yazan/v1/orders/{id}/refunds  {amount, reason, restock, refund_payment}
//
// Permission `orders.refund`; `refund_payment: true` also needs `orders.refund_gateway` and a
// gateway that supports refunds (the order detail says so in `can_gateway_refund` and
// `gateway_refund_supported`). The server refuses more than `remaining_refund`, restocks only a
// refund of the whole remaining amount, and answers 201 with the order detail. A phone admin
// session must send `If-Match` (the refunds route is version-guarded) and gets exactly-once
// execution per `Idempotency-Key`.

/// Sends `POST /yazan/v1/orders/{id}/refunds` with `If-Match` and `Idempotency-Key`.
/// Throws [ApiError] for a server answer; any other exception means "no answer" (offline or lost).
typedef RefundSender = Future<Map<String, dynamic>> Function(
  int id,
  RefundDraft draft, {
  required String version,
  required String idempotencyKey,
});

/// What the person asked for in the refund sheet. [amount] is canonical ("12.50").
class RefundDraft {
  const RefundDraft({
    required this.amount,
    this.reason = '',
    this.restock = false,
    this.viaGateway = false,
  });

  final String amount;
  final String reason;
  final bool restock;
  final bool viaGateway;

  /// The exact request body. A retry sends this same map under the same key, so the server's
  /// idempotency fingerprint matches and a refund that already went through is replayed, not redone.
  Map<String, dynamic> toJson() => {
        'amount': amount,
        'reason': reason,
        'restock': restock,
        'refund_payment': viaGateway,
      };

  @override
  bool operator ==(Object other) =>
      other is RefundDraft &&
      other.amount == amount &&
      other.reason == reason &&
      other.restock == restock &&
      other.viaGateway == viaGateway;

  @override
  int get hashCode => Object.hash(amount, reason, restock, viaGateway);
}

/// What happened to a refund.
///
/// [invalid] and [tooMuch] are local refusals: nothing was sent. [changed] is a 412 (the order
/// changed since it was opened); nothing was written and the order has been read again.
enum RefundResult { done, invalid, tooMuch, offline, busy, changed, noAccess, failed }

/// Local check of a typed amount against what is still refundable.
enum RefundAmountCheck { ok, invalid, zero, tooMuch }

/// [raw] is what was typed (Arabic-Indic digits allowed); [remaining] is the server's
/// `remaining_refund`. Compared in minor units, never as doubles.
RefundAmountCheck checkRefundAmount(String raw, String remaining) {
  final typed = parsePriceInput(raw);
  if (typed == null || typed.minor < 0) return RefundAmountCheck.invalid;
  if (typed.minor == 0) return RefundAmountCheck.zero;
  final left = refundMinor(remaining);
  if (left == null || typed.minor > left) return RefundAmountCheck.tooMuch;
  return RefundAmountCheck.ok;
}

/// A server decimal ("129.5", "129.500") in minor units, or null when unreadable.
int? refundMinor(String raw) {
  final plain = plainPrice(raw);
  if (plain.isEmpty) return null;
  try {
    return Money.parse(plain, currency: 'X').minor;
  } on FormatException {
    return null;
  }
}

/// A typed amount as the canonical decimal the server gets ("50" -> "50.00").
String canonicalRefundAmount(String raw) => parsePriceInput(raw)?.toDecimalString() ?? '';

/// One refund already recorded on the order (`refunds[]` of the order detail).
class OrderRefund {
  const OrderRefund({
    required this.id,
    required this.amount,
    required this.reason,
    required this.date,
    required this.by,
  });

  factory OrderRefund.fromJson(Map<dynamic, dynamic> json) {
    final id = json['id'];
    return OrderRefund(
      id: id is int ? id : int.tryParse('${id ?? ''}') ?? 0,
      amount: plainPrice('${json['amount'] ?? ''}'),
      reason: '${json['reason'] ?? ''}',
      date: '${json['date'] ?? ''}',
      by: '${json['by'] ?? ''}',
    );
  }

  static List<OrderRefund> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final r in raw)
        if (r is Map) OrderRefund.fromJson(r),
    ];
  }

  final int id;
  final String amount;
  final String reason;
  final String date;
  final String by;
}

/// A server message as plain text: tags dropped, the common entities decoded, at most 300
/// characters. Gateway errors can carry HTML; the app never renders it.
String safeServerMessage(String raw) {
  final text = OrderNote.plainText(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length > 300 ? '${text.substring(0, 300)}…' : text;
}
