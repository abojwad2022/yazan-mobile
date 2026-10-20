import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/app.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

// The shell with a stored session. flutter_test answers every HTTP request with a 400, so the
// lists show their "could not load" state; what is checked here is the wiring, not the data.

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
  testWidgets('the shell has a Customers tab that opens the customer list (en)', (tester) async {
    final tokens = await _signedIn();
    await tester.pumpWidget(YazanApp(client: _client(tokens), tokens: tokens));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tab-orders')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-products')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-customers')), findsOneWidget);
    // The list is built on first use.
    expect(find.byKey(const ValueKey('customer-search')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab-customers')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('customer-search')), findsOneWidget);
  });

  testWidgets('the Customers tab is labelled in Arabic and the shell is right-to-left (ar)', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ar')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final tokens = await _signedIn();
    await tester.pumpWidget(YazanApp(client: _client(tokens), tokens: tokens));
    await tester.pumpAndSettle();
    expect(find.text('العملاء'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byKey(const ValueKey('tab-customers')))),
      TextDirection.rtl,
    );
  });
}
