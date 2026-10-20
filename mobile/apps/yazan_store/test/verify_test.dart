import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/l10n/app_localizations.dart';
import 'package:yazan_store/src/verify/serial.dart';
import 'package:yazan_store/src/verify/verify_api.dart';
import 'package:yazan_store/src/verify/verify_models.dart';
import 'package:yazan_store/src/verify/verify_page.dart';

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

Future<void> _check(WidgetTester tester, String typed) async {
  await tester.enterText(find.byType(TextField), typed);
  await tester.tap(find.widgetWithText(FilledButton, 'Check'));
  await tester.pumpAndSettle();
}

void main() {
  group('cleanSerial', () {
    test('trims, upper-cases and keeps only letters, digits and hyphens like the server', () {
      expect(cleanSerial('  yz-925-2026-00012 '), 'YZ-925-2026-00012');
      expect(cleanSerial('yz 925/2026'), 'YZ9252026');
    });

    test('Arabic digits and pasted dashes become ordinary ones', () {
      expect(cleanSerial('YZ-٩٢٥-۲۰۲۶'), 'YZ-925-2026');
      expect(cleanSerial('YZ–925—00012'), 'YZ-925-00012');
    });

    test('is capped at 40 characters', () {
      expect(cleanSerial('A' * 60).length, 40);
    });
  });

  group('serialFromScan', () {
    test('a plain serial', () {
      expect(serialFromScan(' yz-925-2026-00012\n'), 'YZ-925-2026-00012');
    });

    test('the address of the verification page, in its path or query forms', () {
      expect(serialFromScan('https://yazanus.com/verify-ring/yz-925-2026-00012/'), 'YZ-925-2026-00012');
      expect(serialFromScan('https://yazanus.com/verify-ring/?yz_serial=YZ-1-2026-7'), 'YZ-1-2026-7');
      expect(serialFromScan('https://yazanus.com/verify-ring/?serial=abc-123'), 'ABC-123');
      expect(serialFromScan('www.yazanus.com/verify-ring/abc-123'), 'ABC-123');
    });

    test('anything else is not a serial', () {
      expect(serialFromScan(''), isNull);
      expect(serialFromScan('ab'), isNull);
      expect(serialFromScan('WIFI:S:home;T:WPA;P:secret;;'), isNull);
      expect(serialFromScan('https://example.com/shop'), isNull);
      expect(serialFromScan('https://yazanus.com/verify-ring/'), isNull);
      expect(serialFromScan('has a space inside'), isNull);
      expect(serialFromScan('A' * 41), isNull);
    });
  });

  group('RingCertificate', () {
    test('reads the server fields and decodes entities', () {
      final c = RingCertificate.fromJson({
        ...certificateJson(origin: 'Yemen'),
        'name': 'Carnelian &amp; Silver',
        'carat': 12,
      });
      expect(c.name, 'Carnelian & Silver');
      expect(c.carat, '12');
      expect(c.origin, 'Yemen');
      expect(c.oneOfOne, isTrue);
      expect(c.imageUrl, isNull);
    });

    test('an answer without a serial is refused, never shown as a ring', () {
      expect(() => RingCertificate.fromJson(<String, dynamic>{}), throwsFormatException);
    });
  });

  group('ClientVerifyApi', () {
    test('asks the public route with a cleaned serial, signed in or not', () async {
      final client = GetJsonClient(MemoryTokenStore(), (path) => certificateJson());
      final certificate = await ClientVerifyApi(client).lookup(' yz-925-2026-00012 ');
      expect(certificate.serial, 'YZ-925-2026-00012');
      expect(client.gets, [
        (path: '/yazan-mobile/v1/verify/YZ-925-2026-00012', optionalAuth: true),
      ]);
    });

    test('a serial that cannot exist is "not found" without asking the server', () async {
      final client = GetJsonClient(MemoryTokenStore(), (path) => certificateJson());
      await expectLater(
        ClientVerifyApi(client).lookup('x/'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 404)),
      );
      expect(client.gets, isEmpty);
    });
  });

  group('verify page', () {
    testWidgets('shows the certificate the server returned, and nothing the server left out',
        (tester) async {
      final api = FakeVerifyApi();
      await tester.pumpWidget(_app(VerifyPage(api: api), const Locale('en')));

      await _check(tester, ' yz-925-2026-00012 ');
      expect(api.calls, ['YZ-925-2026-00012']);
      expect(find.text('Genuine YAZAN ring'), findsOneWidget);
      expect(find.text('Carnelian Signet'), findsOneWidget);
      expect(find.text('Aqeeq'), findsOneWidget);
      expect(find.text('Silver purity'), findsOneWidget);
      expect(find.text('925'), findsOneWidget);
      expect(find.text('Heritage'), findsOneWidget);
      expect(find.text('One of one'), findsOneWidget);
      // The server recorded no origin and no carat: the app says nothing about either.
      expect(find.text('Origin'), findsNothing);
      expect(find.text('Carat'), findsNothing);
      expect(find.text('Yemen'), findsNothing);
      // The field now shows what was checked.
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'YZ-925-2026-00012');
    });

    testWidgets('a field the server did return is shown with its own words', (tester) async {
      final api = FakeVerifyApi(answer: certificateJson(origin: 'Yemen', purity: ''));
      await tester.pumpWidget(_app(VerifyPage(api: api), const Locale('en')));

      await _check(tester, 'YZ-925-2026-00012');
      expect(find.text('Origin'), findsOneWidget);
      expect(find.text('Yemen'), findsOneWidget);
      // No purity was recorded, so none is claimed.
      expect(find.text('Silver purity'), findsNothing);
    });

    testWidgets('not found: says so and names the serial', (tester) async {
      final api = FakeVerifyApi()
        ..failure = const ApiError(status: 404, code: 'yazan_mobile_no_ring');
      await tester.pumpWidget(_app(VerifyPage(api: api), const Locale('en')));

      await _check(tester, 'yz-000-0000-0');
      expect(find.text('No ring found'), findsOneWidget);
      expect(find.textContaining('YZ-000-0000-0'), findsWidgets);
      expect(find.text('Genuine YAZAN ring'), findsNothing);
    });

    testWidgets('a route the server does not know (404 rest_no_route) also reads as not found',
        (tester) async {
      final api = FakeVerifyApi()..failure = const ApiError(status: 404, code: 'rest_no_route');
      await tester.pumpWidget(_app(VerifyPage(api: api), const Locale('en')));

      await _check(tester, 'abc');
      expect(find.text('No ring found'), findsOneWidget);
    });

    testWidgets('rate limited: asks the customer to wait, shows no result', (tester) async {
      final api = FakeVerifyApi()
        ..failure = const ApiError(status: 429, code: 'yazan_rate_limited', retryAfter: 120);
      await tester.pumpWidget(_app(VerifyPage(api: api), const Locale('en')));

      await _check(tester, 'YZ-925-2026-00012');
      expect(find.text('Too many checks in a short time. Please wait a few minutes and try again.'),
          findsOneWidget);
      expect(find.text('Genuine YAZAN ring'), findsNothing);
      expect(find.text('No ring found'), findsNothing);
    });

    testWidgets('offline and unexpected answers each get their own message, and the check can be retried',
        (tester) async {
      final api = FakeVerifyApi()..failure = Exception('offline');
      await tester.pumpWidget(_app(VerifyPage(api: api), const Locale('en')));

      await _check(tester, 'YZ-925-2026-00012');
      expect(find.text('You are offline. Connect to the internet to see this.'), findsOneWidget);

      api.failure = const ApiError(status: 500, code: 'boom');
      await tester.tap(find.widgetWithText(FilledButton, 'Check'));
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong. Check your connection and try again.'), findsOneWidget);

      api.failure = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Check'));
      await tester.pumpAndSettle();
      expect(find.text('Genuine YAZAN ring'), findsOneWidget);
      expect(api.calls, hasLength(3));
    });

    testWidgets('a serial that is too short is refused without asking the server', (tester) async {
      final api = FakeVerifyApi();
      await tester.pumpWidget(_app(VerifyPage(api: api), const Locale('en')));

      await _check(tester, 'ab');
      expect(find.text('Enter at least 3 letters or numbers.'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('editing the serial clears the previous answer', (tester) async {
      final api = FakeVerifyApi();
      await tester.pumpWidget(_app(VerifyPage(api: api), const Locale('en')));
      await _check(tester, 'YZ-925-2026-00012');
      expect(find.text('Genuine YAZAN ring'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'YZ-925-2026-0001');
      await tester.pump();
      expect(find.text('Genuine YAZAN ring'), findsNothing);
    });

    testWidgets('a serial passed in is checked as the screen opens', (tester) async {
      final api = FakeVerifyApi();
      await tester.pumpWidget(
        _app(VerifyPage(api: api, initialSerial: 'yz-925-2026-00012'), const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(api.calls, ['YZ-925-2026-00012']);
      expect(find.text('Genuine YAZAN ring'), findsOneWidget);
    });

    testWidgets('no scan button when the app has no scanner', (tester) async {
      await tester.pumpWidget(_app(VerifyPage(api: FakeVerifyApi()), const Locale('en')));
      expect(find.text('Scan QR code'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('scanning', () {
    testWidgets('a QR code with the verification address fills the serial and checks it', (tester) async {
      final api = FakeVerifyApi();
      final scanner = FakeSerialScanner();
      await tester.pumpWidget(_app(VerifyPage(api: api, scanner: scanner), const Locale('en')));

      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
      expect(find.text('Point the camera at the QR code on your certificate.'), findsOneWidget);

      scanner.emit('https://yazanus.com/verify-ring/yz-925-2026-00012/');
      // The same code arrives again before the screen closes: it must count once.
      scanner.emit('https://yazanus.com/verify-ring/yz-925-2026-00012/');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fake-camera-preview')), findsNothing);
      expect(api.calls, ['YZ-925-2026-00012']);
      expect(find.text('Genuine YAZAN ring'), findsOneWidget);
    });

    testWidgets('a code that is not a serial is refused and scanning goes on', (tester) async {
      final api = FakeVerifyApi();
      final scanner = FakeSerialScanner();
      await tester.pumpWidget(_app(VerifyPage(api: api, scanner: scanner), const Locale('en')));
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();

      scanner.emit('WIFI:S:home;T:WPA;P:secret;;');
      await tester.pumpAndSettle();
      expect(find.text('That code is not a YAZAN serial number. Try another code or type the serial.'),
          findsOneWidget);
      expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
      expect(api.calls, isEmpty);

      scanner.emit('YZ-925-2026-00012');
      await tester.pumpAndSettle();
      expect(api.calls, ['YZ-925-2026-00012']);
    });

    testWidgets('no camera: says so and leaves typing available', (tester) async {
      final scanner = FakeSerialScanner();
      await tester.pumpWidget(_app(VerifyPage(api: FakeVerifyApi(), scanner: scanner), const Locale('en')));
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();

      scanner.fail();
      await tester.pumpAndSettle();
      expect(find.text('The camera is not available. Type the serial number instead.'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('going back from the camera changes nothing', (tester) async {
      final api = FakeVerifyApi();
      await tester.pumpWidget(_app(VerifyPage(api: api, scanner: FakeSerialScanner()), const Locale('en')));
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      expect(find.text('Genuine YAZAN ring'), findsNothing);
    });
  });

  group('verify page, Arabic', () {
    testWidgets('right-to-left with translated labels; the serial field stays left to right', (tester) async {
      final api = FakeVerifyApi(answer: certificateJson(origin: 'اليمن'));
      await tester.pumpWidget(_app(VerifyPage(api: api), const Locale('ar')));
      await tester.pumpAndSettle();

      expect(find.text('التحقق من خاتم'), findsOneWidget);
      expect(find.text('الرقم التسلسلي'), findsWidgets);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textDirection, TextDirection.ltr);

      await tester.enterText(find.byType(TextField), 'YZ-٩٢٥-2026-00012');
      await tester.tap(find.widgetWithText(FilledButton, 'تحقق'));
      await tester.pumpAndSettle();
      expect(api.calls, ['YZ-925-2026-00012']);
      expect(find.text('خاتم أصلي من يزن'), findsOneWidget);
      expect(find.text('المنشأ'), findsOneWidget);
      expect(find.text('اليمن'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('خاتم أصلي من يزن'))), TextDirection.rtl);
    });

    testWidgets('not found and rate limited are translated', (tester) async {
      final api = FakeVerifyApi()
        ..failure = const ApiError(status: 404, code: 'yazan_mobile_no_ring');
      await tester.pumpWidget(_app(VerifyPage(api: api), const Locale('ar')));
      await tester.enterText(find.byType(TextField), 'YZ-000');
      await tester.tap(find.widgetWithText(FilledButton, 'تحقق'));
      await tester.pumpAndSettle();
      expect(find.text('لم يُعثر على خاتم'), findsOneWidget);

      api.failure = const ApiError(status: 429, code: 'yazan_rate_limited');
      await tester.tap(find.widgetWithText(FilledButton, 'تحقق'));
      await tester.pumpAndSettle();
      expect(find.textContaining('محاولات تحقق كثيرة'), findsOneWidget);
    });
  });
}
