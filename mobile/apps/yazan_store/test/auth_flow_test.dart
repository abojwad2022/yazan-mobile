import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/src/app.dart';
import 'package:yazan_store/src/auth/social_sign_in.dart';
import 'package:yazan_store/src/cart/store_api.dart';
import 'package:yazan_store/src/links.dart';
import 'package:yazan_store/src/login_page.dart';

import 'fixtures/account_fakes.dart';
import 'fixtures/catalogue_fixtures.dart';
import 'fixtures/scripted_client.dart';
import 'fixtures/sign_in_steps.dart';
import 'fixtures/store_cart.dart';

typedef _Opened = ({
  ScriptedClient client,
  MemoryTokenStore tokens,
  FakeWishlistApi wishlist,
  FakeAccountApi account,
  List<Uri> links,
});

/// Opens the app (a guest unless [signedIn]) and taps the account entry: the sign-in screen for a
/// guest, the account page for a signed-in customer.
Future<_Opened> _open(
  WidgetTester tester, {
  ScriptedClient? client,
  MemoryTokenStore? tokens,
  SocialTokenSource? google,
  bool signedIn = false,
  String accountTooltip = 'Account',
}) async {
  // A tall screen keeps every button of a step on screen.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final store = tokens ?? MemoryTokenStore();
  if (signedIn) {
    await store.write(Session.fromJson(
        {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
  }
  final scripted = client ?? ScriptedClient(store);
  final wishlist = FakeWishlistApi();
  final account = FakeAccountApi();
  final links = <Uri>[];
  await tester.pumpWidget(YazanApp(
    client: scripted,
    tokens: store,
    repository: catalogueOf(const []),
    storeApi: StoreApi(FakeTransport((r) => ok(storeCart(images: false))).call),
    accountApi: account,
    wishlistApi: wishlist,
    googleSignIn: google,
    openLink: (uri) async => links.add(uri),
  ));
  await steps(tester);
  await tester.tap(find.byTooltip(accountTooltip));
  await steps(tester);
  return (client: scripted, tokens: store, wishlist: wishlist, account: account, links: links);
}

Finder _key(String key) => find.byKey(ValueKey(key));

/// The password field's editable text (the key is on the form field around it).
EditableText _passwordText(WidgetTester tester) => tester.widget<EditableText>(
    find.descendant(of: _key('auth-password'), matching: find.byType(EditableText)));

Future<void> _fillCreate(WidgetTester tester, {String password = 'Carnelian-Ring-2026'}) async {
  await tester.enterText(_key('auth-first-name'), 'Noor');
  await tester.enterText(_key('auth-last-name'), 'Ali');
  await tester.enterText(_key('auth-password'), password);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('the rules', () {
    test('an email needs one @ and a dotted domain', () {
      expect(looksLikeEmail('noor@yazan.test'), isTrue);
      expect(looksLikeEmail('  noor@yazan.test '), isTrue);
      expect(looksLikeEmail('noor@yazan'), isFalse);
      expect(looksLikeEmail('noor yazan@x.test'), isFalse);
      expect(looksLikeEmail('noor'), isFalse);
    });

    test('a new password is too short under 8, strong from 12 with three kinds', () {
      expect(passwordStrength('short'), PasswordStrength.tooShort);
      expect(passwordStrength('eightchr'), PasswordStrength.fair);
      expect(passwordStrength('alllowercaseletters'), PasswordStrength.fair);
      expect(passwordStrength('Carnelian-Ring-2026'), PasswordStrength.strong);
    });

    test('Google: Android with the Web client id; iOS only beside Apple; never without the id', () {
      expect(googleSignInAllowed(platform: TargetPlatform.android, serverClientId: ''), isFalse);
      expect(googleSignInAllowed(platform: TargetPlatform.android, serverClientId: 'web.apps'),
          isTrue);
      expect(googleSignInAllowed(platform: TargetPlatform.iOS, serverClientId: 'web.apps'),
          isFalse);
      expect(
          googleSignInAllowed(
              platform: TargetPlatform.iOS, serverClientId: 'web.apps', iosClientId: 'ios.apps'),
          isFalse,
          reason: 'App Store rule 4.8: no Google on iOS without Apple');
      expect(
          googleSignInAllowed(
              platform: TargetPlatform.iOS,
              serverClientId: 'web.apps',
              iosClientId: 'ios.apps',
              appleShown: true),
          isTrue);
      expect(googleSignInAllowed(platform: TargetPlatform.windows, serverClientId: 'web.apps'),
          isFalse);
    });

    test('a build without YAZAN_GOOGLE_SERVER_CLIENT_ID has no Google button', () {
      expect(defaultGoogleSource(platform: TargetPlatform.android), isNull);
    });

    test('Apple: iOS only, with the flag and a provider', () {
      expect(appleSignInAllowed(platform: TargetPlatform.iOS, enabled: true, hasSource: true),
          isTrue);
      expect(appleSignInAllowed(platform: TargetPlatform.iOS, enabled: false, hasSource: true),
          isFalse);
      expect(appleSignInAllowed(platform: TargetPlatform.iOS, enabled: true, hasSource: false),
          isFalse);
      expect(appleSignInAllowed(platform: TargetPlatform.android, enabled: true, hasSource: true),
          isFalse);
    });

    test('the website pages', () {
      expect(SiteLinks.terms('https://yazanus.com').toString(),
          'https://yazanus.com/terms-and-conditions/');
      expect(SiteLinks.privacy('https://yazanus.com/').toString(),
          'https://yazanus.com/privacy-policy/');
      expect(SiteLinks.accountDeletion('https://yazanus.com').toString(),
          'https://yazanus.com/account-deletion/');
    });
  });

  group('email first', () {
    testWidgets('an email with an account goes to "Welcome back", then signs in', (tester) async {
      final o = await _open(tester);
      expect(find.text('Welcome to YAZAN'), findsOneWidget);

      await enterEmail(tester, '  noor@yazan.test ');
      expect(o.client.lookups, ['noor@yazan.test']);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('noor@yazan.test'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Forgot password?'), findsOneWidget);

      // Show / hide the password.
      expect(_passwordText(tester).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(_passwordText(tester).obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);

      await tester.enterText(_key('auth-password'), 'secret-password');
      await _tap(tester, _key('auth-sign-in'));
      expect(o.client.logins, ['noor@yazan.test']);
      expect(find.byType(LoginPage), findsNothing);
      expect((await o.tokens.read())!.accessToken, 'yzm_a');
      expect(o.wishlist.calls, contains('list'));
    });

    testWidgets('"Change" goes back to the email, and back again forgets the password',
        (tester) async {
      await _open(tester);
      await enterEmail(tester, 'noor@yazan.test');
      await tester.enterText(_key('auth-password'), 'typed');
      await _tap(tester, _key('auth-change-email'));
      expect(find.text('Welcome to YAZAN'), findsOneWidget);
      expect(tester.widget<TextField>(_key('auth-email')).controller!.text, 'noor@yazan.test');

      await enterEmail(tester, 'noor@yazan.test');
      expect(_passwordText(tester).controller.text, isEmpty);
      // The app bar's back arrow walks the steps too.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to YAZAN'), findsOneWidget);
    });

    testWidgets('a mistyped email is caught before anything is sent', (tester) async {
      final o = await _open(tester);
      await enterEmail(tester, 'noor-at-yazan');
      expect(find.text('Please enter a valid email address.'), findsOneWidget);
      expect(o.client.lookups, isEmpty);
    });

    testWidgets('too many lookups say so; a missing route says the website is not updated',
        (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)
        ..lookupError = const ApiError(status: 429, code: 'yazan_mobile_slow_down');
      await _open(tester, client: client, tokens: tokens);
      await enterEmail(tester, 'noor@yazan.test');
      expect(find.text('Too many attempts. Please wait and try again.'), findsOneWidget);
      expect(find.text('Welcome to YAZAN'), findsOneWidget);

      client.lookupError = const ApiError(status: 404, code: 'rest_no_route');
      await _tap(tester, _key('auth-continue'));
      expect(find.text('The website is not updated for the app yet. Please try again later.'),
          findsOneWidget);
    });

    testWidgets('the Terms and the Privacy Policy open on the website', (tester) async {
      final o = await _open(tester);
      expect(find.text('By continuing you agree to the Terms and the Privacy Policy.'),
          findsOneWidget);
      await _tap(tester, _key('auth-terms'));
      await _tap(tester, _key('auth-privacy'));
      expect(o.links, [
        Uri.parse('https://example.test/terms-and-conditions/'),
        Uri.parse('https://example.test/privacy-policy/'),
      ]);
    });
  });

  group('create an account', () {
    testWidgets('a new email goes to "Create your YAZAN account" and signs in when created',
        (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)..lookupAnswer = const AccountLookup(exists: false);
      await _open(tester, client: client, tokens: tokens);

      await enterEmail(tester, 'new@yazan.test');
      expect(find.text('Create your YAZAN account'), findsOneWidget);
      expect(find.text('new@yazan.test'), findsOneWidget);
      expect(find.text('Forgot password?'), findsNothing);
      // The marketing box starts unticked; the consent line is on this step too.
      expect(tester.widget<CheckboxListTile>(_key('auth-marketing')).value, isFalse);
      expect(find.text('By continuing you agree to the Terms and the Privacy Policy.'),
          findsOneWidget);
      // The new password is offered to the phone's password manager as a new one.
      final field = tester.widget<TextField>(
          find.descendant(of: _key('auth-password'), matching: find.byType(TextField)));
      expect(field.autofillHints, [AutofillHints.newPassword]);

      // Too short: said under the field, nothing sent.
      await _fillCreate(tester, password: 'short');
      expect(find.text('At least 8 characters.'), findsOneWidget);
      await _tap(tester, _key('auth-create'));
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(client.registrations, isEmpty);

      await tester.enterText(_key('auth-password'), 'Carnelian-Ring-2026');
      await tester.pump();
      await _tap(tester, _key('auth-create'));

      expect(client.registrations.single, {
        'first_name': 'Noor',
        'last_name': 'Ali',
        'email': 'new@yazan.test',
        'password': 'Carnelian-Ring-2026',
        'marketing_opt_in': false,
        'platform': 'android',
      });
      expect(find.byType(LoginPage), findsNothing);
      expect((await tokens.read())!.accessToken, 'yzm_n');
    });

    testWidgets('names are required', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)..lookupAnswer = const AccountLookup(exists: false);
      await _open(tester, client: client, tokens: tokens);
      await enterEmail(tester, 'new@yazan.test');
      await tester.enterText(_key('auth-password'), 'eightchr');
      await tester.pump();
      expect(find.text('Good. A longer phrase is stronger.'), findsOneWidget);
      await tester.enterText(_key('auth-password'), 'Carnelian-Ring-2026');
      await tester.pump();
      expect(find.text('Strong password.'), findsOneWidget);
      await _tap(tester, _key('auth-create'));
      expect(find.text('Required'), findsNWidgets(2));
      expect(client.registrations, isEmpty);
    });

    testWidgets('an email that is already taken switches to the sign-in step', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)
        ..lookupAnswer = const AccountLookup(exists: false)
        ..registerError = const ApiError(status: 409, code: 'yazan_mobile_email_taken');
      await _open(tester, client: client, tokens: tokens);
      await enterEmail(tester, 'noor@yazan.test');
      await _fillCreate(tester);
      await _tap(tester, _key('auth-marketing'));
      await _tap(tester, _key('auth-create'));

      expect(client.registrations.single['marketing_opt_in'], isTrue);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('An account with this email already exists. Please sign in.'),
          findsOneWidget);
      expect(_passwordText(tester).controller.text, isEmpty);
      expect(await tokens.read(), isNull);

      await tester.enterText(_key('auth-password'), 'secret-password');
      await _tap(tester, _key('auth-sign-in'));
      expect(client.logins, ['noor@yazan.test']);
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets('each refusal of the server has its own message', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)..lookupAnswer = const AccountLookup(exists: false);
      await _open(tester, client: client, tokens: tokens);
      await enterEmail(tester, 'new@yazan.test');
      await _fillCreate(tester);

      const cases = <(ApiError, String)>[
        (
          ApiError(status: 400, code: 'yazan_mobile_weak_password'),
          'That password is too easy to guess. Please choose a stronger one.',
        ),
        (
          ApiError(status: 400, code: 'yazan_mobile_terms_required'),
          'Please agree to the Terms and the Privacy Policy to create an account.',
        ),
        (
          ApiError(status: 400, code: 'yazan_mobile_bad_email'),
          'Please enter a valid email address.',
        ),
        (
          ApiError(status: 403, code: 'yazan_mobile_registration_closed'),
          'New accounts cannot be created in the app at the moment. Please try again later.',
        ),
        (
          ApiError(status: 429, code: 'yazan_mobile_slow_down'),
          'Too many attempts. Please wait and try again.',
        ),
      ];
      for (final (error, message) in cases) {
        client.registerError = error;
        await _tap(tester, _key('auth-create'));
        expect(find.text(message), findsOneWidget, reason: error.code);
        expect(find.text('Create your YAZAN account'), findsOneWidget);
      }

      // Anything else: the generic message with the code in small print.
      client.registerError = const ApiError(status: 500, code: 'boom');
      await _tap(tester, _key('auth-create'));
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('(code: boom, 500)'), findsOneWidget);
      expect(await tokens.read(), isNull);
    });
  });

  group('forgot password', () {
    testWidgets('shows "Check your inbox" with a 60 second resend timer', (tester) async {
      final o = await _open(tester);
      await enterEmail(tester, 'noor@yazan.test', settle: false);

      await tester.tap(_key('auth-forgot'));
      await tester.pump();
      await tester.pump();
      expect(o.client.forgotten, ['noor@yazan.test']);
      expect(find.text('Check your inbox'), findsOneWidget);
      expect(
          find.text(
              'If an account exists for noor@yazan.test, a link to choose a new password is on its way.'),
          findsOneWidget);
      expect(find.text('Resend in 60 s'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(_key('auth-resend')).onPressed, isNull);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Resend in 59 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 59));
      expect(find.text('Resend email'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(_key('auth-resend')).onPressed, isNotNull);

      await tester.tap(_key('auth-resend'));
      await tester.pump();
      await tester.pump();
      expect(o.client.forgotten, ['noor@yazan.test', 'noor@yazan.test']);
      expect(find.text('Resend in 60 s'), findsOneWidget);

      await tester.tap(_key('auth-back-to-sign-in'));
      await steps(tester);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('too many requests are said in place, without the inbox screen', (tester) async {
      final tokens = MemoryTokenStore();
      final client = ScriptedClient(tokens)
        ..forgotError = const ApiError(status: 429, code: 'yazan_mobile_slow_down');
      await _open(tester, client: client, tokens: tokens);
      await enterEmail(tester, 'noor@yazan.test');
      await _tap(tester, _key('auth-forgot'));
      expect(find.text('Too many attempts. Please wait and try again.'), findsOneWidget);
      expect(find.text('Check your inbox'), findsNothing);
    });
  });

  group('Continue with Google', () {
    testWidgets('is hidden when the build has no Google client id', (tester) async {
      await _open(tester);
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.text('or'), findsNothing);
    });

    testWidgets('sends the ID token to auth/social and signs in; sign-out forgets Google too',
        (tester) async {
      final google = FakeTokenSource();
      final o = await _open(tester, google: google);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('or'), findsOneWidget);

      await _tap(tester, _key('google-sign-in'));
      expect(google.asked, 1);
      expect(o.client.socials, ['google:id-token-1:android']);
      expect(o.client.lookups, isEmpty);
      expect(find.byType(LoginPage), findsNothing);
      expect((await o.tokens.read())!.accessToken, 'yzm_g');

      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Sign out'));
      expect(google.signedOut, 1);
    });

    testWidgets('closing the Google sheet does nothing', (tester) async {
      final google = FakeTokenSource(token: null);
      final o = await _open(tester, google: google);
      await _tap(tester, _key('google-sign-in'));
      expect(google.asked, 1);
      expect(o.client.socials, isEmpty);
      expect(find.byKey(const ValueKey('sign-in-error')), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('a Google failure and a server refusal each get a calm message', (tester) async {
      final google = FakeTokenSource(error: const SocialSignInException('google_uiUnavailable'));
      final o = await _open(tester, google: google);
      await _tap(tester, _key('google-sign-in'));
      expect(
          find.text('That sign-in did not finish. Please try again or continue with your email.'),
          findsOneWidget);
      expect(find.text('(code: google_uiUnavailable)'), findsOneWidget);
      expect(o.client.socials, isEmpty);

      google.error = null;
      o.client.socialError = const ApiError(status: 404, code: 'yazan_mobile_social_unavailable');
      await _tap(tester, _key('google-sign-in'));
      expect(
          find.text(
              'This way of signing in is not available yet. Please continue with your email.'),
          findsOneWidget);
      expect(await o.tokens.read(), isNull);
    });
  });

  group('delete account', () {
    testWidgets('asks for the password, then wipes the phone and carries on as a guest',
        (tester) async {
      final o = await _open(tester, signedIn: true);
      expect(find.text('Noor Ali'), findsOneWidget);

      await _tap(tester, _key('delete-account'));
      expect(find.text('Delete your account'), findsOneWidget);

      // No password: the server asks for it (or a fresh Google / Apple sign-in).
      o.account.deleteError = const ApiError(status: 403, code: 'yazan_mobile_reauth_required');
      await _tap(tester, _key('delete-confirm'));
      expect(
          find.text('Enter your password to confirm. If you signed up with Google or Apple, '
              'sign in again and delete within 5 minutes.'),
          findsOneWidget);

      // The website's own deletion page is one tap away.
      await _tap(tester, _key('delete-on-website'));
      expect(o.links, [Uri.parse('https://example.test/account-deletion/')]);

      // A wrong password is said in place; nothing is wiped.
      o.account.deleteError = const ApiError(status: 403, code: 'yazan_mobile_bad_password');
      await tester.enterText(_key('delete-password'), 'wrong');
      await tester.pump();
      await _tap(tester, _key('delete-confirm'));
      expect(find.text('The password is not right.'), findsOneWidget);
      expect(await o.tokens.read(), isNotNull);

      o.account.deleteError = null;
      await tester.enterText(_key('delete-password'), 'secret-password');
      await tester.pump();
      await _tap(tester, _key('delete-confirm'));

      expect(o.account.deletions, ['', 'wrong', 'secret-password']);
      expect(await o.tokens.read(), isNull);
      expect(o.client.clearedSessions, greaterThanOrEqualTo(1));
      expect(find.text('Delete your account'), findsNothing);
      expect(find.text('Your account has been deleted.'), findsOneWidget);
      expect(find.byTooltip('Cart'), findsOneWidget);

      // A guest again: the account entry opens the sign-in screen.
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to YAZAN'), findsOneWidget);
    });

    testWidgets('Cancel keeps the account', (tester) async {
      final o = await _open(tester, signedIn: true);
      await _tap(tester, _key('delete-account'));
      await _tap(tester, find.text('Cancel'));
      expect(find.text('Delete your account'), findsNothing);
      expect(o.account.deletions, isEmpty);
      expect(await o.tokens.read(), isNotNull);
      expect(find.text('Noor Ali'), findsOneWidget);
    });
  });

  testWidgets('Arabic: the sheet mirrors, while the email and password stay left to right',
      (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ar')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await _open(tester, google: FakeTokenSource(), accountTooltip: 'الحساب');

    expect(find.text('أهلاً بك في يزن'), findsOneWidget);
    expect(find.text('المتابعة باستخدام Google'), findsOneWidget);
    expect(find.text('متابعة'), findsOneWidget);
    expect(find.text('طرق أخرى لتسجيل الدخول'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('أهلاً بك في يزن'))), TextDirection.rtl);
    final email = tester.widget<TextField>(_key('auth-email'));
    expect(email.textDirection, TextDirection.ltr);
    expect(email.autofillHints, [AutofillHints.email]);

    await enterEmail(tester, 'noor@yazan.test');
    expect(find.text('أهلاً بعودتك'), findsOneWidget);
    expect(find.text('نسيت كلمة المرور؟'), findsOneWidget);
    final password = tester.widget<TextField>(
        find.descendant(of: _key('auth-password'), matching: find.byType(TextField)));
    expect(password.textDirection, TextDirection.ltr);
    expect(password.autofillHints, [AutofillHints.password]);
    expect(tester.takeException(), isNull);
  });
}
