import 'package:flutter/material.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../../l10n/app_localizations.dart';
import '../more/staff_permissions.dart';
import '../products/product_permissions.dart' show PermissionsLoader;
import '../security/app_lock_scope.dart';
import 'conflict_page.dart';
import 'no_access_view.dart';
import 'order_detail_controller.dart';
import 'order_refund.dart';
import 'order_summary.dart';
import 'orders_format.dart';
import 'refund_sheet.dart';

enum _ConflictChoice { keepServer, overwrite }

/// Order detail: status change and refunds (online-only, If-Match + Idempotency-Key) and notes
/// (outbox).
class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
    super.key,
    required this.summary,
    required this.accountId,
    required this.load,
    required this.sendStatus,
    required this.sync,
    this.loadNotes,
    this.newKey,
    this.sendRefund,
    this.permissions = const StaffPermissions.unknown(),
    this.loadPermissions,
  });

  final OrderSummary summary;
  final String accountId;
  final VersionedOrderLoader load;
  final StatusSender sendStatus;
  final SyncEngine sync;
  final NotesLoader? loadNotes;

  /// Key factory for tests; defaults to `YazanApiClient.newIdempotencyKey`.
  final String Function()? newKey;

  /// `POST /orders/{id}/refunds`. Without it (or without `orders.refund` in the permission map)
  /// there is no Refund button.
  final RefundSender? sendRefund;
  final StaffPermissions permissions;

  /// Reads `/yazan-mobile/v1/me` when [permissions] is not known yet.
  final PermissionsLoader? loadPermissions;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late final OrderDetailController _c = OrderDetailController(
    orderId: widget.summary.id,
    accountId: widget.accountId,
    initialStatus: widget.summary.status,
    fallbackVersion: widget.summary.version,
    load: widget.load,
    sendStatus: widget.sendStatus,
    sync: widget.sync,
    loadNotes: widget.loadNotes,
    newKey: widget.newKey,
    sendRefund: widget.sendRefund,
    permissions: widget.permissions,
    loadPermissions: widget.loadPermissions,
  );
  final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c.load();
  }

  @override
  void dispose() {
    _c.dispose();
    _note.dispose();
    super.dispose();
  }

  // ---- status ----------------------------------------------------------------------------------

  Future<void> _pickStatus() async {
    final l = AppLocalizations.of(context);
    final current = _c.status;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(l.orderChangeStatus, style: Theme.of(ctx).textTheme.titleMedium)),
            for (final s in orderStatuses)
              if (s != current)
                ListTile(
                  key: ValueKey('status-$s'),
                  title: Text(statusLabel(l, s)),
                  onTap: () => Navigator.of(ctx).pop(s),
                ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.orderChangeStatusConfirm(statusLabel(l, picked))),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l.orderChangeConfirm)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _handle(await _c.changeStatus(picked));
  }

  Future<void> _handle(StatusResult result) async {
    if (!mounted) return;
    switch (result) {
      case StatusResult.done:
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.orderStatusUpdated)));
      case StatusResult.conflict:
        await _showConflict();
      case StatusResult.offline:
      case StatusResult.busy:
      case StatusResult.noAccess:
      case StatusResult.failed:
        // Shown inline from the controller's state.
        break;
    }
  }

  Future<void> _showConflict() async {
    final c = _c.conflict;
    if (c == null) return;
    final l = AppLocalizations.of(context);
    final choice = await Navigator.of(context).push<_ConflictChoice>(
      MaterialPageRoute<_ConflictChoice>(
        builder: (ctx) => ConflictPage(
          local: [MapEntry(l.conflictStatusField, statusLabel(l, c.mine))],
          server: [MapEntry(l.conflictStatusField, statusLabel(l, c.serverStatus))],
          onKeepServer: () => Navigator.of(ctx).pop(_ConflictChoice.keepServer),
          onOverwrite: () => Navigator.of(ctx).pop(_ConflictChoice.overwrite),
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _ConflictChoice.overwrite:
        await _handle(await _c.overwrite());
      case _ConflictChoice.keepServer:
      case null:
        await _c.keepServer();
    }
  }

  // ---- refunds -------------------------------------------------------------------------------

  String _money(String amount) => _c.currency.isEmpty ? amount : '$amount ${_c.currency}';

  Future<bool> _ask({required String body, String? title, required String action, required Key key}) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: title == null ? null : Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l.cancel)),
          FilledButton(key: key, onPressed: () => Navigator.of(ctx).pop(true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  /// Sheet -> confirmation (a second one for money through the gateway) -> identity check -> send.
  /// Cancelled or refused at any step: nothing is sent.
  Future<void> _startRefund() async {
    final l = AppLocalizations.of(context);
    final draft = await showModalBottomSheet<RefundDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RefundSheet(
        remaining: _c.remainingRefund,
        currency: _c.currency,
        gatewayAvailable: _c.gatewayRefundAvailable,
      ),
    );
    if (draft == null || !mounted) return;
    final amount = _money(draft.amount);
    final method = _c.paymentMethod.isEmpty ? l.refundMethodFallback : _c.paymentMethod;
    final first = await _ask(
      body: draft.viaGateway ? l.refundConfirmGateway(amount, method) : l.refundConfirmManual(amount),
      action: l.refundConfirmAction,
      key: const ValueKey('refund-confirm'),
    );
    if (!first || !mounted) return;
    if (draft.viaGateway) {
      final second = await _ask(
        title: l.refundConfirmGateway2Title(amount),
        body: l.refundConfirmGateway2Body,
        action: l.refundNow,
        key: const ValueKey('refund-confirm-gateway'),
      );
      if (!second || !mounted) return;
    }
    if (!await confirmSensitive(context, l.securityReasonRefund) || !mounted) return;
    _handleRefund(await _c.refund(draft));
  }

  /// "Try again" asks for the same identity check as the first send. Refused or cancelled: nothing
  /// is sent and the attempt stays for the button.
  Future<void> _retryRefund() async {
    final l = AppLocalizations.of(context);
    if (!await confirmSensitive(context, l.securityReasonRefund) || !mounted) return;
    _handleRefund(await _c.retryRefund());
  }

  void _handleRefund(RefundResult result) {
    if (!mounted || result != RefundResult.done) return;
    // Every other outcome is shown inline from the controller's state.
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_c.refundWasGateway ? l.refundDoneGateway : l.refundDoneManual)),
    );
  }

  Widget? _refundCard(BuildContext context, AppLocalizations l) {
    final refunds = _c.refunds;
    final canRefund = _c.canRefund;
    String? message;
    var retry = false;
    switch (_c.refundResult) {
      case RefundResult.offline:
        message = l.refundOffline;
        retry = _c.refundPending;
      case RefundResult.busy:
        message = l.refundBusy;
        retry = _c.refundPending;
      case RefundResult.changed:
        message = l.refundChanged;
      case RefundResult.noAccess:
        message = _c.refundMessage.isEmpty ? l.refundNoPermission : _c.refundMessage;
      case RefundResult.failed:
        message = _c.refundMessage.isEmpty ? l.refundFailed : _c.refundMessage;
        retry = _c.refundPending;
      case RefundResult.tooMuch:
        message = l.refundAmountTooMuch(_money(_c.remainingRefund));
      case RefundResult.invalid:
        message = l.refundAmountInvalid;
      case RefundResult.done:
      case null:
        message = null;
    }
    if (refunds.isEmpty && !canRefund && message == null) return null;
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).disabledColor;
    final busy = _c.refunding || _c.loading;
    return Card(
      key: const ValueKey('refund-card'),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.refundsTitle, style: t.titleSmall),
            for (final r in refunds)
              ListTile(
                key: ValueKey('refund-${r.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('−${_money(r.amount)}', textDirection: TextDirection.ltr),
                subtitle: Text(
                  [
                    if (r.date.isNotEmpty) r.date,
                    if (r.by.isNotEmpty) r.by,
                    if (r.reason.isNotEmpty) r.reason,
                  ].join(' · '),
                ),
              ),
            if (!_c.hasRefundable && refunds.isNotEmpty)
              Text(l.refundFull, key: const ValueKey('refund-full'), style: TextStyle(color: muted)),
            if (canRefund) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.wifi_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l.refundOnlineOnly)),
                ],
              ),
              const SizedBox(height: 4),
              Text(l.refundRemaining(_money(_c.remainingRefund))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonal(
                    key: const ValueKey('refund-start'),
                    onPressed: busy || _c.refundPending ? null : _startRefund,
                    child: Text(l.refundStart),
                  ),
                  if (_c.refunding)
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message, key: const ValueKey('refund-message')),
              if (retry)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: const ValueKey('refund-retry'),
                      onPressed: busy ? null : _retryRefund,
                      child: Text(l.retry),
                    ),
                    TextButton(
                      key: const ValueKey('refund-dismiss'),
                      onPressed: busy ? null : _c.dismissRefund,
                      child: Text(l.refundDiscard),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- notes -----------------------------------------------------------------------------------

  Future<void> _addNote() async {
    final text = _note.text;
    if (text.trim().isEmpty) return;
    _note.clear();
    final report = await _c.addNote(text);
    if (!mounted) return;
    if (report.offline) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.noteQueued)));
    }
  }

  // ---- build -----------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = widget.summary;
    return Scaffold(
      appBar: AppBar(title: Text(l.orderNumber(s.number))),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) =>
            _c.noAccess ? const NoAccessView() : _body(context, l, s),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l, OrderSummary s) {
    final t = Theme.of(context).textTheme;
    final d = _c.detail;
    final rawLines = d == null ? null : d['items'];
    final lines = rawLines is List ? rawLines : const <Object?>[];
    final payment = d == null ? '' : '${d['payment_method'] ?? ''}';
    final billing = d == null ? '' : '${d['billing_formatted'] ?? ''}';
    final refundCard = _c.loading || _c.failed ? null : _refundCard(context, l);
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        Text(s.customerName.isEmpty ? l.guestCustomer : s.customerName, style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(label: Text(statusLabel(l, _c.status)), visualDensity: VisualDensity.compact),
            Text(l.orderItems(s.itemCount)),
          ],
        ),
        const SizedBox(height: 8),
        Text('${l.orderTotal}: ${formatMoney(s.total)}', style: t.titleSmall),
        const SizedBox(height: 16),
        _statusCard(context, l),
        const SizedBox(height: 16),
        if (_c.loading)
          const Center(child: CircularProgressIndicator())
        else if (_c.failed) ...[
          Text(l.orderDetailFailed),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(onPressed: _c.load, child: Text(l.retry)),
          ),
        ] else ...[
          if (lines.isNotEmpty) ...[
            Text(l.orderLines, style: t.titleSmall),
            for (final raw in lines)
              if (raw is Map)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${raw['name'] ?? ''}'),
                  subtitle: Text('x ${raw['quantity'] ?? ''}'),
                  trailing: Text('${raw['total'] ?? ''}'),
                ),
          ],
          if (payment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l.orderPayment, style: t.titleSmall),
            Text(payment),
          ],
          if (billing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l.orderBilling, style: t.titleSmall),
            Text(billing),
          ],
        ],
        if (refundCard != null) ...[
          const SizedBox(height: 16),
          refundCard,
        ],
        const SizedBox(height: 24),
        ..._notesSection(context, l),
      ],
    );
  }

  Widget _statusCard(BuildContext context, AppLocalizations l) {
    final result = _c.lastResult;
    String? message;
    var retry = false;
    switch (result) {
      case StatusResult.offline:
        message = l.needsConnection;
        retry = _c.canRetry;
      case StatusResult.busy:
        message = l.statusBusy;
        retry = _c.canRetry;
      case StatusResult.noAccess:
        message = l.statusNoPermission;
      case StatusResult.failed:
        message = _c.lastMessage.isEmpty ? l.statusChangeFailed : _c.lastMessage;
        retry = _c.canRetry;
      case StatusResult.done:
      case StatusResult.conflict:
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
                Expanded(child: Text(l.orderStatusNeedsConnection)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonal(
                  key: const ValueKey('change-status'),
                  onPressed: _c.sending || _c.loading || _c.failed ? null : _pickStatus,
                  child: Text(l.orderChangeStatus),
                ),
                if (_c.sending)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message, key: const ValueKey('status-message')),
              if (retry)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: _c.sending ? null : () async => _handle(await _c.retryStatus()),
                    child: Text(l.retry),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _notesSection(BuildContext context, AppLocalizations l) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).disabledColor;
    final pending = _c.pendingNotes;
    final notes = _c.notes;
    return [
      Row(
        children: [
          Expanded(child: Text(l.orderNotes, style: t.titleSmall)),
          TextButton.icon(
            key: const ValueKey('sync-now'),
            onPressed: _c.syncing ? null : _c.syncNow,
            icon: const Icon(Icons.sync, size: 18),
            label: Text(l.syncNow),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('note-field'),
              controller: _note,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(hintText: l.addNoteHint),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('add-note'),
            onPressed: _addNote,
            child: Text(l.addNote),
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final op in pending)
        ListTile(
          key: ValueKey('pending-note-${op.id}'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            op.state == OpState.failed ? Icons.error_outline : Icons.schedule,
            color: muted,
          ),
          title: Text('${op.body?['note'] ?? ''}', style: TextStyle(color: muted)),
          subtitle: Text(
            op.state == OpState.failed ? l.noteSendFailed : l.noteWaiting,
            style: TextStyle(color: muted),
          ),
        ),
      if (notes.isEmpty && pending.isEmpty && !_c.loading)
        Text(l.notesEmpty, style: TextStyle(color: muted)),
      for (final n in notes)
        ListTile(
          key: ValueKey('note-${n.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(n.content),
          subtitle: Text(
            [
              if (n.author.isNotEmpty) n.author,
              if (n.date.isNotEmpty) n.date,
              if (n.toCustomer) l.noteToCustomer,
            ].join(' · '),
          ),
        ),
    ];
  }
}
