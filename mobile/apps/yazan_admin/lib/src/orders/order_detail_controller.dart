import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../more/staff_permissions.dart';
import '../products/product_input.dart' show plainPrice;
import '../products/product_permissions.dart' show PermissionsLoader;
import 'order_refund.dart';

/// An order body plus its version token (the ETag, quotes stripped).
typedef VersionedOrder = ({Map<String, dynamic> body, String? version});

/// Loads `/yazan/v1/orders/{id}` with its version.
typedef VersionedOrderLoader = Future<VersionedOrder> Function(int id);

/// Loads the notes list when the order payload does not carry one.
typedef NotesLoader = Future<List<Map<String, dynamic>>> Function(int id);

/// Sends `PUT /yazan/v1/orders/{id}` `{status}` with `If-Match` and `Idempotency-Key`.
/// Throws [ApiError] for a server answer; any other exception means "no network".
typedef StatusSender = Future<Map<String, dynamic>> Function(
  int id,
  String status, {
  required String version,
  required String idempotencyKey,
});

/// What happened to a status change.
enum StatusResult { done, offline, busy, conflict, noAccess, failed }

/// The order statuses the web dashboard offers (WooCommerce's core list).
const List<String> orderStatuses = [
  'pending',
  'processing',
  'on-hold',
  'completed',
  'cancelled',
  'refunded',
  'failed',
];

/// One order note as `/yazan/v1/orders/{id}` (or `/notes`) sends it. Parsing never throws.
class OrderNote {
  const OrderNote({
    required this.id,
    required this.content,
    required this.author,
    required this.date,
    required this.toCustomer,
    required this.system,
  });

  factory OrderNote.fromJson(Map<dynamic, dynamic> json) {
    final id = json['id'];
    return OrderNote(
      id: id is int ? id : int.tryParse('${id ?? ''}') ?? 0,
      content: plainText('${json['content'] ?? ''}'),
      author: '${json['author'] ?? ''}',
      date: '${json['date'] ?? ''}',
      toCustomer: json['customer_note'] == true,
      system: json['system'] == true,
    );
  }

  static List<OrderNote> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final n in raw)
        if (n is Map) OrderNote.fromJson(n),
    ];
  }

  /// The server sends note HTML (kses-filtered); the app shows text only.
  static String plainText(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&amp;', '&')
      .trim();

  final int id;
  final String content;
  final String author;
  final String date;
  final bool toCustomer;
  final bool system;
}

/// A 412 on a status change: what the person chose against what the server has now.
class StatusConflict {
  const StatusConflict({required this.mine, required this.serverStatus, this.serverVersion});

  final String mine;
  final String serverStatus;
  final String? serverVersion;
}

class _RefundAttempt {
  _RefundAttempt(this.draft, this.key, this.version);

  final RefundDraft draft;

  /// Created once per refund; "Try again" sends the same key, body and If-Match, so a refund whose
  /// answer was lost is replayed by the server, never made twice.
  final String key;
  final String version;
}

class _Attempt {
  _Attempt(this.status, this.key);

  final String status;

  /// Created once per attempt; every retry of this attempt sends the same key.
  final String key;
}

/// State and actions of one order screen. Everything that talks to the network is injected.
///
/// * Status changes are online-only: a network failure keeps the attempt (same key) for a retry and
///   never queues anything.
/// * Notes are append-only: they go through the outbox ([SyncEngine]) so one written offline is sent
///   later, exactly once (the op's idempotency key).
/// * Refunds are online-only like status changes and never touch the outbox: one attempt (key,
///   body, base version) is kept for "Try again" after a lost answer.
class OrderDetailController extends ChangeNotifier {
  OrderDetailController({
    required this.orderId,
    required this.accountId,
    required String initialStatus,
    required String fallbackVersion,
    required VersionedOrderLoader load,
    required StatusSender sendStatus,
    required SyncEngine sync,
    NotesLoader? loadNotes,
    String Function()? newKey,
    RefundSender? sendRefund,
    StaffPermissions permissions = const StaffPermissions.unknown(),
    PermissionsLoader? loadPermissions,
  })  : _initialStatus = initialStatus,
        _fallbackVersion = fallbackVersion,
        _load = load,
        _sendStatus = sendStatus,
        _sync = sync,
        _loadNotes = loadNotes,
        _sendRefund = sendRefund,
        _permissions = permissions,
        _loadPermissions = loadPermissions,
        _newKey = newKey ?? YazanApiClient.newIdempotencyKey;

  final int orderId;
  final String accountId;
  final String _initialStatus;
  final String _fallbackVersion;
  final VersionedOrderLoader _load;
  final StatusSender _sendStatus;
  final SyncEngine _sync;
  final NotesLoader? _loadNotes;
  final String Function() _newKey;
  final RefundSender? _sendRefund;
  final PermissionsLoader? _loadPermissions;
  StaffPermissions _permissions;

  Map<String, dynamic>? _detail;
  String? _version;
  bool _loading = true;
  bool _failed = false;
  bool _noAccess = false;
  bool _sending = false;
  bool _syncing = false;
  bool _disposed = false;
  List<OrderNote> _notes = const [];
  List<OutboxOp> _pendingNotes = const [];
  _Attempt? _attempt;
  StatusConflict? _conflict;
  StatusResult? _lastResult;
  String _lastMessage = '';
  _RefundAttempt? _refund;
  bool _refunding = false;
  RefundResult? _refundResult;
  String _refundMessage = '';
  bool _refundWasGateway = false;

  Map<String, dynamic>? get detail => _detail;

  /// The version the next write is based on: the ETag of the last read, else the feed's token.
  String get version {
    final v = _version;
    return v == null || v.isEmpty ? _fallbackVersion : v;
  }

  bool get loading => _loading;
  bool get failed => _failed;

  /// The order itself may not be viewed.
  bool get noAccess => _noAccess;
  bool get sending => _sending;
  bool get syncing => _syncing;
  List<OrderNote> get notes => _notes;

  /// Notes written here that are still in the outbox (pending, sending or failed).
  List<OutboxOp> get pendingNotes => _pendingNotes;
  StatusConflict? get conflict => _conflict;

  /// Outcome of the last status change, for the inline message; null once it is dismissed.
  StatusResult? get lastResult => _lastResult;

  /// The server's message for [StatusResult.failed], when it sent one.
  String get lastMessage => _lastMessage;

  /// True when [retryStatus] has an attempt to resend.
  bool get canRetry => _attempt != null;

  String get status {
    final d = _detail;
    final s = d == null ? null : d['status'];
    return s is String && s.isNotEmpty ? s : _initialStatus;
  }

  String get notesPath => '/yazan/v1/orders/$orderId/notes';

  static bool _forbidden(ApiError e) => e.action == ErrorAction.hideFeature || e.status == 403;

  // ---- reading ---------------------------------------------------------------------------------

  Future<void> load() async {
    _loading = true;
    _failed = false;
    _noAccess = false;
    _notify();
    try {
      final r = await _load(orderId);
      await _apply(r);
    } on ApiError catch (e) {
      _noAccess = _forbidden(e);
      _failed = true;
    } on Exception {
      _failed = true;
    }
    if (!_permissions.known) {
      final loader = _loadPermissions;
      if (loader != null) {
        try {
          _permissions = StaffPermissions.fromMe(await loader());
        } on Exception {
          // Refunds stay hidden until the permissions can be read.
        }
      }
    }
    _loading = false;
    await refreshPending();
    _notify();
  }

  Future<void> _apply(VersionedOrder r) async {
    _detail = r.body;
    _version = r.version;
    final loader = _loadNotes;
    if (r.body.containsKey('notes')) {
      _notes = OrderNote.listFrom(r.body['notes']);
    } else if (loader != null) {
      try {
        _notes = OrderNote.listFrom(await loader(orderId));
      } on Exception {
        // Keep the notes already shown.
      }
    }
  }

  // ---- status (online-only) --------------------------------------------------------------------

  /// Starts a status change, or resends the open attempt when it is for the same status.
  Future<StatusResult> changeStatus(String target) {
    final open = _attempt;
    final attempt = open != null && open.status == target ? open : _Attempt(target, _newKey());
    _attempt = attempt;
    return _send(attempt);
  }

  /// Resends the open attempt with the same Idempotency-Key.
  Future<StatusResult> retryStatus() async {
    final open = _attempt;
    if (open == null) return StatusResult.failed;
    return _send(open);
  }

  /// Dismisses the inline message and forgets the open attempt.
  void dismissStatus() {
    _attempt = null;
    _lastResult = null;
    _notify();
  }

  Future<StatusResult> _send(_Attempt attempt) async {
    _sending = true;
    _lastResult = null;
    _lastMessage = '';
    _notify();
    final result = await _sendOnce(attempt);
    _lastResult = result == StatusResult.conflict ? null : result;
    _sending = false;
    _notify();
    return result;
  }

  Future<StatusResult> _sendOnce(_Attempt attempt) async {
    try {
      final body = await _sendStatus(
        orderId,
        attempt.status,
        version: version,
        idempotencyKey: attempt.key,
      );
      _attempt = null;
      _detail = body;
      // A write answers without an ETag: read the record again for its new version.
      try {
        await _apply(await _load(orderId));
      } on Exception {
        // The status changed; the next write would get a 412 and show the conflict screen.
      }
      return StatusResult.done;
    } on ApiError catch (e) {
      switch (e.action) {
        case ErrorAction.showConflict:
          return _openConflict(attempt, e);
        case ErrorAction.waitAndRetrySameKey:
          return StatusResult.busy;
        default:
          if (_forbidden(e)) {
            _attempt = null;
            return StatusResult.noAccess;
          }
          _lastMessage = e.message;
          return StatusResult.failed;
      }
    } on Exception {
      // No network. Nothing is queued: the attempt (and its key) waits for "Try again".
      return StatusResult.offline;
    }
  }

  Future<StatusResult> _openConflict(_Attempt attempt, ApiError e) async {
    try {
      final r = await _load(orderId);
      final s = r.body['status'];
      _conflict = StatusConflict(
        mine: attempt.status,
        serverStatus: s is String ? s : '',
        serverVersion: r.version ?? e.current,
      );
      return StatusResult.conflict;
    } on Exception {
      return StatusResult.offline;
    }
  }

  /// "Keep server version": drop the local choice and show the server's copy.
  Future<void> keepServer() async {
    _conflict = null;
    _attempt = null;
    await load();
  }

  /// "Overwrite with mine": send the same status again against the server's current version.
  ///
  /// This is a new attempt with a new key: the 412 wrote nothing, and the server never finishes
  /// the idempotency record of a request its precondition gate refused.
  Future<StatusResult> overwrite() async {
    final c = _conflict;
    if (c == null) return StatusResult.failed;
    _conflict = null;
    final v = c.serverVersion;
    if (v != null && v.isNotEmpty) _version = v;
    final attempt = _Attempt(c.mine, _newKey());
    _attempt = attempt;
    return _send(attempt);
  }

  // ---- refunds (online-only) -------------------------------------------------------------------

  StaffPermissions get permissions => _permissions;

  /// The server's `remaining_refund` as "12.50"; empty before the load.
  String get remainingRefund {
    final v = _detail?['remaining_refund'];
    return v == null ? '' : plainPrice('$v');
  }

  String get currency {
    final v = _detail?['currency'];
    return v is String ? v : '';
  }

  List<OrderRefund> get refunds => OrderRefund.listFrom(_detail?['refunds']);

  /// Something is still refundable on this order, as the server last said.
  bool get hasRefundable => (refundMinor(remainingRefund) ?? 0) > 0;

  /// The Refund button shows only when the server's permission map grants `orders.refund`
  /// (unknown permissions keep it hidden) and something is left to refund. The server re-checks.
  bool get canRefund =>
      _sendRefund != null &&
      _detail != null &&
      _permissions.known &&
      _permissions.allows('orders.refund') &&
      hasRefundable;

  /// A gateway refund is offered only when the order detail says both that the payment method can
  /// refund and that this account may send money back (`orders.refund_gateway`).
  bool get gatewayRefundAvailable =>
      _detail?['gateway_refund_supported'] == true && _detail?['can_gateway_refund'] == true;

  String get paymentMethod {
    final v = _detail?['payment_method'];
    return v == null ? '' : '$v';
  }

  bool get refunding => _refunding;

  /// Outcome of the last refund, for the inline message; null after a success or a dismissal.
  RefundResult? get refundResult => _refundResult;

  /// The server's message (plain text) for [RefundResult.failed] / [RefundResult.noAccess].
  String get refundMessage => _refundMessage;

  /// True while a refund attempt waits for "Try again".
  bool get refundPending => _refund != null;

  /// Whether the last refund that went through was sent through the gateway.
  bool get refundWasGateway => _refundWasGateway;

  /// Starts a refund. Checked here first (permission, amount within the remaining refundable),
  /// so a refusal never reaches the network. While an attempt is open no other one starts.
  Future<RefundResult> refund(RefundDraft draft) {
    if (!canRefund) return Future<RefundResult>.value(RefundResult.noAccess);
    if (_refund != null || _refunding) return Future<RefundResult>.value(RefundResult.busy);
    switch (checkRefundAmount(draft.amount, remainingRefund)) {
      case RefundAmountCheck.ok:
        break;
      case RefundAmountCheck.tooMuch:
        return Future<RefundResult>.value(RefundResult.tooMuch);
      case RefundAmountCheck.invalid:
      case RefundAmountCheck.zero:
        return Future<RefundResult>.value(RefundResult.invalid);
    }
    if (draft.viaGateway && !gatewayRefundAvailable) {
      return Future<RefundResult>.value(RefundResult.invalid);
    }
    // Like the dashboard: only a refund of the whole remaining amount can restock.
    final amount = canonicalRefundAmount(draft.amount);
    final full = refundMinor(amount) == refundMinor(remainingRefund);
    final body = RefundDraft(
      amount: amount,
      reason: draft.reason.trim(),
      restock: draft.restock && full,
      viaGateway: draft.viaGateway,
    );
    final attempt = _RefundAttempt(body, _newKey(), version);
    _refund = attempt;
    return _sendRefundAttempt(attempt);
  }

  /// Resends the open refund with the same key, body and base version.
  Future<RefundResult> retryRefund() async {
    final open = _refund;
    if (open == null || _refunding) return RefundResult.failed;
    return _sendRefundAttempt(open);
  }

  /// Forgets the open refund and reads the order again, so the remaining amount shows whatever the
  /// server really holds (a refund whose answer was lost may have gone through).
  Future<void> dismissRefund() async {
    _refund = null;
    _refundResult = null;
    _refundMessage = '';
    await load();
  }

  Future<RefundResult> _sendRefundAttempt(_RefundAttempt attempt) async {
    final send = _sendRefund;
    if (send == null) return RefundResult.noAccess;
    _refunding = true;
    _refundResult = null;
    _refundMessage = '';
    _notify();
    final result = await _refundOnce(send, attempt);
    _refundResult = result == RefundResult.done ? null : result;
    _refunding = false;
    _notify();
    return result;
  }

  Future<RefundResult> _refundOnce(RefundSender send, _RefundAttempt attempt) async {
    try {
      final body = await send(
        orderId,
        attempt.draft,
        version: attempt.version,
        idempotencyKey: attempt.key,
      );
      _refund = null;
      _refundWasGateway = attempt.draft.viaGateway;
      // The answer is the order detail after the refund.
      if (body.containsKey('id')) _detail = body;
      try {
        await _apply(await _load(orderId));
      } on Exception {
        // The refund went through; the next read brings the new version.
      }
      return RefundResult.done;
    } on ApiError catch (e) {
      switch (e.action) {
        case ErrorAction.waitAndRetrySameKey:
          // The first delivery is still running on the server: same key, a little later.
          return RefundResult.busy;
        case ErrorAction.showConflict:
          // Nothing was written. Show the order as it is now; the person starts again.
          _refund = null;
          try {
            await _apply(await _load(orderId));
          } on Exception {
            // Keep what is shown.
          }
          return RefundResult.changed;
        default:
          _refundMessage = safeServerMessage(e.message);
          if (_forbidden(e)) {
            _refund = null;
            return RefundResult.noAccess;
          }
          // A 5xx says nothing certain about the refund: the key stays for "Try again". A refusal
          // (over-refund, gateway declined, nothing left) wrote nothing and would be refused again.
          if (e.status < 500 && e.status != 0) _refund = null;
          return RefundResult.failed;
      }
    } on Exception {
      // No answer (offline, or the answer was lost). Nothing is queued: the attempt and its key
      // wait for "Try again".
      return RefundResult.offline;
    }
  }

  // ---- notes (outbox) --------------------------------------------------------------------------

  /// Queues the note and tries to send it at once. Offline, it stays in the outbox.
  Future<SyncReport> addNote(String text) async {
    final note = text.trim();
    if (note.isEmpty) return SyncReport();
    await _sync.enqueue(OutboxOp(
      id: _newKey(),
      accountId: accountId,
      kind: QueueableKind.orderNote,
      method: 'POST',
      path: notesPath,
      entity: 'order:$orderId',
      idempotencyKey: _newKey(),
      body: {'note': note, 'customer_note': false},
    ));
    await refreshPending();
    _notify();
    return syncNow();
  }

  /// Runs the outbox for this account.
  Future<SyncReport> syncNow() async {
    if (_syncing) return SyncReport();
    _syncing = true;
    _notify();
    try {
      final report = await _sync.run(accountId);
      if (report.sent > 0) {
        try {
          await _apply(await _load(orderId));
        } on Exception {
          // The notes were sent; they show on the next load.
        }
      }
      return report;
    } finally {
      _syncing = false;
      await refreshPending();
      _notify();
    }
  }

  Future<void> refreshPending() async {
    final all = await _sync.store.all(accountId);
    _pendingNotes = [
      for (final op in all)
        if (op.kind == QueueableKind.orderNote && op.path == notesPath) op,
    ];
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
