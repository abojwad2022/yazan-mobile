import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import '../account/account_widgets.dart';
import '../catalogue/price_text.dart';
import '../catalogue/product.dart';
import '../catalogue/product_page.dart';
import 'wishlist_controller.dart';
import 'wishlist_models.dart';
import 'wishlist_scope.dart';

/// Finds a catalogue product by id in the local catalogue (null when it is not cached).
typedef ProductLookup = Future<Product?> Function(int id);

/// The customer's favourites. The list is readable offline (the phone keeps a copy of the last
/// server answer); removing a piece needs a connection.
class WishlistPage extends StatefulWidget {
  const WishlistPage({
    super.key,
    required this.controller,
    required this.findProduct,
    required this.onSessionEnded,
  });

  final WishlistController controller;
  final ProductLookup findProduct;

  /// Called after every pushed screen is closed when the server says the session is over.
  final VoidCallback onSessionEnded;

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  @override
  void initState() {
    super.initState();
    // After the first frame: the refresh notifies listeners, which must not happen during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.refresh();
    });
  }

  Future<void> _open(WishlistItem item) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final product = await widget.findProduct(item.id);
    if (!mounted) return;
    if (product == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.favouriteNotInCatalogue)));
      return;
    }
    navigator.push(MaterialPageRoute<void>(builder: (_) => ProductPage(product: product)));
  }

  Future<void> _remove(WishlistItem item) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final c = widget.controller;
    final ok = await c.setSaved(item, saved: false);
    final failure = c.failure;
    if (!mounted) return;
    if (!ok && failure != null && failure.isSignedOut) {
      endSession(context, widget.onSessionEnded);
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          ok
              ? l.favouriteRemoved
              : (failure == null ? l.genericError : wishlistErrorMessage(l, failure)),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final failure = c.failure;
        final items = c.items;
        final Widget body;
        if (items.isEmpty) {
          if (c.busy) {
            body = const Center(child: CircularProgressIndicator());
          } else if (failure != null) {
            body = MessageView(text: wishlistErrorMessage(l, failure), onRetry: c.refresh);
          } else {
            body = MessageView(text: l.favouritesEmpty);
          }
        } else {
          body = Column(
            children: [
              if (c.busy) const LinearProgressIndicator(),
              if (c.stale)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 16, end: 16, top: 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StaleBadge(label: l.staleBadge),
                  ),
                ),
              Expanded(
                child: ListView(
                  children: [
                    for (final item in items)
                      ListTile(
                        onTap: () => _open(item),
                        leading: SizedBox(
                          width: 48,
                          height: 48,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: ProductImageView(url: item.thumbUrl),
                          ),
                        ),
                        title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: item.price.isEmpty ? null : Text(item.price),
                        trailing: IconButton(
                          tooltip: l.removeFromFavourites,
                          onPressed: c.busy ? null : () => _remove(item),
                          icon: const Icon(Icons.favorite),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(l.favourites)),
          body: body,
        );
      },
    );
  }
}
