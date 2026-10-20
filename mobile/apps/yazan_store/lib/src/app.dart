import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../l10n/app_localizations.dart';
import 'cart/cart_controller.dart';
import 'cart/cart_scope.dart';
import 'cart/store_api.dart';
import 'catalogue/catalogue_repository.dart';
import 'home_page.dart';
import 'login_page.dart';

/// The app shell. The client is injected so tests and previews never touch the network.
class YazanApp extends StatefulWidget {
  const YazanApp({
    super.key,
    required this.client,
    required this.tokens,
    this.repository,
    this.storeApi,
  });

  final YazanApiClient client;
  final TokenStore tokens;

  /// Optional catalogue source (tests inject one; the app builds its own).
  final CatalogueRepository? repository;

  /// Optional Store API (tests inject a fake transport; the default uses [clientStoreTransport]).
  final StoreApi? storeApi;

  @override
  State<YazanApp> createState() => _YazanAppState();
}

class _YazanAppState extends State<YazanApp> {
  bool? _signedIn;
  late final CartController _cart =
      CartController(widget.storeApi ?? StoreApi(clientStoreTransport(widget.client)));

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
    super.dispose();
  }

  /// Loads the server cart on sign-in; forgets it (and its token) on sign-out.
  void _setSignedIn(bool signedIn) {
    setState(() => _signedIn = signedIn);
    if (signedIn) {
      _cart.refresh();
    } else {
      _cart.forget();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CartScope(
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
              repository: widget.repository,
              onSignedOut: () => _setSignedIn(false),
            ),
          false => LoginPage(
              client: widget.client,
              onSignedIn: () => _setSignedIn(true),
            ),
        },
      ),
    );
  }
}
