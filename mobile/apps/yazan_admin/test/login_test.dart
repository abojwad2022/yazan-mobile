import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_admin/src/app.dart';

YazanApiClient _client(TokenStore t) => YazanApiClient(
      baseUrl: 'https://example.test',
      scope: AppScope.admin,
      deviceId: 'test-device',
      tokens: t,
    );

void main() {
  testWidgets('a signed-out user sees the sign-in form in English', (tester) async {
    final tokens = MemoryTokenStore();
    await tester.pumpWidget(YazanApp(client: _client(tokens), tokens: tokens));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('Arabic locale renders right-to-left', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ar')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final tokens = MemoryTokenStore();
    await tester.pumpWidget(YazanApp(client: _client(tokens), tokens: tokens));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.text('تسجيل الدخول')));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('a stored session goes straight to the home screen', (tester) async {
    final tokens = MemoryTokenStore();
    await tokens.write(Session.fromJson(
        {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
    await tester.pumpWidget(YazanApp(client: _client(tokens), tokens: tokens));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
  });
}
