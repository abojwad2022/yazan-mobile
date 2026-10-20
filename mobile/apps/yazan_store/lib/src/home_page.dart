import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import '../l10n/app_localizations.dart';
import 'account/account_api.dart';
import 'account/account_page.dart';
import 'cart/cart_page.dart';
import 'cart/cart_scope.dart';
import 'catalogue/catalogue_list_page.dart';
import 'catalogue/catalogue_repository.dart';
import 'catalogue/product.dart';
import 'wishlist/wishlist_page.dart';
import 'wishlist/wishlist_scope.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.client,
    required this.accountApi,
    required this.onSignOut,
    required this.onSessionEnded,
    this.repository,
  });

  final YazanApiClient client;

  /// The customer's account routes (tests inject a fake).
  final AccountApi accountApi;

  /// Signs out on the server and the phone, then shows the sign-in form.
  final Future<void> Function() onSignOut;

  /// The server says the session is over: show the sign-in form.
  final VoidCallback onSessionEnded;

  /// Injected by tests; the app builds one over the live client.
  final CatalogueRepository? repository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final CatalogueRepository _repository = widget.repository ??
      CatalogueRepository(fetch: (cursor) => widget.client.syncCatalog(cursor: cursor));

  Future<Product?> _findProduct(int id) async {
    final all = await _repository.products();
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cart = CartScope.maybeOf(context);
    final wishlist = WishlistScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          if (wishlist != null)
            IconButton(
              tooltip: l.favourites,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WishlistPage(
                    controller: wishlist,
                    findProduct: _findProduct,
                    onSessionEnded: widget.onSessionEnded,
                  ),
                ),
              ),
              icon: const Icon(Icons.favorite_border),
            ),
          if (cart != null)
            IconButton(
              tooltip: l.cart,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => CartPage(controller: cart)),
              ),
              icon: Badge.count(
                count: cart.count,
                isLabelVisible: cart.count > 0,
                child: const Icon(Icons.shopping_bag_outlined),
              ),
            ),
          IconButton(
            tooltip: l.account,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AccountPage(
                  api: widget.accountApi,
                  findProduct: _findProduct,
                  onSignOut: widget.onSignOut,
                  onSessionEnded: widget.onSessionEnded,
                ),
              ),
            ),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: CatalogueListPage(repository: _repository),
    );
  }
}
