import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../cart/cart_controller.dart';
import '../cart/cart_page.dart';
import '../cart/cart_scope.dart';
import 'price_text.dart';
import 'product.dart';

class ProductPage extends StatelessWidget {
  const ProductPage({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stock = product.stock;
    final cart = CartScope.maybeOf(context);
    final String stockText;
    if (product.isSoldOut) {
      stockText = l.soldOut;
    } else if (stock != null && stock > 0 && stock <= 5) {
      stockText = l.onlyLeft(stock);
    } else {
      stockText = l.inStock;
    }
    return Scaffold(
      appBar: AppBar(title: Text(product.name)),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ProductImageView(url: product.mediumUrl),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                PriceText(product: product, large: true),
                const SizedBox(height: 8),
                Text(
                  stockText,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: product.isSoldOut ? theme.colorScheme.error : null,
                  ),
                ),
                if (cart != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: product.isSoldOut || cart.busy ? null : () => _add(context, cart),
                      child: Text(l.addToCart),
                    ),
                  ),
                ],
                if (product.summary.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(product.summary, style: theme.textTheme.bodyLarge),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, CartController cart) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await cart.add(product.id);
    final error = cart.error;
    final String message;
    if (ok) {
      message = l.addedToCart;
    } else {
      message = error == null ? l.genericError : storeErrorMessage(l, error);
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: ok
            ? SnackBarAction(
                label: l.viewCart,
                onPressed: () => navigator.push(
                  MaterialPageRoute<void>(builder: (_) => CartPage(controller: cart)),
                ),
              )
            : null,
      ));
  }
}
