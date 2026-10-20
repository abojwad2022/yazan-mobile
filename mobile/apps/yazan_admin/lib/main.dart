import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';
import 'package:yazan_storage/yazan_storage.dart';

import 'src/app.dart';
import 'src/config.dart';
import 'src/secure_token_store.dart';
import 'src/session_events.dart';
import 'src/storage/account_id_store.dart';
import 'src/storage/account_lifecycle.dart';
import 'src/storage/admin_stores.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tokens = SecureTokenStore();
  final events = SessionEvents();
  final client = YazanApiClient(
    baseUrl: AppConfig.baseUrl,
    scope: AppConfig.scope,
    deviceId: await tokens.deviceId(),
    tokens: tokens,
    onSignedOut: events.sessionEnded,
  );
  runApp(YazanApp(
    client: client,
    tokens: tokens,
    accounts: await _openAccounts(client),
    events: events,
  ));
}

/// Opens the encrypted database. If it cannot be opened at all (for example it was written by a
/// newer app version) the app still runs, with its data in memory only, rather than not at all.
Future<AccountLifecycle?> _openAccounts(YazanApiClient client) async {
  try {
    final storage = await YazanStorage.open(
      opener: SqlCipherOpener(fileName: 'yazan_admin.db'),
      secrets: FlutterSecureSecretStore(),
    );
    return AccountLifecycle(
      storage: YazanAccountStorage(storage),
      ids: SecureAccountIdStore(),
      loadMe: () => client.getJson('/yazan-mobile/v1/me'),
      // Ids are only unique per server: a staging build and production never share an account key.
      namespace: Uri.parse(AppConfig.baseUrl).host,
      storageRecreated: storage.recreated,
    );
  } catch (_) {
    return null;
  }
}
