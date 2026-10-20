import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import 'src/app.dart';
import 'src/config.dart';
import 'src/secure_token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tokens = SecureTokenStore();
  final client = YazanApiClient(
    baseUrl: AppConfig.baseUrl,
    scope: AppConfig.scope,
    deviceId: await tokens.deviceId(),
    tokens: tokens,
  );
  runApp(YazanApp(client: client, tokens: tokens));
}
