import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/l10n/app_localizations.dart';
import 'package:yazan_store/src/verify/mobile_serial_scanner.dart';
import 'package:yazan_store/src/verify/serial.dart';
import 'package:yazan_store/src/verify/serial_scanner.dart';
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

/// Lets a route push or pop finish and the page react, without pumpAndSettle.
Future<void> _pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

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

    test('Arabic-Indic digits and pasted dashes are read like the typed field reads them', () {
      expect(serialFromScan('YZ-٩٢٥-٢٠٢٦-٠٠٠١٢'), 'YZ-925-2026-00012');
      expect(serialFromScan('yz-۹۲۵-۲۰۲۶'), 'YZ-925-2026');
      expect(serialFromScan('YZ–925—00012'), 'YZ-925-00012');
      expect(serialFromScan('https://yazanus.com/verify-ring/YZ-٩٢٥-٢٠٢٦/'), 'YZ-925-2026');
    });

    test('subdomains of yazanus.com count, and so does the site this build talks to', () {
      expect(serialFromScan('https://shop.yazanus.com/verify-ring/abc-123'), 'ABC-123');
      expect(serialFromScan('HTTPS://YAZANUS.COM/verify-ring/abc-123'), 'ABC-123');
      expect(serialFromScan('yazanus.com/verify-ring/abc-123'), 'ABC-123');
      expect(serialFromScan('https://ar.yazanus.com/ar/verify-ring/abc-123/'), 'ABC-123');
      expect(serialFromScan('http://yazan.test/verify-ring/abc-123/', siteHost: 'yazan.test'), 'ABC-123');
      expect(serialFromScan('http://yazan.test/verify-ring/abc-123/'), isNull);
    });

    test('another site, another page, another scheme or a junk serial in the address is refused', () {
      // Somebody else's verification page, even one that looks like ours.
      expect(serialFromScan('https://example.com/verify-ring/YZ-925-2026-00012/'), isNull);
      expect(serialFromScan('https://yazanus.com.evil.example/verify-ring/abc-123'), isNull);
      expect(serialFromScan('https://evil.example/yazanus.com/verify-ring/abc-123'), isNull);
      expect(serialFromScan('https://notyazanus.com/verify-ring/abc-123'), isNull);
      // Our site, but not the verification page.
      expect(serialFromScan('https://yazanus.com/product/carnelian-signet/'), isNull);
      expect(serialFromScan('https://yazanus.com/?yz_serial=abc-123'), isNull);
      expect(serialFromScan('https://yazanus.com/verify-ring/abc-123/extra'), isNull);
      // Not a web address.
      expect(serialFromScan('ftp://yazanus.com/verify-ring/abc-123'), isNull);
      expect(serialFromScan('javascript://yazanus.com/verify-ring/abc-123'), isNull);
      // The serial in the address must itself be a serial.
      expect(serialFromScan('https://yazanus.com/verify-ring/ab/'), isNull);
      expect(serialFromScan('https://yazanus.com/verify-ring/abc%20123/'), isNull);
      expect(serialFromScan('https://yazanus.com/verify-ring/?yz_serial=%3Cscript%3E'), isNull);
      expect(serialFromScan('https://yazanus.com/verify-ring/%E0%A4%A/'), isNull);
      expect(serialFromScan('YZ/925'), isNull);
      expect(serialFromScan('https://yazanus.com/verify-ring/${'A' * 41}/'), isNull);
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
      expect(find.text("Scan the ring's code"), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('scanning', () {
    testWidgets('a QR code with the verification address fills the serial and checks it', (tester) async {
      final api = FakeVerifyApi();
      final scanner = FakeSerialScanner();
      await tester.pumpWidget(_app(VerifyPage(api: api, scanner: scanner), const Locale('en')));

      await tester.tap(find.text("Scan the ring's code"));
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
      await tester.tap(find.text("Scan the ring's code"));
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
      await tester.tap(find.text("Scan the ring's code"));
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
      await tester.tap(find.text("Scan the ring's code"));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      expect(find.text('Genuine YAZAN ring'), findsNothing);
    });

    test('the app ships the camera scanner', () {
      expect(defaultSerialScanner(), isA<MobileSerialScanner>());
    });

    // The tests below step frames by hand (no pumpAndSettle): the page shows a spinner while it checks.

    testWidgets('the scanner returns a value: the serial fills the field and is checked once',
        (tester) async {
      final api = FakeVerifyApi();
      final scanner = FakeSerialScanner();
      await tester.pumpWidget(_app(VerifyPage(api: api, scanner: scanner), const Locale('en')));
      await tester.pump();

      await tester.tap(find.text("Scan the ring's code"));
      await _pumpRoute(tester);
      expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Arabic-Indic digits as a phone might print them: read like the typed field reads them.
      scanner.emit('YZ-٩٢٥-٢٠٢٦-٠٠٠١٢');
      scanner.emit('YZ-٩٢٥-٢٠٢٦-٠٠٠١٢');
      await _pumpRoute(tester);

      expect(find.byKey(const Key('fake-camera-preview')), findsNothing);
      expect(api.calls, ['YZ-925-2026-00012']);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'YZ-925-2026-00012');
      expect(find.text('Genuine YAZAN ring'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the scanner returns nothing (Cancel): nothing is checked and the field is untouched',
        (tester) async {
      final api = FakeVerifyApi();
      final scanner = FakeSerialScanner();
      await tester.pumpWidget(_app(VerifyPage(api: api, scanner: scanner), const Locale('en')));
      await tester.enterText(find.byType(TextField), 'YZ-1');
      await tester.pump();

      await tester.tap(find.text("Scan the ring's code"));
      await _pumpRoute(tester);
      await tester.tap(find.text('Cancel'));
      await _pumpRoute(tester);

      expect(find.byKey(const Key('fake-camera-preview')), findsNothing);
      expect(api.calls, isEmpty);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'YZ-1');
      expect(find.text('Genuine YAZAN ring'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // A code the camera reads after the screen closed is ignored.
      scanner.emit('YZ-925-2026-00012');
      await tester.pump();
      expect(api.calls, isEmpty);
    });

    testWidgets('camera refused: "Type the serial instead" goes back to the field, scanning still offered',
        (tester) async {
      final api = FakeVerifyApi();
      final scanner = FakeSerialScanner();
      await tester.pumpWidget(_app(VerifyPage(api: api, scanner: scanner), const Locale('en')));
      await tester.pump();

      await tester.tap(find.text("Scan the ring's code"));
      await _pumpRoute(tester);
      scanner.fail();
      await tester.pump();
      expect(find.text('The camera is not available. Type the serial number instead.'), findsOneWidget);
      expect(find.byKey(const Key('fake-camera-preview')), findsNothing);

      await tester.tap(find.text('Type the serial instead'));
      await _pumpRoute(tester);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text("Scan the ring's code"), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('Arabic: the scan button and the camera screen are translated', (tester) async {
      final scanner = FakeSerialScanner();
      await tester.pumpWidget(_app(VerifyPage(api: FakeVerifyApi(), scanner: scanner), const Locale('ar')));
      await tester.pump();

      await tester.tap(find.text('امسح رمز الخاتم'));
      await _pumpRoute(tester);
      expect(find.text('إلغاء'), findsOneWidget);

      scanner.emit('https://example.com/verify-ring/YZ-925-2026-00012/');
      await tester.pump();
      expect(find.text('هذا الرمز ليس رقمًا تسلسليًا من يزن. جرّب رمزًا آخر أو اكتب الرقم.'), findsOneWidget);
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
