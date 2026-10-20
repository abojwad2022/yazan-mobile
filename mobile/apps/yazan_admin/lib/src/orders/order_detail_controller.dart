import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

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
  })  : _initialStatus = initialStatus,
        _fallbackVersion = fallbackVersion,
        _load = load,
        _sendStatus = sendStatus,
        _sync = sync,
        _loadNotes = loadNotes,
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
