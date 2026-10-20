import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../products/product_input.dart';
import 'coupon_detail_controller.dart';

/// Asks for the discount amount. Pops the typed text (validated), or null on cancel.
class CouponAmountDialog extends StatefulWidget {
  const CouponAmountDialog({super.key, required this.current, required this.isPercent});

  final String current;
  final bool isPercent;

  @override
  State<CouponAmountDialog> createState() => _CouponAmountDialogState();
}

class _CouponAmountDialogState extends State<CouponAmountDialog> {
  late final TextEditingController _amount = TextEditingController(text: widget.current);
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit(AppLocalizations l) {
    final m = parsePriceInput(_amount.text);
    String? error;
    if (m == null || m.minor <= 0) {
      error = l.couponAmountInvalid;
    } else if (widget.isPercent && m.minor > 10000) {
      error = l.couponPercentInvalid;
    }
    setState(() => _error = error);
    if (error != null || m == null) return;
    Navigator.of(context).pop<String>(m.toDecimalString());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.couponEditAmount),
      content: TextField(
        key: const ValueKey('coupon-amount-field'),
        controller: _amount,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: l.couponAmountLabel, errorText: _error),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        FilledButton(
          key: const ValueKey('coupon-amount-save'),
          onPressed: () => _submit(l),
          child: Text(l.couponSave),
        ),
      ],
    );
  }
}

/// Asks for the expiry date. Pops `YYYY-MM-DD`, an empty string for "no expiry", or null on cancel.
class CouponExpiryDialog extends StatefulWidget {
  const CouponExpiryDialog({super.key, required this.current, required this.today});

  /// The current expiry (`YYYY-MM-DD`) or empty.
  final String current;

  /// The device's date, where the date picker starts.
  final DateTime today;

  @override
  State<CouponExpiryDialog> createState() => _CouponExpiryDialogState();
}

class _CouponExpiryDialogState extends State<CouponExpiryDialog> {
  late final TextEditingController _date = TextEditingController(text: widget.current);
  bool _bad = false;

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _date.text.trim();
    final parsed = raw.isEmpty ? '' : parseDateInput(raw);
    setState(() => _bad = parsed == null);
    if (parsed == null) return;
    Navigator.of(context).pop<String>(parsed);
  }

  Future<void> _pick() async {
    final start = DateTime.tryParse(parseDateInput(_date.text) ?? '') ?? widget.today;
    final picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(widget.today.year - 1),
      lastDate: DateTime(widget.today.year + 10),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date.text = dateString(picked);
      _bad = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.couponEditExpiry),
      content: TextField(
        key: const ValueKey('coupon-expiry-field'),
        controller: _date,
        autofocus: true,
        keyboardType: TextInputType.datetime,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: l.couponExpiryField,
          errorText: _bad ? l.couponExpiryInvalid : null,
          suffixIcon: IconButton(
            key: const ValueKey('coupon-expiry-pick'),
            tooltip: l.couponPickDate,
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: _pick,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        FilledButton(
          key: const ValueKey('coupon-expiry-save'),
          onPressed: _submit,
          child: Text(l.couponSave),
        ),
      ],
    );
  }
}
