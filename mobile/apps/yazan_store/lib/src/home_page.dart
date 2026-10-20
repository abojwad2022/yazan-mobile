import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import '../l10n/app_localizations.dart';
import 'cart/cart_page.dart';
import 'cart/cart_scope.dart';
import 'catalogue/catalogue_list_page.dart';
import 'catalogue/catalogue_repository.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.client,
    required this.onSignedOut,
    this.repository,
  });

  final YazanApiClient client;
  final VoidCallback onSignedOut;

  /// Injected by tests; the app builds one over the live client.
  final CatalogueRepository? repository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final CatalogueRepository _repository = widget.repository ??
      CatalogueRepository(fetch: (cursor) => widget.client.syncCatalog(cursor: cursor));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cart = CartScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
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
          TextButton(
            onPressed: () async {
              await widget.client.logout();
              widget.onSignedOut();
            },
            child: Text(l.signOut),
          ),
        ],
      ),
      body: CatalogueListPage(repository: _repository),
    );
  }
}
