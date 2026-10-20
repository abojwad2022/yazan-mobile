import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/app.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

// The shell with a stored session. flutter_test answers every HTTP request with a 400, so the
// pages show their "could not load" state; what is checked here is the wiring, not the data.

YazanApiClient _client(TokenStore t) => YazanApiClient(
      baseUrl: 'https://example.test',
      scope: AppScope.admin,
      deviceId: 'test-device',
      tokens: t,
    );

Future<MemoryTokenStore> _signedIn() async {
  final tokens = MemoryTokenStore();
  await tokens.write(Session.fromJson(
      {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
  return tokens;
}

void main() {
  testWidgets('the shell opens on the Dashboard tab and the other tabs are still there (en)', (tester) async {
    final tokens = await _signedIn();
    await tester.pumpWidget(YazanApp(client: _client(tokens), tokens: tokens));
    await tester.pumpAndSettle();

    final tabs = ['tab-dashboard', 'tab-orders', 'tab-products', 'tab-customers'];
    for (final key in tabs) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    // The first tab is the Dashboard: its request failed (no network in tests), and it says so.
    expect(find.text('Could not load the dashboard. Pull down to try again.'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);

    // Orders are built on first use; going there and back keeps the Dashboard.
    await tester.tap(find.byKey(const ValueKey('tab-orders')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-dashboard')));
    await tester.pumpAndSettle();
    expect(find.text('Could not load the dashboard. Pull down to try again.'), findsOneWidget);
  });

  testWidgets('the Dashboard tab is labelled in Arabic and the shell is right-to-left (ar)', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ar')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final tokens = await _signedIn();
    await tester.pumpWidget(YazanApp(client: _client(tokens), tokens: tokens));
    await tester.pumpAndSettle();
    expect(find.text('لوحة التحكم'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byKey(const ValueKey('tab-dashboard')))),
      TextDirection.rtl,
    );
  });
}
