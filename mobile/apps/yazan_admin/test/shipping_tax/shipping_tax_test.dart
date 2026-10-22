import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/dashboard/dashboard_format.dart';
import 'package:yazan_admin/src/more/more_registry.dart';
import 'package:yazan_admin/src/more/staff_permissions.dart';
import 'package:yazan_admin/src/shipping_tax/shipping_tax_page.dart';
import 'package:yazan_admin/src/shipping_tax/shipping_tax_repository.dart';
import 'package:yazan_admin/src/shipping_tax/shipping_tax_snapshot.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../dashboard/fakes.dart' show dashboardHost, tallScreen;
import 'fakes.dart';

Widget _page(ShippingTaxRepository repo, {Locale locale = const Locale('en')}) =>
    dashboardHost(locale, ShippingTaxPage(repository: repo));

Finder _in(String key, Finder what) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: what);

/// Lets the fake answers arrive. The page shows a spinner until then, so no pumpAndSettle.
Future<void> _load(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _forbidden = ApiError(status: 403, code: 'yazan_forbidden');

ShippingMethodInfo _method(String id, Map<String, String> values) => ShippingMethodInfo(
      instanceId: 1,
      methodId: id,
      title: id,
      methodTitle: id,
      enabled: true,
      values: values,
      labels: const {},
    );

void main() {
  testWidgets('English: zones with their methods and costs, then tax settings and rates', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(FakeShippingTaxServer().repository()));
    await _load(tester);

    // Shipping.
    expect(find.text('Shipping zones'), findsOneWidget);
    expect(_in('shipping-zone-3', find.text('Gulf')), findsOneWidget);
    expect(_in('shipping-zone-3', find.text('Saudi Arabia, Yemen')), findsOneWidget);
    expect(_in('shipping-method-7', find.text('Express courier')), findsOneWidget);
    expect(_in('shipping-method-7', find.text('Flat rate')), findsOneWidget);
    expect(find.text('Cost: ${isolate('25')}'), findsOneWidget);
    expect(find.text('"Heavy" shipping class cost: ${isolate('10')}'), findsOneWidget);
    expect(find.textContaining('No shipping class cost'), findsNothing); // empty: not shown
    expect(_in('shipping-method-7-state', find.text('On')), findsOneWidget);
    expect(find.text('Free on orders of ${isolate('500')} or more'), findsOneWidget);
    expect(_in('shipping-method-8-state', find.text('Off')), findsOneWidget);
    // The fallback zone in the app's words, not WooCommerce's.
    expect(_in('shipping-zone-0', find.text('Rest of the world')), findsOneWidget);
    expect(find.text('Locations not covered by your other zones'), findsNothing);
    expect(find.byKey(const ValueKey('shipping-zone-0-empty')), findsOneWidget);

    // Tax.
    expect(find.text('Taxes are calculated at checkout'), findsOneWidget);
    expect(_in('tax-setting-woocommerce_calc_taxes', find.text('Yes')), findsOneWidget);
    expect(_in('tax-setting-woocommerce_prices_include_tax', find.text('Exclusive of tax')), findsOneWidget);
    expect(_in('tax-setting-woocommerce_tax_based_on', find.text('Customer shipping address')), findsOneWidget);
    expect(_in('tax-setting-woocommerce_shipping_tax_class', find.text('Reduced rate')), findsOneWidget);
    expect(_in('tax-setting-woocommerce_price_display_suffix', find.text('Not set')), findsOneWidget);
    expect(find.text('Standard rates (2)'), findsOneWidget);
    expect(_in('tax-rate-11', find.text('NY tax')), findsOneWidget);
    expect(_in('tax-rate-11-percent', find.text('8.875%')), findsOneWidget);
    expect(_in('tax-rate-11-where', find.text(isolate('US · NY'))), findsOneWidget);
    expect(_in('tax-rate-11', find.text('Priority 1 · Also on shipping · Automatic')), findsOneWidget);
    expect(_in('tax-rate-12-percent', find.text('5%')), findsOneWidget);
    expect(_in('tax-rate-12-where', find.text('Everywhere')), findsOneWidget);
    expect(_in('tax-rate-12', find.text('Priority 2 · Compound')), findsOneWidget);
    expect(find.text('Reduced rate rates (0)'), findsOneWidget);
    expect(find.byKey(const ValueKey('tax-class-reduced-rate-empty')), findsOneWidget);

    expect(find.textContaining('2026-10-20 14:05'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('shiptax-stale')), findsNothing);
  });

  testWidgets('read only: nothing to type in, switch or press', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(FakeShippingTaxServer().repository()));
    await _load(tester);

    expect(find.byKey(const ValueKey('shiptax-readonly')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('Arabic: translated wording, right to left', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(_page(FakeShippingTaxServer().repository(), locale: const Locale('ar')));
    await _load(tester);

    expect(find.text('مناطق الشحن'), findsOneWidget);
    expect(find.text('بقية العالم'), findsOneWidget);
    expect(find.text('التكلفة: ${isolate('25')}'), findsOneWidget);
    expect(_in('shipping-method-8-state', find.text('متوقفة')), findsOneWidget);
    expect(find.text('الضريبة'), findsOneWidget);
    expect(_in('tax-setting-woocommerce_prices_include_tax', find.text('غير شاملة الضريبة')), findsOneWidget);
    expect(find.text('القياسية · النسب (2)'), findsOneWidget);
    expect(find.text('Gulf'), findsOneWidget); // owner-entered names stay as typed
    expect(
      Directionality.of(tester.element(find.byKey(const ValueKey('shipping-zone-3')))),
      TextDirection.rtl,
    );
  });

  testWidgets('tax only: shipping says no access, tax still shows', (tester) async {
    tallScreen(tester);
    final server = FakeShippingTaxServer()..zonesFailure = _forbidden;
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);

    expect(find.byKey(const ValueKey('shipping-no-access')), findsOneWidget);
    expect(find.text('Your account cannot view shipping settings.'), findsOneWidget);
    expect(find.byKey(const ValueKey('shipping-zone-3')), findsNothing);
    expect(find.text('Standard rates (2)'), findsOneWidget);
    expect(find.text('No access'), findsNothing);
  });

  testWidgets('shipping only: tax says no access, zones still show', (tester) async {
    tallScreen(tester);
    final server = FakeShippingTaxServer()..taxFailure = _forbidden;
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);

    expect(find.byKey(const ValueKey('tax-no-access')), findsOneWidget);
    expect(find.byKey(const ValueKey('shipping-zone-3')), findsOneWidget);
    expect(server.ratesAsked, isEmpty);
  });

  testWidgets('no access when the server refuses both', (tester) async {
    final server = FakeShippingTaxServer()
      ..zonesFailure = _forbidden
      ..taxFailure = _forbidden;
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);

    expect(find.text('No access'), findsOneWidget);
    expect(find.textContaining('view shipping or tax settings'), findsOneWidget);
  });

  testWidgets('offline: the cached settings show with the offline badge', (tester) async {
    tallScreen(tester);
    final store = MemoryFeedStore();
    await FakeShippingTaxServer().repository(store: store).refresh();

    final server = FakeShippingTaxServer()..goOffline();
    await tester.pumpWidget(_page(server.repository(store: store)));
    await _load(tester);

    expect(find.byKey(const ValueKey('shiptax-stale')), findsOneWidget);
    expect(find.text('Cost: ${isolate('25')}'), findsOneWidget);
    expect(_in('tax-rate-11-percent', find.text('8.875%')), findsOneWidget);
    expect(find.textContaining('2026-10-20 14:05'), findsNWidgets(2));
  });

  testWidgets('offline with nothing cached: a retry hint', (tester) async {
    final server = FakeShippingTaxServer()..goOffline();
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);

    expect(find.byKey(const ValueKey('shiptax-failed')), findsOneWidget);
    expect(find.textContaining('Could not load the shipping and tax settings'), findsOneWidget);
  });

  testWidgets('one part offline: the other still shows, the missing one says so', (tester) async {
    tallScreen(tester);
    final server = FakeShippingTaxServer()..taxFailure = Exception('offline');
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);

    expect(find.byKey(const ValueKey('shipping-zone-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('tax-failed')), findsOneWidget);
    expect(find.byKey(const ValueKey('shiptax-stale')), findsOneWidget);
  });

  testWidgets('pull to refresh asks the server again', (tester) async {
    tallScreen(tester);
    final server = FakeShippingTaxServer();
    await tester.pumpWidget(_page(server.repository()));
    await _load(tester);
    expect(server.zoneCalls, 1);

    final next = zonesAnswer();
    ((next['zones'] as List).first as Map)['name'] = 'Gulf and Levant';
    server.zones = next;
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(server.zoneCalls, 2);
    expect(server.taxCalls, 2);
    expect(find.text('Gulf and Levant'), findsOneWidget);
  });

  group('repository', () {
    test('asks for the rate table of each class that has rates, by slug', () async {
      final server = FakeShippingTaxServer();
      server.tax['classes'] = [
        {'slug': '', 'name': 'Standard', 'rates': 2},
        {'slug': 'reduced-rate', 'name': 'Reduced rate', 'rates': 0},
        {'slug': 'zero-rate', 'name': 'Zero rate'}, // count not given: asked anyway
      ];
      final repo = server.repository();
      await repo.refresh();

      expect(server.ratesAsked, ['', 'zero-rate']);
      expect(repo.tax!.classes.map((c) => c.slug), ['', 'reduced-rate', 'zero-rate']);
      expect(repo.tax!.classes.first.rates, hasLength(2));
      expect(repo.lastRefreshFailed, isFalse);
    });

    test('a failed rate table keeps the cached tax copy and reports the failure', () async {
      final store = MemoryFeedStore();
      final server = FakeShippingTaxServer();
      final repo = server.repository(store: store);
      await repo.refresh();

      server.ratesFailure = Exception('offline');
      await repo.refresh();
      expect(repo.lastRefreshFailed, isTrue);
      expect(repo.tax!.classes.first.rates, hasLength(2));
      expect(repo.taxNoAccess, isFalse);
    });

    test('a 403 on one part drops only that part from the phone', () async {
      final store = MemoryFeedStore();
      final server = FakeShippingTaxServer();
      final repo = server.repository(store: store);
      await repo.refresh();
      expect((await store.readAll()).map((r) => r['id']), unorderedEquals([1, 2]));

      server.zonesFailure = _forbidden;
      await repo.refresh();
      expect(repo.shippingNoAccess, isTrue);
      expect(repo.noAccess, isFalse);
      expect(repo.shipping, isNull);
      expect(repo.lastRefreshFailed, isFalse);
      expect((await store.readAll()).map((r) => r['id']), [ShippingTaxRepository.taxRow]);

      server.taxFailure = _forbidden;
      await repo.refresh();
      expect(repo.noAccess, isTrue);
      expect(await store.readAll(), isEmpty);
    });

    test('the cached copy survives a restart unchanged', () async {
      final store = MemoryFeedStore();
      await FakeShippingTaxServer().repository(store: store).refresh();

      final again = FakeShippingTaxServer().repository(store: store);
      await again.ready;
      final method = again.shipping!.zones.first.methods.first;
      expect(method.value('cost'), '25');
      expect(method.classCosts.single.value, '10');
      expect(again.shipping!.zones.last.isFallback, isTrue);
      expect(again.tax!.enabled, isTrue);
      expect(again.tax!.settings.first.value, 'yes');
      expect(again.tax!.classes.first.rates.first.percent, '8.875');
    });
  });

  group('wording', () {
    late AppLocalizations l;
    setUpAll(() async => l = await AppLocalizations.delegate.load(const Locale('en')));

    test('method cost summaries', () {
      expect(methodCostSummary(l, _method('flat_rate', {'cost': '20'})), 'Cost: ${isolate('20')}');
      expect(methodCostSummary(l, _method('flat_rate', {'cost': ''})), 'No charge');
      expect(methodCostSummary(l, _method('free_shipping', {'requires': ''})), 'Always free');
      expect(methodCostSummary(l, _method('free_shipping', {'requires': 'coupon'})),
          'Free with a free-shipping coupon');
      expect(methodCostSummary(l, _method('free_shipping', {'requires': 'either', 'min_amount': '300'})),
          'Free on orders of ${isolate('300')} or more, or with a coupon');
      expect(methodCostSummary(l, _method('local_pickup', {'cost': '5'})), 'Cost: ${isolate('5')}');
      expect(methodCostSummary(l, _method('yazan_live_rates', const {})), 'Carrier-calculated rates');
      expect(methodCostSummary(l, _method('some_plugin_rate', const {})), '');
    });

    test('tax values fall back to the server choice, then the stored text', () {
      const custom = TaxSetting(
        option: 'woocommerce_something_new',
        type: 'select',
        label: 'Something new',
        value: 'b',
        choices: {'a': 'Choice A', 'b': 'Choice B'},
      );
      expect(taxSettingLabel(l, custom), 'Something new');
      expect(taxSettingValue(l, custom), 'Choice B');
      const text = TaxSetting(
        option: 'woocommerce_price_display_suffix',
        type: 'text',
        label: 'Price display suffix',
        value: 'incl. VAT',
        choices: {},
      );
      expect(taxSettingValue(l, text), 'incl. VAT');
    });
  });

  group('More tab', () {
    test('the registry has Shipping & tax, shown with either permission', () {
      final entry = moreEntries.firstWhere((e) => e.key == 'shipping-tax');
      expect(entry.permission, isNull);
      expect(entry.anyOf, ['shipping.view', 'tax.view']);
      expect(entry.visibleWith(StaffPermissions.of(['shipping.view'])), isTrue);
      expect(entry.visibleWith(StaffPermissions.of(['tax.view'])), isTrue);
      expect(entry.visibleWith(StaffPermissions.of(['orders.view'])), isFalse);
      expect(entry.visibleWith(const StaffPermissions.unknown()), isTrue);
    });
  });
}
