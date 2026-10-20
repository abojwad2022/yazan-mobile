import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../l10n/app_localizations.dart';
import 'account/account_api.dart';
import 'cart/cart_controller.dart';
import 'cart/cart_scope.dart';
import 'cart/store_api.dart';
import 'catalogue/catalogue_repository.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'wishlist/wishlist_api.dart';
import 'wishlist/wishlist_controller.dart';
import 'wishlist/wishlist_mirror.dart';
import 'wishlist/wishlist_scope.dart';

/// The app shell. The client is injected so tests and previews never touch the network.
class YazanApp extends StatefulWidget {
  const YazanApp({
    super.key,
    required this.client,
    required this.tokens,
    this.repository,
    this.storeApi,
    this.accountApi,
    this.wishlistApi,
    this.wishlistMirror,
  });

  final YazanApiClient client;
  final TokenStore tokens;

  /// Optional catalogue source (tests inject one; the app builds its own).
  final CatalogueRepository? repository;

  /// Optional Store API (tests inject a fake transport; the default uses [clientStoreTransport]).
  final StoreApi? storeApi;

  /// Optional account routes (tests inject a fake; the app talks to the server).
  final AccountApi? accountApi;

  /// Optional favourites routes (tests inject a fake; the app talks to the server).
  final WishlistApi? wishlistApi;

  /// Where the phone keeps its copy of the favourites. Defaults to memory only; `main` passes the
  /// Keystore/Keychain-backed one so the list can be read offline after a restart.
  final WishlistMirror? wishlistMirror;

  @override
  State<YazanApp> createState() => _YazanAppState();
}

class _YazanAppState extends State<YazanApp> {
  bool? _signedIn;
  late final CartController _cart =
      CartController(widget.storeApi ?? StoreApi(clientStoreTransport(widget.client)));
  late final AccountApi _account = widget.accountApi ?? ClientAccountApi(widget.client);
  late final WishlistController _wishlist = WishlistController(
    api: widget.wishlistApi ?? ClientWishlistApi(widget.client),
    mirror: widget.wishlistMirror ?? MemoryWishlistMirror(),
  );

  @override
  void initState() {
    super.initState();
    widget.tokens.read().then((s) {
      if (mounted) _setSignedIn(s != null);
    });
  }

  @override
  void dispose() {
    _cart.dispose();
    _wishlist.dispose();
    super.dispose();
  }

  /// Loads the server cart and favourites on sign-in; forgets them (and the cart token and the
  /// phone's copy of the favourites) on sign-out, so the next customer starts clean.
  void _setSignedIn(bool signedIn) {
    setState(() => _signedIn = signedIn);
    if (signedIn) {
      _cart.refresh();
      _wishlist.load();
    } else {
      _cart.forget();
      _wishlist.forget();
    }
  }

  /// Ends the session on the server when it can be reached; the phone's session is cleared either
  /// way (the package client's logout only tolerates a server answer, not a missing connection).
  Future<void> _signOut() async {
    try {
      await widget.client.logout();
    } catch (_) {
      await widget.tokens.clear();
    }
    if (mounted) _setSignedIn(false);
  }

  @override
  Widget build(BuildContext context) {
    return WishlistScope(
      controller: _wishlist,
      child: CartScope(
        controller: _cart,
        child: MaterialApp(
          onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
          theme: yazanTheme(YazanThemeVariant.black),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: switch (_signedIn) {
            null => const Scaffold(body: Center(child: CircularProgressIndicator())),
            true => HomePage(
                client: widget.client,
                accountApi: _account,
                repository: widget.repository,
                onSignOut: _signOut,
                onSessionEnded: () => _setSignedIn(false),
              ),
            false => LoginPage(
                client: widget.client,
                onSignedIn: () => _setSignedIn(true),
              ),
          },
        ),
      ),
    );
  }
}
