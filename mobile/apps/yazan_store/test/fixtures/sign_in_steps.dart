import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_store/src/auth/social_sign_in.dart';

/// The sign-in screen's email step: types [email] and taps Continue (the lookup answers next).
Future<void> enterEmail(WidgetTester tester, String email, {bool settle = true}) async {
  await tester.enterText(find.byKey(const ValueKey('auth-email')), email);
  await tester.tap(find.byKey(const ValueKey('auth-continue')));
  await _after(tester, settle);
}

/// From the email step to signed in, for an email the lookup says has an account.
Future<void> signInWithEmail(
  WidgetTester tester, {
  String email = 'noor@yazan.test',
  String password = 'secret-password',
  bool settle = true,
}) async {
  await enterEmail(tester, email, settle: settle);
  await tester.enterText(find.byKey(const ValueKey('auth-password')), password);
  await tester.tap(find.byKey(const ValueKey('auth-sign-in')));
  await _after(tester, settle);
}

/// Fixed steps, never pumpAndSettle: enough for a route transition, cannot hang on a timer.
Future<void> steps(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _after(WidgetTester tester, bool settle) async {
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await steps(tester);
  }
}

/// A provider SDK stand-in: hands out [token] (null = the customer closed the sheet), or throws
/// [error].
class FakeTokenSource implements SocialTokenSource {
  FakeTokenSource({this.provider = 'google', this.token = 'id-token-1', this.error});

  @override
  final String provider;
  String? token;
  Object? error;
  int asked = 0;
  int signedOut = 0;

  @override
  Future<SocialToken?> obtain() async {
    asked++;
    final e = error;
    if (e != null) throw e;
    final t = token;
    return t == null ? null : SocialToken(idToken: t);
  }

  @override
  Future<void> signOut() async {
    signedOut++;
  }
}
