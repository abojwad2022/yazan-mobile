import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'product.dart';

/// Price with sale styling: the sale price in the accent colour, the regular price struck through.
class PriceText extends StatelessWidget {
  const PriceText({super.key, required this.product, this.large = false});

  final Product product;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final base = large ? theme.textTheme.titleLarge : theme.textTheme.bodyMedium;
    final price = product.price;
    if (price == null) return const SizedBox.shrink();
    if (!product.hasSalePrice) {
      return Text(price.toString(), style: base);
    }
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          label: l.salePrice,
          child: Text(
            price.toString(),
            style: base?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
          ),
        ),
        Semantics(
          label: l.regularPrice,
          child: Text(
            product.regularPrice.toString(),
            style: base?.copyWith(
              decoration: TextDecoration.lineThrough,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Network image with a quiet placeholder when there is no URL or it fails to load.
class ProductImageView extends StatelessWidget {
  const ProductImageView({super.key, required this.url, this.fit = BoxFit.cover});

  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(l.noImage, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
    final u = url;
    if (u == null) return placeholder;
    return Image.network(
      u,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}
