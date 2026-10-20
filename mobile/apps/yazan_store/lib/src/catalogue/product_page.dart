import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
}
