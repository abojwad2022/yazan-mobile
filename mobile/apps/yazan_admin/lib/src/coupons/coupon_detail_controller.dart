import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../more/staff_permissions.dart';
import '../products/product_input.dart';
import '../products/product_permissions.dart' show PermissionsLoader;
import 'coupon_api.dart';

/// What happened to a coupon change.
///
/// [notApplied] is a 2xx answer after which the coupon does not hold the value that was sent (the
/// server dropped the field). [invalid] is a local refusal, before any request.
enum CouponEditResult { done, offline, busy, noAccess, invalid, failed, notApplied }

class _Attempt {
  _Attempt(this.fields, this.key);

  /// The exact request body. A retry sends this same map under the same key.
  final Map<String, dynamic> fields;
  final String key;
}

/// State and actions of one coupon screen. Everything that talks to the network is injected.
///
/// Changes are online-only: a network failure keeps the attempt (same `Idempotency-Key`) for
/// [retry] and nothing is ever queued. The coupon route has no version token, so there is no
/// `If-Match` and no conflict screen: the last write wins.
///
/// "Enable / disable" is expressed through the expiry date, the only switch the route exposes:
/// [expireNow] sets today as the expiry, [removeExpiry] clears it.
class CouponDetailController extends ChangeNotifier {
  CouponDetailController({
    required this.couponId,
    required CouponLoader load,
    required CouponWriter write,
    StaffPermissions permissions = const StaffPermissions.unknown(),
    PermissionsLoader? loadPermissions,
    String Function()? newKey,
    DateTime Function()? clock,
  })  : _load = load,
        _write = write,
        _permissions = permissions,
        _loadPermissions = loadPermissions,
        _clock = clock ?? DateTime.now,
        _newKey = newKey ?? YazanApiClient.newIdempotencyKey;

  final int couponId;
  final CouponLoader _load;
  final CouponWriter _write;
  final PermissionsLoader? _loadPermissions;
  final String Function() _newKey;
  final DateTime Function() _clock;

  StaffPermissions _permissions;
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _failed = false;
  bool _noAccess = false;
  bool _sending = false;
  bool _disposed = false;
  _Attempt? _attempt;
  CouponEditResult? _lastResult;
  String _lastMessage = '';

  Map<String, dynamic>? get detail => _detail;
  bool get loading => _loading;
  bool get failed => _failed;
  bool get noAccess => _noAccess;
  bool get sending => _sending;
  StaffPermissions get permissions => _permissions;
  CouponEditResult? get lastResult => _lastResult;
  String get lastMessage => _lastMessage;
  bool get canRetry => _attempt != null;

  /// True when [retry] would resend a discount amount change (the one coupon change that asks
  /// for an identity check), false for an expiry change or when nothing is open.
  bool get retryChangesAmount => _attempt?.fields.containsKey('amount') ?? false;

  // ---- what the loaded coupon says -------------------------------------------------------------

  String _text(String key) {
    final v = _detail?[key];
    return v == null ? '' : '$v';
  }

  String get code => _text('code');
  String get description => _text('description');
  String get discountType => _text('discount_type');
  bool get isPercent => discountType == 'percent';

  /// The discount as a plain decimal ("20", "12.50"); empty before the load.
  String get amount => plainPrice(_text('amount'));
  String get amountText => _text('amount_html').isEmpty ? amount : _text('amount_html');

  /// `YYYY-MM-DD` or empty (never expires).
  String get expires {
    final s = _text('date_expires');
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  /// The expiry has been reached. The server counts the day itself as expired (the date means
  /// midnight at its start), so this does too.
  bool get expired => expires.isNotEmpty && expires.compareTo(today) <= 0;

  bool get freeShipping => _detail?['free_shipping'] == true;
  int get usageCount => int.tryParse(_text('usage_count')) ?? 0;

  /// Null when the coupon has no overall limit.
  int? get usageLimit {
    final n = int.tryParse(_text('usage_limit'));
    return n == null || n <= 0 ? null : n;
  }

  /// The device's date as `YYYY-MM-DD`.
  String get today => dateString(_clock());

  bool get canEdit => _detail != null && _permissions.known && _permissions.allows('coupons.edit');

  // ---- reading ---------------------------------------------------------------------------------

  Future<void> load() async {
    _loading = true;
    _failed = false;
    _noAccess = false;
    _notify();
    try {
      _detail = await _load(couponId);
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
          // Edits stay off until the permissions can be read.
        }
      }
    }
    _loading = false;
    _notify();
  }

  static bool _forbidden(ApiError e) => e.action == ErrorAction.hideFeature || e.status == 403;

  // ---- changes (online-only) -------------------------------------------------------------------

  /// Sets the discount. [raw] is what was typed; it is validated here (greater than zero, at most
  /// 100 for a percentage), so a bad value never reaches the network.
  Future<CouponEditResult> saveAmount(String raw) {
    if (!canEdit) return Future<CouponEditResult>.value(CouponEditResult.noAccess);
    final m = parsePriceInput(raw);
    if (m == null || m.minor <= 0 || (isPercent && m.minor > 10000)) {
      return Future<CouponEditResult>.value(CouponEditResult.invalid);
    }
    return _start({'amount': m.toDecimalString()});
  }

  /// Sets the expiry to [date] (`YYYY-MM-DD`), or removes it when empty.
  Future<CouponEditResult> saveExpiry(String date) {
    if (!canEdit) return Future<CouponEditResult>.value(CouponEditResult.noAccess);
    final canonical = date.trim().isEmpty ? '' : parseDateInput(date);
    if (canonical == null) return Future<CouponEditResult>.value(CouponEditResult.invalid);
    return _start({'date_expires': canonical});
  }

  /// Stops the coupon now: the expiry becomes today.
  Future<CouponEditResult> expireNow() => saveExpiry(today);

  /// Makes the coupon usable again: no expiry date.
  Future<CouponEditResult> removeExpiry() => saveExpiry('');

  Future<CouponEditResult> _start(Map<String, dynamic> fields) {
    final open = _attempt;
    final attempt = open != null && mapEquals(open.fields, fields) ? open : _Attempt(fields, _newKey());
    _attempt = attempt;
    return _send(attempt);
  }

  /// Resends the open attempt with the same Idempotency-Key.
  Future<CouponEditResult> retry() async {
    final open = _attempt;
    if (open == null) return CouponEditResult.failed;
    return _send(open);
  }

  /// Dismisses the inline message and forgets the open attempt.
  void dismiss() {
    _attempt = null;
    _lastResult = null;
    _notify();
  }

  Future<CouponEditResult> _send(_Attempt attempt) async {
    _sending = true;
    _lastResult = null;
    _lastMessage = '';
    _notify();
    final result = await _sendOnce(attempt);
    _lastResult = result;
    _sending = false;
    _notify();
    return result;
  }

  Future<CouponEditResult> _sendOnce(_Attempt attempt) async {
    try {
      final answer = await _write(couponId, attempt.fields, idempotencyKey: attempt.key);
      _attempt = null;
      // The answer is the coupon as saved; it replaces what the screen shows.
      _detail = answer.containsKey('code') ? answer : {...?_detail, ...answer};
      return _took(attempt, _detail!) ? CouponEditResult.done : CouponEditResult.notApplied;
    } on ApiError catch (e) {
      switch (e.action) {
        case ErrorAction.waitAndRetrySameKey:
          return CouponEditResult.busy;
        default:
          if (_forbidden(e)) {
            _attempt = null;
            return CouponEditResult.noAccess;
          }
          _lastMessage = e.message;
          return CouponEditResult.failed;
      }
    } on Exception {
      // No network. Nothing is queued: the attempt (and its key) waits for "Try again".
      return CouponEditResult.offline;
    }
  }

  bool _took(_Attempt attempt, Map<String, dynamic> record) {
    final f = attempt.fields;
    if (f.containsKey('amount')) {
      return samePrice('${record['amount'] ?? ''}', '${f['amount']}');
    }
    if (f.containsKey('date_expires')) {
      final s = '${record['date_expires'] ?? ''}';
      return (s.length >= 10 ? s.substring(0, 10) : s) == '${f['date_expires']}';
    }
    return true;
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

/// `2026-12-31` for a date; always Latin digits.
String dateString(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

/// A typed expiry as canonical `YYYY-MM-DD`, or null when it is not a real calendar date.
/// Arabic-Indic digits are accepted.
String? parseDateInput(String raw) {
  final s = normalizeDigits(raw).trim();
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final dt = DateTime.utc(y, mo, d);
  if (dt.year != y || dt.month != mo || dt.day != d) return null;
  return dateString(dt);
}
