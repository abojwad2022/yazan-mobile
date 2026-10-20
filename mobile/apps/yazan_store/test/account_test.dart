import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/l10n/app_localizations.dart';
import 'package:yazan_store/src/account/account_models.dart';
import 'package:yazan_store/src/account/account_page.dart';
import 'package:yazan_store/src/account/failure.dart';
import 'package:yazan_store/src/catalogue/product.dart';
import 'package:yazan_store/src/wishlist/wishlist_controller.dart';
import 'package:yazan_store/src/wishlist/wishlist_mirror.dart';
import 'package:yazan_store/src/wishlist/wishlist_scope.dart';

import 'fixtures/account_fakes.dart';

Widget _app(Widget home, Locale locale, {WishlistController? wishlist}) {
  final app = MaterialApp(
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
  return wishlist == null ? app : WishlistScope(controller: wishlist, child: app);
}

class _Host {
  _Host(this.api);

  final FakeAccountApi api;
  bool signedOut = false;
  bool sessionEnded = false;

  Widget page() => AccountPage(
        api: api,
        findProduct: (id) async => const Product(id: 13, name: 'Carnelian ring'),
        onSignOut: () async {
          signedOut = true;
        },
        onSessionEnded: () => sessionEnded = true,
      );
}

void main() {
  group('models', () {
    test('Profile uses the display name when no first or last name is set', () {
      final p = Profile.fromJson({'id': 3, 'email': 'a@b.test', 'display_name': 'abu'});
      expect(p.name, 'abu');
      expect(Profile.fromJson(profileJson()).name, 'Noor Ali');
    });

    test('amountText formats decimals and keeps odd amounts readable', () {
      expect(amountText('340.00', 'USD'), 'USD 340.00');
      expect(amountText('1,299.5', 'USD'), 'USD 1299.50');
      expect(amountText('12.345', 'USD'), 'USD 12.345');
      expect(amountText(null, 'USD'), '');
      expect(amountText('', 'USD'), '');
    });

    test('OrderDetail hides zero rows, decodes names and builds the address', () {
      final d = OrderDetail.fromJson(orderDetailJson(1042));
      expect(d.summary.number, '1042');
      expect(d.summary.total, 'USD 340.00');
      expect(d.items.first.name, 'Carnelian & Silver Ring');
      expect(d.items.first.quantity, 2);
      expect(d.subtotal, 'USD 330.00');
      expect(d.shipping, 'USD 10.00');
      expect(d.tax, '');
      expect(d.discount, '');
      expect(d.address, ['Noor Ali', '12 Market Street', 'Dearborn MI 48126', 'US']);
      expect(d.shipments.single.number, 'JD0146');
    });

    test('OrderDetail tolerates a nearly empty record and falls back to billing', () {
      final d = OrderDetail.fromJson({
        'id': 5,
        'billing': {'first_name': 'Sam', 'address_1': '1 Road'},
        'items': ['bad', 3],
        'shipments': [
          {'label': 'DHL'},
        ],
      });
      expect(d.summary.number, '5');
      expect(d.summary.currency, 'USD');
      expect(d.items, isEmpty);
      expect(d.shipments, isEmpty);
      expect(d.address, ['Sam', '1 Road']);
    });

    test('Failure maps server answers and network problems', () {
      Failure f(Object e) => Failure.from(e);
      expect(f(const ApiError(status: 401, code: 'yazan_mobile_bad_refresh')).kind,
          FailureKind.signedOut);
      expect(f(const ApiError(status: 401, code: 'yazan_auth')).kind, FailureKind.signedOut);
      expect(f(const ApiError(status: 429, code: 'unknown')).kind, FailureKind.rateLimited);
      expect(f(const ApiError(status: 403, code: 'yazan_mobile_wrong_app')).kind,
          FailureKind.unavailable);
      expect(f(const ApiError(status: 404, code: 'yazan_mobile_no_order')).kind,
          FailureKind.notFound);
      expect(f(const ApiError(status: 500, code: 'boom')).kind, FailureKind.other);
      expect(f(const FormatException('bad')).kind, FailureKind.other);
      expect(f(Exception('socket')).kind, FailureKind.offline);
    });
  });

  group('account page', () {
    testWidgets('shows who is signed in, my orders and sign out', (tester) async {
      final host = _Host(FakeAccountApi());
      await tester.pumpWidget(_app(host.page(), const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Noor Ali'), findsOneWidget);
      expect(find.text('noor@yazan.test'), findsOneWidget);
      expect(find.text('+13135550100'), findsOneWidget);
      expect(find.text('My orders'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      // No favourites row without a favourites controller in scope.
      expect(find.text('Favourites'), findsNothing);
    });

    testWidgets('sign out hands over to the app once', (tester) async {
      final host = _Host(FakeAccountApi());
      await tester.pumpWidget(_app(host.page(), const Locale('en')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(host.signedOut, isTrue);
    });

    testWidgets('offline: a polite message, retry, and sign out still works', (tester) async {
      final api = FakeAccountApi()..failure = Exception('offline');
      final host = _Host(api);
      await tester.pumpWidget(_app(host.page(), const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('You are offline. Connect to the internet to see this.'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);

      api.failure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Noor Ali'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a finished session asks the app to show the sign-in form', (tester) async {
      final api = FakeAccountApi()
        ..failure = const ApiError(status: 401, code: 'yazan_mobile_bad_refresh');
      final host = _Host(api);
      await tester.pumpWidget(_app(host.page(), const Locale('en')));
      // The page keeps its spinner (nothing replaces it in this host), so settle cannot finish.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(host.sessionEnded, isTrue);
    });

    testWidgets('shows the favourites row when favourites are available', (tester) async {
      final wishlist = WishlistController(api: FakeWishlistApi(), mirror: MemoryWishlistMirror());
      addTearDown(wishlist.dispose);
      final host = _Host(FakeAccountApi());
      await tester.pumpWidget(_app(host.page(), const Locale('en'), wishlist: wishlist));
      await tester.pumpAndSettle();
      expect(find.text('Favourites'), findsOneWidget);
    });
  });

  group('orders', () {
    testWidgets('list, load more, and read-only detail', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = FakeAccountApi();
      final host = _Host(api);
      await tester.pumpWidget(_app(host.page(), const Locale('en')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('My orders'));
      await tester.pumpAndSettle();

      expect(api.calls, contains('orders:1'));
      expect(find.text('Order number 1042'), findsOneWidget);
      expect(find.text('Order number 1031'), findsOneWidget);
      expect(find.textContaining('Processing'), findsOneWidget);
      expect(find.textContaining('Completed'), findsOneWidget);
      expect(find.text('USD 340.00'), findsNWidgets(2));
      expect(find.text('Order number 1020'), findsNothing);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('orders:2'));
      expect(find.text('Order number 1020'), findsOneWidget);
      expect(find.textContaining('On hold'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);

      await tester.tap(find.text('Order number 1042'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('order:1042'));
      expect(find.text('Carnelian & Silver Ring'), findsOneWidget);
      expect(find.text('Quantity 2'), findsOneWidget);
      expect(find.text('USD 240.00'), findsOneWidget);
      expect(find.text('USD 330.00'), findsOneWidget); // subtotal
      expect(find.text('USD 10.00'), findsOneWidget); // shipping
      expect(find.text('Tax'), findsNothing); // zero rows are hidden
      expect(find.text('Discount'), findsNothing);
      expect(find.text('Cash on delivery'), findsOneWidget);
      expect(find.textContaining('12 Market Street'), findsOneWidget);
      expect(find.text('DHL - JD0146'), findsOneWidget);
    });

    testWidgets('no orders yet', (tester) async {
      final api = FakeAccountApi(pages: [
        {'orders': <Object>[], 'total': 0, 'pages': 0},
      ]);
      await tester.pumpWidget(_app(_Host(api).page(), const Locale('en')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My orders'));
      await tester.pumpAndSettle();
      expect(find.text('You have not placed any orders yet.'), findsOneWidget);
    });

    testWidgets('offline: message and retry on the first page', (tester) async {
      final api = FakeAccountApi();
      final host = _Host(api);
      await tester.pumpWidget(_app(host.page(), const Locale('en')));
      await tester.pumpAndSettle();

      api.failure = Exception('offline');
      await tester.tap(find.text('My orders'));
      await tester.pumpAndSettle();
      expect(find.text('You are offline. Connect to the internet to see this.'), findsOneWidget);

      api.failure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Order number 1042'), findsOneWidget);
    });

    testWidgets('a failed second page keeps the orders already shown', (tester) async {
      final api = FakeAccountApi();
      await tester.pumpWidget(_app(_Host(api).page(), const Locale('en')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My orders'));
      await tester.pumpAndSettle();

      api.failure = Exception('offline');
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Order number 1042'), findsOneWidget);
      expect(find.text('You are offline. Connect to the internet to see this.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('an order the server will not show gives a polite message', (tester) async {
      final api = FakeAccountApi();
      await tester.pumpWidget(_app(_Host(api).page(), const Locale('en')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My orders'));
      await tester.pumpAndSettle();

      api.failure = const ApiError(status: 404, code: 'yazan_mobile_no_order');
      await tester.tap(find.text('Order number 1042'));
      await tester.pumpAndSettle();
      expect(find.text('That could not be found.'), findsOneWidget);
    });
  });

  group('Arabic', () {
    testWidgets('account and orders render right-to-left with translated labels', (tester) async {
      final host = _Host(FakeAccountApi());
      await tester.pumpWidget(_app(host.page(), const Locale('ar')));
      await tester.pumpAndSettle();

      expect(find.text('الحساب'), findsOneWidget);
      expect(find.text('تسجيل الخروج'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('طلباتي'))), TextDirection.rtl);

      await tester.tap(find.text('طلباتي'));
      await tester.pumpAndSettle();
      expect(find.text('رقم الطلب 1042'), findsOneWidget);
      expect(find.textContaining('قيد التجهيز'), findsOneWidget);
      expect(find.textContaining('مكتمل'), findsOneWidget);
    });
  });
}
