import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../l10n/app_localizations.dart';
import 'home_page.dart';
import 'login_page.dart';

/// The app shell. The client is injected so tests and previews never touch the network.
class YazanApp extends StatefulWidget {
  const YazanApp({super.key, required this.client, required this.tokens});

  final YazanApiClient client;
  final TokenStore tokens;

  @override
  State<YazanApp> createState() => _YazanAppState();
}

class _YazanAppState extends State<YazanApp> {
  bool? _signedIn;

  @override
  void initState() {
    super.initState();
    widget.tokens.read().then((s) {
      if (mounted) setState(() => _signedIn = s != null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
            onSignedOut: () => setState(() => _signedIn = false),
          ),
        false => LoginPage(
            client: widget.client,
            onSignedIn: () => setState(() => _signedIn = true),
          ),
      },
    );
  }
}
