import 'package:yazan_admin/src/shipping_tax/shipping_tax_repository.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../dashboard/fakes.dart' show fixedNow;

/// One `fields[]` entry of a shipping method, as `GET /yazan/v1/shipping/zones` sends it.
Map<String, dynamic> methodField(String key, String label, Object? value, {String type = 'text'}) =>
    {'key': key, 'label': label, 'type': type, 'description': '', 'options': null, 'value': value};

/// `GET /yazan/v1/shipping/zones`: one zone (Gulf, id 3) with a flat rate of 25 (plus a "Heavy"
/// class cost of 10) and a disabled free-shipping rule from 500, then the fallback zone with no
/// methods.
Map<String, dynamic> zonesAnswer() => {
      'zones': [
        {
          'id': 3,
          'name': 'Gulf',
          'order': 0,
          'is_fallback': false,
          'regions': [
            {'type': 'country', 'code': 'SA'},
            {'type': 'country', 'code': 'YE'},
          ],
          'region_text': 'Saudi Arabia, Yemen',
          'methods': [
            {
              'instance_id': 7,
              'method_id': 'flat_rate',
              'title': 'Express courier',
              'method_title': 'Flat rate',
              'enabled': true,
              'fields': [
                methodField('title', 'Name', 'Express courier'),
                methodField('tax_status', 'Tax status', 'taxable', type: 'select'),
                methodField('cost', 'Cost', '25'),
                methodField('class_cost_12', '"Heavy" shipping class cost', '10'),
                methodField('no_class_cost', 'No shipping class cost', ''),
              ],
            },
            {
              'instance_id': 8,
              'method_id': 'free_shipping',
              'title': 'Free shipping',
              'method_title': 'Free shipping',
              'enabled': false,
              'fields': [
                methodField('requires', 'Free shipping requires', 'min_amount', type: 'select'),
                methodField('min_amount', 'Minimum order amount', '500', type: 'price'),
              ],
            },
          ],
        },
        {
          'id': 0,
          'name': 'Locations not covered by your other zones',
          'order': 0,
          'is_fallback': true,
          'regions': <dynamic>[],
          'region_text': 'Everywhere',
          'methods': <dynamic>[],
        },
      ],
      'available_methods': <dynamic>[],
      'countries': {'SA': 'Saudi Arabia', 'YE': 'Yemen'},
      'options': {'ship_to_countries': 'all'},
      'classes': <dynamic>[],
      'health': <dynamic>[],
    };

/// `GET /yazan/v1/tax`: taxes on, prices exclusive, based on the shipping address, the "Reduced rate"
/// class for shipping, no suffix. Standard has 2 rates, Reduced rate none.
Map<String, dynamic> taxAnswer() => {
      'fields': [
        {
          'option': 'woocommerce_calc_taxes',
          'type': 'bool_yesno',
          'label': 'Enable taxes',
          'choices': <dynamic>[],
          'value': true,
        },
        {
          'option': 'woocommerce_prices_include_tax',
          'type': 'select',
          'label': 'Prices entered with tax',
          'choices': {'yes': 'Yes, I will enter prices inclusive of tax', 'no': 'No, I will enter prices exclusive of tax'},
          'value': 'no',
        },
        {
          'option': 'woocommerce_tax_based_on',
          'type': 'select',
          'label': 'Calculate tax based on',
          'choices': {'shipping': 'Customer shipping address', 'billing': 'Customer billing address', 'base': 'Shop base address'},
          'value': 'shipping',
        },
        {
          'option': 'woocommerce_shipping_tax_class',
          'type': 'select',
          'label': 'Shipping tax class',
          'choices': {'inherit': 'Shipping tax class based on cart items', '': 'Standard', 'reduced-rate': 'Reduced rate'},
          'value': 'reduced-rate',
        },
        {
          'option': 'woocommerce_price_display_suffix',
          'type': 'text',
          'label': 'Price display suffix',
          'choices': <dynamic>[],
          'value': '',
        },
      ],
      'classes': [
        {'slug': '', 'name': 'Standard', 'rates': 2},
        {'slug': 'reduced-rate', 'name': 'Reduced rate', 'rates': 0},
      ],
      'enabled': true,
    };

/// `GET /yazan/v1/tax/rates?class=` (Standard): New York 8.875% on shipping too (automatic), and a
/// 5% compound rate everywhere.
Map<String, dynamic> standardRatesAnswer() => {
      'class': '',
      'items': [
        {
          'id': 11,
          'country': 'US',
          'state': 'NY',
          'postcode': '',
          'city': '',
          'rate': '8.8750',
          'name': 'NY tax',
          'priority': 1,
          'compound': false,
          'shipping': true,
          'class': '',
          'managed': true,
        },
        {
          'id': 12,
          'country': '*',
          'state': '*',
          'postcode': '',
          'city': '',
          'rate': '5.0000',
          'name': 'VAT',
          'priority': 2,
          'compound': true,
          'shipping': false,
          'class': '',
          'managed': false,
        },
      ],
    };

/// A scripted stand-in for the shipping and tax routes. No network anywhere.
class FakeShippingTaxServer {
  Map<String, dynamic> zones = zonesAnswer();
  Map<String, dynamic> tax = taxAnswer();
  Map<String, Map<String, dynamic>> rates = {'': standardRatesAnswer()};

  /// When set, the matching call throws it (and stays set until cleared).
  Object? zonesFailure;
  Object? taxFailure;
  Object? ratesFailure;

  int zoneCalls = 0;
  int taxCalls = 0;

  /// The tax class of every rate table asked for, in order.
  final List<String> ratesAsked = [];

  Future<Map<String, dynamic>> fetchZones() async {
    zoneCalls++;
    if (zonesFailure != null) throw zonesFailure!;
    return zones;
  }

  Future<Map<String, dynamic>> fetchTax() async {
    taxCalls++;
    if (taxFailure != null) throw taxFailure!;
    return tax;
  }

  Future<Map<String, dynamic>> fetchRates(String taxClass) async {
    ratesAsked.add(taxClass);
    if (ratesFailure != null) throw ratesFailure!;
    return rates[taxClass] ?? {'class': taxClass, 'items': <dynamic>[]};
  }

  /// Makes every route fail as if offline.
  void goOffline() {
    zonesFailure = Exception('offline');
    taxFailure = Exception('offline');
  }

  ShippingTaxRepository repository({FeedStore? store}) => ShippingTaxRepository(
        fetchZones: fetchZones,
        fetchTax: fetchTax,
        fetchRates: fetchRates,
        store: store,
        clock: () => fixedNow,
      );
}
