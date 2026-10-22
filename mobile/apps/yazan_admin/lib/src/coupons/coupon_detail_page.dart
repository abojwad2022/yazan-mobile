import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../more/staff_permissions.dart';
import '../orders/no_access_view.dart';
import '../products/product_permissions.dart' show PermissionsLoader;
import '../security/app_lock_scope.dart';
import 'coupon_api.dart';
import 'coupon_detail_controller.dart';
import 'coupon_dialogs.dart';
import 'coupon_summary.dart';
import 'coupons_format.dart';

/// One coupon with online-only changes: the discount amount, the expiry date, "expire now" and
/// "remove expiry". Each change asks for a confirmation, then sends one request with an
/// `Idempotency-Key`. Nothing is queued on the phone.
class CouponDetailPage extends StatefulWidget {
  const CouponDetailPage({
    super.key,
    required this.summary,
    required this.load,
    required this.write,
    this.permissions = const StaffPermissions.unknown(),
    this.loadPermissions,
    this.newKey,
    this.clock,
    this.onChanged,
  });

  final CouponSummary summary;
  final CouponLoader load;
  final CouponWriter write;
  final StaffPermissions permissions;
  final PermissionsLoader? loadPermissions;

  /// Key factory for tests.
  final String Function()? newKey;
  final DateTime Function()? clock;

  /// Called after a change went through, so the list can refresh its copy.
  final VoidCallback? onChanged;

  @override
  State<CouponDetailPage> createState() => _CouponDetailPageState();
}

class _CouponDetailPageState extends State<CouponDetailPage> {
  late final CouponDetailController _c = CouponDetailController(
    couponId: widget.summary.id,
    load: widget.load,
    write: widget.write,
    permissions: widget.permissions,
    loadPermissions: widget.loadPermissions,
    newKey: widget.newKey,
    clock: widget.clock,
  );

  @override
  void initState() {
    super.initState();
    _c.load();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _code => _c.code.isEmpty ? widget.summary.code : _c.code;

  Future<bool> _confirm(String text) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l.cancel)),
          FilledButton(
            key: const ValueKey('confirm-change'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.couponConfirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _editAmount() async {
    final l = AppLocalizations.of(context);
    final amount = await showDialog<String>(
      context: context,
      builder: (_) => CouponAmountDialog(current: _c.amount, isPercent: _c.isPercent),
    );
    if (amount == null || !mounted) return;
    if (amount == _c.amount) return;
    final shown = _c.isPercent ? '$amount%' : amount;
    if (!await _confirm(l.couponAmountConfirm(_code, shown))) return;
    if (!mounted) return;
    // Refused or cancelled: nothing is sent.
    if (!await confirmSensitive(context, l.securityReasonCouponAmount) || !mounted) return;
    await _handle(await _c.saveAmount(amount));
  }

  Future<void> _editExpiry() async {
    final l = AppLocalizations.of(context);
    final date = await showDialog<String>(
      context: context,
      builder: (_) => CouponExpiryDialog(current: _c.expires, today: DateTime.tryParse(_c.today) ?? DateTime.now()),
    );
    if (date == null || !mounted) return;
    if (date == _c.expires) return;
    final text = date.isEmpty ? l.couponExpiryClearConfirm(_code) : l.couponExpiryConfirm(_code, date);
    if (!await _confirm(text) || !mounted) return;
    await _handle(await _c.saveExpiry(date));
  }

  Future<void> _toggle() async {
    final l = AppLocalizations.of(context);
    final stopping = !_c.expired;
    final text = stopping ? l.couponExpireNowConfirm(_code) : l.couponExpiryClearConfirm(_code);
    if (!await _confirm(text) || !mounted) return;
    await _handle(stopping ? await _c.expireNow() : await _c.removeExpiry());
  }

  /// "Try again" on an amount change asks for the same identity check as the first send; an expiry
  /// change never did. Refused or cancelled: nothing is sent and the attempt stays for the button.
  Future<void> _retry() async {
    if (_c.retryChangesAmount) {
      final l = AppLocalizations.of(context);
      if (!await confirmSensitive(context, l.securityReasonCouponAmount) || !mounted) return;
    }
    await _handle(await _c.retry());
  }

  Future<void> _handle(CouponEditResult result) async {
    if (!mounted) return;
    if (result == CouponEditResult.done) {
      widget.onChanged?.call();
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.couponUpdated)));
    }
    // Every other outcome is shown inline from the controller's state.
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(_code)),
        body: _c.noAccess ? NoAccessView(body: l.noAccessCouponsBody) : _body(context, l),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l) {
    final t = Theme.of(context).textTheme;
    final s = widget.summary;
    final loaded = _c.detail != null;
    final expired = loaded ? _c.expired : s.expired;
    final expires = loaded ? _c.expires : s.expires;
    final type = loaded ? _c.discountType : s.discountType;
    final amountText = loaded ? _c.amountText : s.amountText;
    final count = loaded ? _c.usageCount : s.usageCount;
    final limit = loaded ? _c.usageLimit : s.usageLimit;
    final description = loaded ? _c.description : s.description;
    final freeShipping = loaded ? _c.freeShipping : s.freeShipping;
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text(_code, style: t.titleMedium, textDirection: TextDirection.ltr)),
            Chip(
              key: const ValueKey('coupon-status'),
              label: Text(expired ? l.couponExpired : l.couponActive),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(description, style: t.bodySmall),
        ],
        const SizedBox(height: 16),
        _line(l.couponDiscountLabel, '${couponTypeLabel(l, type)}: $amountText',
            key: const ValueKey('coupon-discount')),
        _line(l.couponExpiryLabel, expires.isEmpty ? l.couponNoExpiry : expires,
            key: const ValueKey('coupon-expiry')),
        _line(l.couponUsageLabel, couponUsageText(l, count, limit), key: const ValueKey('coupon-usage')),
        if (freeShipping) _line(l.couponFreeShipping, '✓'),
        const SizedBox(height: 16),
        if (_c.loading)
          const Center(child: CircularProgressIndicator())
        else if (_c.failed) ...[
          Text(l.couponDetailFailed),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(onPressed: _c.load, child: Text(l.retry)),
          ),
        ] else
          _editCard(context, l, expired),
      ],
    );
  }

  Widget _line(String label, String value, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsetsDirectional.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _editCard(BuildContext context, AppLocalizations l, bool expired) {
    String? message;
    var retry = false;
    switch (_c.lastResult) {
      case CouponEditResult.offline:
        message = l.couponOffline;
        retry = _c.canRetry;
      case CouponEditResult.busy:
        message = l.statusBusy;
        retry = _c.canRetry;
      case CouponEditResult.noAccess:
        message = l.couponNoPermission;
      case CouponEditResult.failed:
        message = _c.lastMessage.isEmpty ? l.couponChangeFailed : _c.lastMessage;
        retry = _c.canRetry;
      case CouponEditResult.notApplied:
        message = l.couponNotApplied;
      case CouponEditResult.invalid:
        message = l.couponChangeFailed;
      case CouponEditResult.done:
      case null:
        message = null;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(l.couponOnlineOnly)),
              ],
            ),
            const SizedBox(height: 12),
            if (!_c.canEdit)
              Text(l.couponReadOnly, key: const ValueKey('edit-note'))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonal(
                    key: const ValueKey('coupon-edit-amount'),
                    onPressed: _c.sending ? null : _editAmount,
                    child: Text(l.couponEditAmount),
                  ),
                  FilledButton.tonal(
                    key: const ValueKey('coupon-edit-expiry'),
                    onPressed: _c.sending ? null : _editExpiry,
                    child: Text(l.couponEditExpiry),
                  ),
                  FilledButton.tonal(
                    key: const ValueKey('coupon-toggle'),
                    onPressed: _c.sending ? null : _toggle,
                    child: Text(expired ? l.couponReenable : l.couponExpireNow),
                  ),
                  if (_c.sending)
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message, key: const ValueKey('edit-message')),
              if (retry)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey('edit-retry'),
                    onPressed: _c.sending ? null : _retry,
                    child: Text(l.retry),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
