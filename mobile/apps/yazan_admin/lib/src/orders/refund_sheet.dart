import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'order_refund.dart';

/// The refund form, shown as a bottom sheet. The amount starts at what is still refundable and is
/// checked here before the sheet closes: more than that, zero, or not a number never leaves it.
/// Pops a [RefundDraft], or null when cancelled.
class RefundSheet extends StatefulWidget {
  const RefundSheet({
    super.key,
    required this.remaining,
    required this.currency,
    required this.gatewayAvailable,
  });

  /// The server's `remaining_refund` ("129.50").
  final String remaining;
  final String currency;

  /// The payment method can refund and this account may send money back.
  final bool gatewayAvailable;

  @override
  State<RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<RefundSheet> {
  late final TextEditingController _amount = TextEditingController(text: widget.remaining);
  final TextEditingController _reason = TextEditingController();
  bool _restock = false;
  bool _gateway = false;
  RefundAmountCheck? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  String _money(String amount) =>
      widget.currency.isEmpty ? amount : '$amount ${widget.currency}';

  /// A typed amount below the remaining one names no units, so it cannot restock.
  bool get _partial {
    final typed = refundMinor(canonicalRefundAmount(_amount.text));
    final left = refundMinor(widget.remaining);
    return typed != null && left != null && typed < left;
  }

  String? _errorText(AppLocalizations l) {
    switch (_error) {
      case RefundAmountCheck.invalid:
        return l.refundAmountInvalid;
      case RefundAmountCheck.zero:
        return l.refundAmountZero;
      case RefundAmountCheck.tooMuch:
        return l.refundAmountTooMuch(_money(widget.remaining));
      case RefundAmountCheck.ok:
      case null:
        return null;
    }
  }

  void _submit() {
    final check = checkRefundAmount(_amount.text, widget.remaining);
    if (check != RefundAmountCheck.ok) {
      setState(() => _error = check);
      return;
    }
    Navigator.of(context).pop(
      RefundDraft(
        amount: canonicalRefundAmount(_amount.text),
        reason: _reason.text.trim(),
        restock: _restock && !_partial,
        viaGateway: widget.gatewayAvailable && _gateway,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final error = _errorText(l);
    final partial = _partial;
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.refundSheetTitle, style: t.titleMedium),
              const SizedBox(height: 4),
              Text(l.refundRemaining(_money(widget.remaining))),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('refund-amount-field'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: l.refundAmountLabel,
                  suffixText: widget.currency.isEmpty ? null : widget.currency,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (error != null) ...[
                const SizedBox(height: 4),
                Text(
                  error,
                  key: const ValueKey('refund-amount-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('refund-reason-field'),
                controller: _reason,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(labelText: l.refundReasonLabel),
              ),
              CheckboxListTile(
                key: const ValueKey('refund-restock'),
                contentPadding: EdgeInsets.zero,
                value: _restock && !partial,
                onChanged: partial ? null : (v) => setState(() => _restock = v ?? false),
                title: Text(l.refundRestock),
                subtitle: Text(
                  partial ? l.refundRestockPartial(_money(widget.remaining)) : l.refundRestockHelp,
                ),
              ),
              if (widget.gatewayAvailable)
                CheckboxListTile(
                  key: const ValueKey('refund-gateway'),
                  contentPadding: EdgeInsets.zero,
                  value: _gateway,
                  onChanged: (v) => setState(() => _gateway = v ?? false),
                  title: Text(l.refundViaGateway),
                  subtitle: Text(l.refundViaGatewayHelp),
                )
              else
                Text(l.refundManualNote, key: const ValueKey('refund-manual-note')),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('refund-continue'),
                    onPressed: _submit,
                    child: Text(l.refundContinue),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
