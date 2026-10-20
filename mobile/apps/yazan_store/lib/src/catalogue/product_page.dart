import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../cart/cart_controller.dart';
import '../cart/cart_page.dart';
import '../cart/cart_scope.dart';
import '../session_scope.dart';
import '../wishlist/wishlist_controller.dart';
import '../wishlist/wishlist_models.dart';
import '../wishlist/wishlist_scope.dart';
import 'price_text.dart';
import 'product.dart';

class ProductPage extends StatefulWidget {
  const ProductPage({super.key, required this.product});

  final Product product;

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  /// The size (variation) the customer picked; null until they pick one.
  ProductVariation? _selected;

  Product get product => widget.product;

  @override
  void initState() {
    super.initState();
    // A single size needs no choosing.
    final options = product.selectableVariations;
    if (options.length == 1 && !options.first.isSoldOut) _selected = options.first;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = _selected;
    final options = product.selectableVariations;
    final cart = CartScope.maybeOf(context);
    final wishlist = WishlistScope.maybeOf(context);
    final soldOut = selected != null ? selected.isSoldOut : product.isSoldOut;
    final stock = selected != null ? selected.stock : product.stock;
    // A variable product with nothing to choose from cannot be bought from the app.
    final buyable = !product.isSoldOut && (!product.isVariable || options.isNotEmpty);
    final String stockText;
    if (soldOut) {
      stockText = l.soldOut;
    } else if (stock != null && stock > 0 && stock <= 5) {
      stockText = l.onlyLeft(stock);
    } else {
      stockText = l.inStock;
    }
    final variationPrice = selected?.price;
    return Scaffold(
      appBar: AppBar(
        title: Text(product.name),
        actions: [
          if (wishlist != null)
            IconButton(
              tooltip: wishlist.contains(product.id) ? l.removeFromFavourites : l.addToFavourites,
              onPressed: wishlist.busy ? null : () => _toggleSaved(wishlist),
              icon: Icon(wishlist.contains(product.id) ? Icons.favorite : Icons.favorite_border),
            ),
        ],
      ),
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
                if (variationPrice != null)
                  Text(variationPrice.toString(), style: theme.textTheme.titleLarge)
                else
                  PriceText(product: product, large: true),
                const SizedBox(height: 8),
                Text(
                  stockText,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: soldOut ? theme.colorScheme.error : null,
                  ),
                ),
                if (options.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SizePicker(
                    options: options,
                    selected: selected,
                    onPicked: (v) => setState(() => _selected = v),
                  ),
                ],
                if (cart != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: !buyable || soldOut || cart.busy ? null : () => _add(cart),
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

  /// Saves or removes the piece on the server (online only) and says what happened. Favourites
  /// need an account: a guest is asked to sign in first, and taps again once signed in (the
  /// favourites are still loading at that moment).
  Future<void> _toggleSaved(WishlistController wishlist) async {
    final wasGuest = !(SessionScope.maybeRead(context)?.signedIn ?? true);
    if (!await requireSignIn(context)) return;
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (wasGuest) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.signedInTapAgain)));
      return;
    }
    final wantSaved = !wishlist.contains(product.id);
    final item = WishlistItem(
      id: product.id,
      name: product.name,
      price: product.price?.toString() ?? '',
      thumb: product.thumbUrl ?? '',
    );
    final ok = await wishlist.setSaved(item, saved: wantSaved);
    final failure = wishlist.failure;
    final String message;
    if (ok) {
      message = wantSaved ? l.favouriteAdded : l.favouriteRemoved;
    } else {
      message = failure == null ? l.genericError : wishlistErrorMessage(l, failure);
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Adds the piece to the server cart; a variable product is added as the chosen variation.
  Future<void> _add(CartController cart) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final variation = _selected;
    if (product.isVariable && variation == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.chooseOptionFirst)));
      return;
    }
    final ok = variation == null
        ? await cart.add(product.id)
        : await cart.add(variation.id, variation: variation.cartAttributes);
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

/// The size chooser: one chip per purchasable variation; a sold-out size is shown but disabled.
class _SizePicker extends StatelessWidget {
  const _SizePicker({required this.options, required this.selected, required this.onPicked});

  final List<ProductVariation> options;
  final ProductVariation? selected;
  final ValueChanged<ProductVariation?> onPicked;

  /// "Size" for a size attribute, the attribute's own (tidied) name for anything else, and a
  /// neutral heading when a variation mixes several attributes.
  static String heading(AppLocalizations l, List<ProductVariation> options) {
    final keys = options.first.attributes.keys.toList();
    if (keys.length != 1) return l.chooseOption;
    final key = keys.first;
    if (key.toLowerCase().contains('size')) return l.sizeLabel;
    final tidy = key.replaceFirst(RegExp(r'^pa_'), '').replaceAll(RegExp(r'[-_]+'), ' ').trim();
    if (tidy.isEmpty) return l.chooseOption;
    return tidy[0].toUpperCase() + tidy.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading(l, options), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in options)
              ChoiceChip(
                key: ValueKey<String>('variation-${v.id}'),
                label: Text(v.isSoldOut ? '${v.label} - ${l.soldOut}' : v.label),
                selected: selected?.id == v.id,
                onSelected: v.isSoldOut ? null : (picked) => onPicked(picked ? v : null),
              ),
          ],
        ),
      ],
    );
  }
}
