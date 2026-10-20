import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import '../l10n/app_localizations.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.client, required this.onSignedOut});

  final YazanApiClient client;
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          TextButton(
            onPressed: () async {
              await client.logout();
              onSignedOut();
            },
            child: Text(l.signOut),
          ),
        ],
      ),
      body: Center(child: Text(l.welcome)),
    );
  }
}
