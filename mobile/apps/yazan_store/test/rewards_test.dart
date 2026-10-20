import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/l10n/app_localizations.dart';
import 'package:yazan_store/src/extras/extras_menu.dart';
import 'package:yazan_store/src/rewards/rewards_api.dart';
import 'package:yazan_store/src/rewards/rewards_models.dart';
import 'package:yazan_store/src/rewards/rewards_page.dart';
import 'package:yazan_store/src/session_scope.dart';
import 'package:yazan_store/src/verify/verify_page.dart';

import 'fixtures/scripted_client.dart';
import 'fixtures/verify_rewards_fakes.dart';

Widget _app(Widget home, Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

Widget _page(RewardsApi api, {Locale locale = const Locale('en'), VoidCallback? onEnded}) =>
    _app(RewardsPage(api: api, onSessionEnded: onEnded ?? () {}), locale);

void main() {
  group('RewardsSummary', () {
    test('reads balance, labels, tier and the next level', () {
      final s = RewardsSummary.fromJson(rewardsMeJson());
      expect(s.points, 1250);
      expect(s.label, 'Points');
      expect(s.tierName, 'Silver');
      expect(s.next!.name, 'Gold');
      expect(s.next!.remaining, 250);
      expect(s.next!.progress, 0.5);
    });

    test('the singular word is used for exactly one point', () {
      expect(RewardsSummary.fromJson(rewardsMeJson(balance: 1)).label, 'Point');
      expect(RewardsSummary.fromJson(rewardsMeJson(balance: 0)).label, 'Points');
    });

    test('no label from the server means no label', () {
      final s = RewardsSummary.fromJson({
        'points': {'balance': '40'},
      });
      expect(s.points, 40);
      expect(s.label, isNull);
      expect(s.tierName, '');
      expect(s.next, isNull);
    });

    test('an empty cached tier falls back to the level the server computed', () {
      final s = RewardsSummary.fromJson(rewardsMeJson(tier: ''));
      expect(s.tierName, 'Silver');
    });

    test('a foreign answer is refused, never shown as zero points', () {
      expect(() => RewardsSummary.fromJson(<String, dynamic>{}), throwsFormatException);
      expect(() => ReferralInfo.fromJson(<String, dynamic>{'code': ' '}), throwsFormatException);
    });

    test('next level values are kept in range', () {
      final s = RewardsSummary.fromJson({
        'points': {'balance': 5},
        'level': {
          'next': {'name': 'Gold', 'remaining': -3, 'progress': 7},
        },
      });
      expect(s.next!.remaining, 0);
      expect(s.next!.progress, 1.0);
    });
  });

  group('ClientRewardsApi', () {
    test('uses only the two customer routes', () async {
      final client = GetJsonClient(MemoryTokenStore(), (path) {
        return path.endsWith('/referral') ? referralJson() : rewardsMeJson();
      });
      final api = ClientRewardsApi(client);
      expect((await api.summary()).points, 1250);
      expect((await api.referral()).code, 'NOOR7K');
      expect([for (final g in client.gets) g.path], [
        '/yazan-rewards/v1/me',
        '/yazan-rewards/v1/referral',
      ]);
    });
  });

  group('rewards page', () {
    testWidgets('shows points, tier, progress to the next level and the referral code', (tester) async {
      final api = FakeRewardsApi();
      await tester.pumpWidget(_page(api));
      await tester.pumpAndSettle();

      expect(api.calls.toSet(), {'me', 'referral'});
      expect(find.text('Rewards'), findsOneWidget);
      expect(find.text('1250'), findsOneWidget);
      expect(find.text('Points'), findsOneWidget);
      expect(find.text('Silver'), findsOneWidget);
      expect(find.text('250 Points to go until Gold'), findsOneWidget);
      expect(find.text('NOOR7K'), findsOneWidget);
      expect(find.text('https://yazan.test/?ref=NOOR7K'), findsOneWidget);
      // Nothing that could change a balance is on the screen.
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('a customer with no tier yet is told so', (tester) async {
      final api = FakeRewardsApi(me: {
        'points': {
          'balance': 0,
          'label': {'singular': 'Point', 'plural': 'Points'},
        },
      });
      await tester.pumpWidget(_page(api));
      await tester.pumpAndSettle();
      expect(find.text('No tier yet'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('copies the code and the link and says so', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map<Object?, Object?>)['text']! as String);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(_page(FakeRewardsApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Copy code'));
      await tester.pumpAndSettle();
      expect(copied, ['NOOR7K']);
      expect(find.text('Copied'), findsOneWidget);

      await tester.tap(find.byTooltip('Copy link'));
      await tester.pumpAndSettle();
      expect(copied.last, 'https://yazan.test/?ref=NOOR7K');
    });

    testWidgets('the referral code failing does not hide the points, and can be retried', (tester) async {
      final api = FakeRewardsApi()..referralFailure = Exception('offline');
      await tester.pumpWidget(_page(api));
      await tester.pumpAndSettle();

      expect(find.text('1250'), findsOneWidget);
      expect(find.text('You are offline. Connect to the internet to see this.'), findsOneWidget);
      expect(find.text('NOOR7K'), findsNothing);

      api.referralFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('NOOR7K'), findsOneWidget);
    });

    testWidgets('offline: says so and offers a retry that works', (tester) async {
      final api = FakeRewardsApi()..summaryFailure = Exception('offline');
      await tester.pumpWidget(_page(api));
      await tester.pumpAndSettle();
      expect(find.text('You are offline. Connect to the internet to see this.'), findsOneWidget);
      expect(find.text('1250'), findsNothing);

      api.summaryFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('1250'), findsOneWidget);
    });

    testWidgets('a rewards system that is off (404) or refused (403) reads as not available', (tester) async {
      final api = FakeRewardsApi()
        ..summaryFailure = const ApiError(status: 404, code: 'rest_no_route')
        ..referralFailure = const ApiError(status: 404, code: 'rest_no_route');
      await tester.pumpWidget(_page(api));
      await tester.pumpAndSettle();
      expect(find.text('Rewards are not available right now.'), findsOneWidget);

      api.summaryFailure = const ApiError(status: 403, code: 'yazan_mobile_wrong_app');
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Rewards are not available right now.'), findsOneWidget);
    });

    testWidgets('a finished session asks the app to show the sign-in form', (tester) async {
      final api = FakeRewardsApi()
        ..summaryFailure = const ApiError(status: 401, code: 'yazan_mobile_bad_refresh');
      var ended = false;
      await tester.pumpWidget(_page(api, onEnded: () => ended = true));
      await tester.pumpAndSettle();
      expect(ended, isTrue);
    });

    testWidgets('Arabic: right-to-left with translated labels', (tester) async {
      await tester.pumpWidget(_page(FakeRewardsApi(), locale: const Locale('ar')));
      await tester.pumpAndSettle();

      expect(find.text('المكافآت'), findsOneWidget);
      expect(find.text('رصيدك'), findsOneWidget);
      expect(find.text('المستوى'), findsOneWidget);
      expect(find.text('رمز الإحالة الخاص بك'), findsOneWidget);
      expect(find.textContaining('250 Points'), findsOneWidget);
      expect(find.textContaining('Gold'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('رصيدك'))), TextDirection.rtl);
      expect(find.byTooltip('نسخ الرمز'), findsOneWidget);
    });
  });

  group('More menu', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
    }

    Widget host({
      required bool signedIn,
      required FakeVerifyApi verify,
      required FakeRewardsApi rewards,
      required List<String> log,
      Locale locale = const Locale('en'),
    }) {
      final client = ScriptedClient(MemoryTokenStore());
      return SessionScope(
        signedIn: signedIn,
        openSignIn: (context) async {
          log.add('sign-in opened');
          return false;
        },
        child: _app(
          Scaffold(
            appBar: AppBar(
              actions: [
                ExtrasMenuButton(
                  client: client,
                  onSessionEnded: () => log.add('session ended'),
                  verifyApi: verify,
                  rewardsApi: rewards,
                ),
              ],
            ),
          ),
          locale,
        ),
      );
    }

    testWidgets('offers both entries', (tester) async {
      await tester.pumpWidget(host(
        signedIn: false,
        verify: FakeVerifyApi(),
        rewards: FakeRewardsApi(),
        log: [],
      ));
      await openMenu(tester);
      expect(find.text('Verify a ring'), findsOneWidget);
      expect(find.text('Rewards'), findsOneWidget);
    });

    testWidgets('verifying a ring needs no account', (tester) async {
      final verify = FakeVerifyApi();
      final rewards = FakeRewardsApi();
      await tester.pumpWidget(host(signedIn: false, verify: verify, rewards: rewards, log: []));
      await openMenu(tester);
      await tester.tap(find.text('Verify a ring'));
      await tester.pumpAndSettle();

      expect(find.byType(VerifyPage), findsOneWidget);
      expect(find.text('Sign in to use this'), findsNothing);
      expect(rewards.calls, isEmpty);
    });

    testWidgets('a guest tapping Rewards is asked to sign in, and "Not now" fetches nothing', (tester) async {
      final rewards = FakeRewardsApi();
      await tester.pumpWidget(host(signedIn: false, verify: FakeVerifyApi(), rewards: rewards, log: []));
      await openMenu(tester);
      await tester.tap(find.text('Rewards'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to use this'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byType(RewardsPage), findsNothing);
      expect(rewards.calls, isEmpty);
    });

    testWidgets('a guest who agrees is sent to the sign-in screen, and still sees no rewards if they stop there',
        (tester) async {
      final rewards = FakeRewardsApi();
      final log = <String>[];
      await tester.pumpWidget(host(signedIn: false, verify: FakeVerifyApi(), rewards: rewards, log: log));
      await openMenu(tester);
      await tester.tap(find.text('Rewards'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(log, ['sign-in opened']);
      expect(find.byType(RewardsPage), findsNothing);
      expect(rewards.calls, isEmpty);
    });

    testWidgets('a signed-in customer reaches the rewards', (tester) async {
      final rewards = FakeRewardsApi();
      await tester.pumpWidget(host(signedIn: true, verify: FakeVerifyApi(), rewards: rewards, log: []));
      await openMenu(tester);
      await tester.tap(find.text('Rewards'));
      await tester.pumpAndSettle();

      expect(find.byType(RewardsPage), findsOneWidget);
      expect(find.text('1250'), findsOneWidget);
      expect(find.text('Sign in to use this'), findsNothing);
    });

    testWidgets('the menu is translated and right-to-left in Arabic', (tester) async {
      await tester.pumpWidget(host(
        signedIn: true,
        verify: FakeVerifyApi(),
        rewards: FakeRewardsApi(),
        log: [],
        locale: const Locale('ar'),
      ));
      await tester.tap(find.byTooltip('المزيد'));
      await tester.pumpAndSettle();
      expect(find.text('التحقق من خاتم'), findsOneWidget);
      expect(find.text('المكافآت'), findsOneWidget);
    });
  });
}
