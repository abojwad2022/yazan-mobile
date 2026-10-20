import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'product_input.dart';

/// What the price dialog returns: validated, canonical decimal strings ("129.50"). [sale] is empty
/// when there is no sale price.
typedef PriceInput = ({String regular, String sale});

/// Asks for the regular price and an optional sale price. Pops a [PriceInput], or null on cancel.
class PriceDialog extends StatefulWidget {
  const PriceDialog({super.key, required this.regular, required this.sale});

  /// Current values, shown as the starting text.
  final String regular;
  final String sale;

  @override
  State<PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<PriceDialog> {
  late final TextEditingController _regular = TextEditingController(text: widget.regular);
  late final TextEditingController _sale = TextEditingController(text: widget.sale);
  bool _regularBad = false;
  bool _saleBad = false;

  @override
  void dispose() {
    _regular.dispose();
    _sale.dispose();
    super.dispose();
  }

  void _submit() {
    final regular = parsePriceInput(_regular.text);
    final regularMinor = regular == null ? 0 : regular.minor;
    final regularOk = regularMinor > 0;
    var saleOk = true;
    var sale = '';
    if (_sale.text.trim().isNotEmpty) {
      final s = parsePriceInput(_sale.text);
      saleOk = s != null && s.minor > 0 && regularOk && s.minor < regularMinor;
      if (s != null && saleOk) sale = s.toDecimalString();
    }
    setState(() {
      _regularBad = !regularOk;
      _saleBad = !saleOk;
    });
    if (regular == null || !regularOk || !saleOk) return;
    Navigator.of(context).pop<PriceInput>((regular: regular.toDecimalString(), sale: sale));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.productEditPrice),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('regular-price-field'),
              controller: _regular,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l.productRegularPrice,
                errorText: _regularBad ? l.priceInvalid : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('sale-price-field'),
              controller: _sale,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l.productSalePrice,
                errorText: _saleBad ? l.salePriceInvalid : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        FilledButton(
          key: const ValueKey('price-save'),
          onPressed: _submit,
          child: Text(l.productSave),
        ),
      ],
    );
  }
}

/// Asks for the stock quantity. Pops the number, or null on cancel.
class StockDialog extends StatefulWidget {
  const StockDialog({super.key, required this.current});

  final int current;

  @override
  State<StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<StockDialog> {
  late final TextEditingController _qty = TextEditingController(text: '${widget.current}');
  bool _bad = false;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  void _submit() {
    final n = parseStockInput(_qty.text);
    setState(() => _bad = n == null);
    if (n == null) return;
    Navigator.of(context).pop<int>(n);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.productEditStock),
      content: TextField(
        key: const ValueKey('stock-field'),
        controller: _qty,
        autofocus: true,
        keyboardType: TextInputType.number,
        // Arabic-Indic digits typed on an Arabic keyboard are normalised when saving.
        decoration: InputDecoration(
          labelText: l.productStockQty,
          errorText: _bad ? l.stockInvalid : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        FilledButton(
          key: const ValueKey('stock-save'),
          onPressed: _submit,
          child: Text(l.productSave),
        ),
      ],
    );
  }
}
