import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import '../l10n/app_localizations.dart';
import 'account/account_api.dart';
import 'account/account_page.dart';
import 'account/orders_page.dart';
import 'cart/cart_page.dart';
import 'cart/cart_scope.dart';
import 'catalogue/catalogue_list_page.dart';
import 'catalogue/catalogue_repository.dart';
import 'catalogue/category_repository.dart';
import 'catalogue/product.dart';
import 'extras/extras_menu.dart';
import 'links.dart';
import 'session_scope.dart';
import 'wishlist/wishlist_controller.dart';
import 'wishlist/wishlist_page.dart';
import 'wishlist/wishlist_scope.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.client,
    required this.accountApi,
    required this.onSignOut,
    required this.onSessionEnded,
    this.onAccountDeleted,
    this.openLink = openInBrowser,
    this.repository,
    this.categories,
  });

  final YazanApiClient client;

  /// The customer's account routes (tests inject a fake).
  final AccountApi accountApi;

  /// Signs out on the server and the phone; the app goes on as a guest.
  final Future<void> Function() onSignOut;

  /// The server says the session is over: carry on as a guest.
  final VoidCallback onSessionEnded;

  /// The customer deleted the account: wipe their data on the phone and carry on as a guest.
  final VoidCallback? onAccountDeleted;

  /// Opens pages of the website outside the app.
  final LinkOpener openLink;

  /// Injected by tests; the app builds one over the live client.
  final CatalogueRepository? repository;

  /// Injected by tests; the app builds one over the live client.
  final CategoryRepository? categories;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final CatalogueRepository _repository = widget.repository ??
      CatalogueRepository(fetch: (cursor) => widget.client.syncCatalog(cursor: cursor));

  // Tests that inject a catalogue stay off the network unless they inject categories too.
  late final CategoryRepository? _categories = widget.categories ??
      (widget.repository != null ? null : CategoryRepository(fetch: () => fetchCategories(widget.client)));

  Future<Product?> _findProduct(int id) async {
    final all = await _repository.products();
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The server ended the session: drop to guest browsing and say so.
  void _sessionEnded() {
    if (!mounted) {
      widget.onSessionEnded();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context).sessionEnded;
    widget.onSessionEnded();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Favourites need an account: a guest is asked to sign in first.
  Future<void> _openFavourites(WishlistController wishlist) async {
    if (!await requireSignIn(context)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WishlistPage(
          controller: wishlist,
          findProduct: _findProduct,
          onSessionEnded: _sessionEnded,
        ),
      ),
    );
  }

  /// "My orders" needs an account: a guest is asked to sign in first.
  Future<void> _openOrders() async {
    if (!await requireSignIn(context)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrdersPage(api: widget.accountApi, onSessionEnded: _sessionEnded),
      ),
    );
  }

  /// The account entry: the account page when signed in, the (optional) sign-in screen otherwise.
  Future<void> _openAccount() async {
    final session = SessionScope.maybeRead(context);
    if (session != null && !session.signedIn) {
      await session.openSignIn(context);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountPage(
          api: widget.accountApi,
          findProduct: _findProduct,
          onSignOut: widget.onSignOut,
          onSessionEnded: _sessionEnded,
          onAccountDeleted: widget.onAccountDeleted,
          websiteUrl: widget.client.baseUrl,
          openLink: widget.openLink,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cart = CartScope.maybeOf(context);
    final wishlist = WishlistScope.maybeOf(context);
    // Rebuilds this bar when the customer signs in or out.
    SessionScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          if (wishlist != null)
            IconButton(
              tooltip: l.favourites,
              onPressed: () => _openFavourites(wishlist),
              icon: const Icon(Icons.favorite_border),
            ),
          IconButton(
            tooltip: l.myOrders,
            onPressed: _openOrders,
            icon: const Icon(Icons.receipt_long_outlined),
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
          ExtrasMenuButton(client: widget.client, onSessionEnded: _sessionEnded),
          IconButton(
            tooltip: l.account,
            onPressed: _openAccount,
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: CatalogueListPage(repository: _repository, categories: _categories),
    );
  }
}
