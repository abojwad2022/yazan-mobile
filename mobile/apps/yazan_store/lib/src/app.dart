import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_design_system/yazan_design_system.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../l10n/app_localizations.dart';
import 'account/account_api.dart';
import 'cart/cart_controller.dart';
import 'cart/cart_scope.dart';
import 'cart/store_api.dart';
import 'catalogue/catalogue_repository.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'session_scope.dart';
import 'wishlist/wishlist_api.dart';
import 'wishlist/wishlist_controller.dart';
import 'wishlist/wishlist_mirror.dart';
import 'wishlist/wishlist_scope.dart';

/// The app shell. It opens on the catalogue with no account needed (browsing, cart and cash on
/// delivery work as a guest); signing in is optional. The client is injected so tests and previews
/// never touch the network.
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

  /// Optional Store API (tests inject a fake transport; the default talks to the server through the client's raw requests).
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
  /// Signing in is optional: the app opens on the catalogue either way, and this only says
  /// whether an account session exists (it is read from the secure store a moment after launch).
  bool _signedIn = false;
  late final CartController _cart =
      CartController(widget.storeApi ?? StoreApi(widget.client.raw, fetchTokenFirst: true));
  late final AccountApi _account = widget.accountApi ?? ClientAccountApi(widget.client);
  late final WishlistController _wishlist = WishlistController(
    api: widget.wishlistApi ?? ClientWishlistApi(widget.client),
    mirror: widget.wishlistMirror ?? MemoryWishlistMirror(),
  );

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _cart.dispose();
    _wishlist.dispose();
    super.dispose();
  }

  /// Reads any stored session. A signed-in customer also gets the favourites; everyone, guest or
  /// not, gets the cart their device already holds (the Cart-Token), so the badge is right at once.
  Future<void> _start() async {
    Session? stored;
    try {
      stored = await widget.tokens.read();
    } catch (_) {
      stored = null;
    }
    if (!mounted) return;
    if (stored != null) {
      setState(() => _signedIn = true);
      _wishlist.load();
    }
    _cart.refresh();
  }

  /// Signing in keeps the cart (its token is not touched) and reloads it, then loads favourites.
  void _signedInNow() {
    setState(() => _signedIn = true);
    _cart.refresh();
    _wishlist.load();
  }

  /// Signing out (or a session the server ended) returns to browsing as a guest. The cart token,
  /// the cart and the phone's copy of the favourites are forgotten, so the next customer starts
  /// clean; the cart still works as a guest afterwards (a fresh token is issued on the next call).
  void _signedOutNow() {
    if (mounted) setState(() => _signedIn = false);
    _cart.forget();
    _wishlist.forget();
  }

  /// Pushes the sign-in screen; resolves true once the customer has signed in.
  Future<bool> _openSignIn(BuildContext context) async {
    final navigator = Navigator.of(context);
    final signedIn = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (routeContext) => LoginPage(
          client: widget.client,
          onSignedIn: () {
            _signedInNow();
            Navigator.of(routeContext).pop(true);
          },
        ),
      ),
    );
    return signedIn == true;
  }

  /// Ends the session on the server when it can be reached; the phone's session is cleared either
  /// way (the package client's logout only tolerates a server answer, not a missing connection).
  Future<void> _signOut() async {
    try {
      await widget.client.logout();
    } catch (_) {
      await widget.tokens.clear();
    }
    _signedOutNow();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      signedIn: _signedIn,
      openSignIn: _openSignIn,
      child: WishlistScope(
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
            home: HomePage(
              client: widget.client,
              accountApi: _account,
              repository: widget.repository,
              onSignOut: _signOut,
              onSessionEnded: _signedOutNow,
            ),
          ),
        ),
      ),
    );
  }
}
