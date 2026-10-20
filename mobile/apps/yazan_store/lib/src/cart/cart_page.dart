import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../catalogue/price_text.dart';
import 'cart.dart';
import 'cart_controller.dart';
import 'cart_scope.dart';
import 'checkout_page.dart';

/// The server cart: lines with quantity controls, the server's totals and the checkout button.
class CartPage extends StatefulWidget {
  const CartPage({super.key, required this.controller});

  final CartController controller;

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  @override
  void initState() {
    super.initState();
    // After the first frame: the refresh notifies listeners, which must not happen during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final cart = c.cart;
        final error = c.error;
        final Widget body;
        if (cart == null) {
          body = error != null
              ? _Message(text: storeErrorMessage(l, error), onRetry: c.refresh)
              : const Center(child: CircularProgressIndicator());
        } else if (cart.isEmpty) {
          body = _Message(text: error != null ? storeErrorMessage(l, error) : l.cartEmpty);
        } else {
          body = _CartList(controller: c, cart: cart);
        }
        final canCheckout = cart != null && !cart.isEmpty && cart.errors.isEmpty && !c.busy;
        return Scaffold(
          appBar: AppBar(title: Text(l.cart)),
          body: body,
          bottomNavigationBar: cart == null || cart.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(16),
                    child: FilledButton(
                      onPressed: canCheckout
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CheckoutPage(controller: c, cart: cart),
                                ),
                              )
                          : null,
                      child: Text(l.checkout),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final retry = onRetry;
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (retry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: retry, child: Text(l.retry)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CartList extends StatelessWidget {
  const _CartList({required this.controller, required this.cart});

  final CartController controller;
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final error = controller.error;
    final totals = cart.totals;
    final errorStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error);
    final shipping = totals.shipping;
    return ListView(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
      children: [
        if (controller.busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 8),
            child: Text(storeErrorMessage(l, error), style: errorStyle),
          ),
        for (final message in cart.errors)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 4),
            child: Text(message, style: errorStyle),
          ),
        for (final item in cart.items) _CartItemRow(controller: controller, item: item),
        const Divider(height: 24),
        _TotalRow(label: l.subtotal, value: totals.subtotal.toString()),
        if (totals.discount.minor != 0)
          _TotalRow(label: l.discount, value: '-${totals.discount}'),
        if (cart.needsShipping)
          _TotalRow(
            label: l.shipping,
            value: shipping == null ? l.shippingAtCheckout : shipping.toString(),
          ),
        _TotalRow(label: l.tax, value: totals.tax.toString()),
        _TotalRow(label: l.total, value: totals.total.toString(), emphasis: true),
      ],
    );
  }
}

class _CartItemRow extends StatelessWidget {
  const _CartItemRow({required this.controller, required this.item});

  final CartController controller;
  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final busy = controller.busy;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ProductImageView(url: item.imageUrl),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(item.lineTotal.toString(), style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          IconButton(
            tooltip: l.decreaseQuantity,
            onPressed: busy || !item.editable
                ? null
                : () => controller.setQuantity(item, item.quantity - 1),
            icon: const Icon(Icons.remove),
          ),
          Semantics(
            label: l.quantityLabel(item.quantity),
            excludeSemantics: true,
            child: Text('${item.quantity}', style: theme.textTheme.titleMedium),
          ),
          IconButton(
            tooltip: l.increaseQuantity,
            onPressed: busy || !item.canIncrease
                ? null
                : () => controller.setQuantity(item, item.quantity + 1),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: l.removeItem,
            onPressed: busy ? null : () => controller.remove(item),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasis ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
