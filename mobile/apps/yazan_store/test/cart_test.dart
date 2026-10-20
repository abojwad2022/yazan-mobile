import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/src/cart/cart.dart';
import 'package:yazan_store/src/cart/store_api.dart';

import 'fixtures/store_cart.dart';

const _details = CheckoutDetails(
  firstName: 'Yazan',
  lastName: 'Ali',
  phone: '+13135550100',
  email: 'customer@yazan.test',
  address: '12 Market Street',
  city: 'Dearborn',
  state: 'MI',
  postcode: '48126',
  country: 'US',
  note: 'Ring the bell',
);

void main() {
  group('Cart.fromJson', () {
    test('parses a realistic Store API cart', () {
      final cart = Cart.fromJson(storeCart());
      expect(cart.items, hasLength(2));
      expect(cart.itemsCount, 3);

      final first = cart.items.first;
      expect(first.key, 'c51ce410c124a10e0db5e4b97fc2af39');
      expect(first.id, 13);
      expect(first.name, 'Carnelian & Silver Ring');
      expect(first.quantity, 2);
      expect(first.lineTotal, const Money(24000));
      expect(first.lineSubtotal, const Money(24000));
      expect(first.imageUrl, 'https://yazan.test/wp-content/uploads/ring-13-300x300.jpg');
      expect(first.canIncrease, isTrue);

      final second = cart.items[1];
      expect(second.name, 'Aqeeq Signet – Black');
      expect(second.lineTotal, const Money(9000));
      expect(second.imageUrl, isNull);
      expect(second.canIncrease, isFalse, reason: 'quantity_limits.maximum is 1');

      expect(cart.totals.subtotal, const Money(33000));
      expect(cart.totals.shipping, const Money(1000));
      expect(cart.totals.tax, const Money(0));
      expect(cart.totals.discount, const Money(0));
      expect(cart.totals.total, const Money(34000));
      expect(cart.totals.total.toString(), 'USD 340.00');

      expect(cart.errors, isEmpty);
      expect(cart.acceptsCashOnDelivery, isTrue);
      expect(cart.needsShipping, isTrue);
      expect(cart.countryOr('XX'), 'US');
      expect(cart.billing['email'], 'customer@yazan.test');
    });

    test('tolerates an empty or malformed cart', () {
      final cart = Cart.fromJson({
        'items': ['nope', 3],
        'totals': {'total_price': 'abc', 'total_shipping': null},
        'errors': [
          {'code': 'woocommerce_rest_product_out_of_stock', 'message': '<b>Ring</b> is out of stock.'},
          'junk',
        ],
      });
      expect(cart.isEmpty, isTrue);
      expect(cart.itemsCount, 0);
      expect(cart.totals.total, const Money(0));
      expect(cart.totals.shipping, isNull, reason: 'not calculated yet');
      expect(cart.errors, ['Ring is out of stock.']);
      expect(cart.acceptsCashOnDelivery, isFalse);
      expect(cart.countryOr('US'), 'US');
    });

    test('minor units are read in the currency precision', () {
      expect(storeMoney('24000', currency: 'USD', minorUnit: 2), const Money(24000));
      expect(storeMoney('250', currency: 'JPY', minorUnit: 0), const Money(25000, 'JPY'));
      expect(storeMoney('12345', currency: 'KWD', minorUnit: 3), const Money(1235, 'KWD'));
      expect(storeMoney(-500, currency: 'USD', minorUnit: 2), const Money(-500));
      expect(storeMoney('', currency: 'USD', minorUnit: 2), isNull);
      expect(storeMoney(null, currency: 'USD', minorUnit: 2), isNull);
    });

    test('checkout body pays cash on delivery', () {
      final body = _details.toJson();
      expect(body['payment_method'], 'cod');
      expect(body['customer_note'], 'Ring the bell');
      final billing = body['billing_address'] as Map<String, dynamic>;
      final shipping = body['shipping_address'] as Map<String, dynamic>;
      expect(billing['email'], 'customer@yazan.test');
      expect(billing['country'], 'US');
      expect(shipping['address_1'], '12 Market Street');
      expect(shipping.containsKey('email'), isFalse);
    });

    test('placed order falls back to the id for its number', () {
      expect(PlacedOrder.fromJson(checkoutSuccess()).orderNumber, '1042');
      expect(PlacedOrder.fromJson({'order_id': 77}).orderNumber, '77');
    });
  });

  group('StoreApi Cart-Token', () {
    test('stores the token it receives and sends it on every later call', () async {
      final tokens = MemoryCartTokenStore();
      final fake = FakeTransport((r) => ok(storeCart(), headers: {'Cart-Token': 'tok-1'}));
      final api = StoreApi(fake.call, tokens: tokens);

      await api.getCart();
      await api.addItem(13, quantity: 1);
      await api.updateItem('c51ce410c124a10e0db5e4b97fc2af39', 3);
      await api.removeItem('aab3238922bcc25a6f606eb525ffdc56');

      expect(fake.requests.first.headers.containsKey('Cart-Token'), isFalse);
      for (final r in fake.requests.skip(1)) {
        expect(r.headers['Cart-Token'], 'tok-1', reason: r.path);
      }
      expect(tokens.token, 'tok-1');
      expect([for (final r in fake.requests) r.path], [
        '/wc/store/v1/cart',
        '/wc/store/v1/cart/add-item',
        '/wc/store/v1/cart/update-item',
        '/wc/store/v1/cart/remove-item',
      ]);
      expect(fake.requests[1].body, {'id': 13, 'quantity': 1});
      expect(fake.requests[2].body, {'key': 'c51ce410c124a10e0db5e4b97fc2af39', 'quantity': 3});
      expect(fake.requests[3].body, {'key': 'aab3238922bcc25a6f606eb525ffdc56'});
    });

    test('a saved token is sent on the first call and a rotated one replaces it', () async {
      final tokens = MemoryCartTokenStore('saved');
      final fake = FakeTransport((r) => ok(storeCart(), headers: {'cart-token': 'rotated'}));
      final api = StoreApi(fake.call, tokens: tokens);

      await api.getCart();
      await api.getCart();

      expect(fake.requests[0].headers['Cart-Token'], 'saved');
      expect(fake.requests[1].headers['Cart-Token'], 'rotated');
      expect(tokens.token, 'rotated');
    });

    test('forgetting the cart drops the token', () async {
      final tokens = MemoryCartTokenStore('saved');
      final fake = FakeTransport((r) => ok(storeCart()));
      final api = StoreApi(fake.call, tokens: tokens);
      await api.forgetCartToken();
      await api.getCart();
      expect(fake.requests.single.headers.containsKey('Cart-Token'), isFalse);
      expect(tokens.token, isNull);
    });

    test('server errors surface with their code and plain message', () async {
      final fake = FakeTransport((r) => failResponse(
            400,
            'woocommerce_rest_cart_product_no_stock',
            'You cannot add &quot;Ring&quot; - it is out of stock.',
          ));
      final api = StoreApi(fake.call);
      await expectLater(
        api.addItem(13),
        throwsA(isA<StoreApiException>()
            .having((e) => e.code, 'code', 'woocommerce_rest_cart_product_no_stock')
            .having((e) => e.message, 'message', 'You cannot add "Ring" - it is out of stock.')
            .having((e) => e.isDefiniteRejection, 'definite', isTrue)),
      );
    });
  });

  group('StoreApi checkout idempotency', () {
    test('a retry after a network failure reuses the same Idempotency-Key', () async {
      var offline = true;
      final fake = FakeTransport((r) {
        if (offline) throw Exception('socket closed');
        return ok(checkoutSuccess());
      });
      final api = StoreApi(fake.call);

      await expectLater(
        api.checkout(_details),
        throwsA(isA<StoreApiException>().having((e) => e.isNetwork, 'network', isTrue)),
      );
      offline = false;
      final order = await api.checkout(_details);

      expect(order.orderNumber, '1042');
      final first = fake.requests[0].headers['Idempotency-Key'];
      final second = fake.requests[1].headers['Idempotency-Key'];
      expect(first, isNotNull);
      expect(first, isNotEmpty);
      expect(second, first);
      expect(fake.requests[0].path, '/wc/store/v1/checkout');
      expect((fake.requests[0].body as Map<String, dynamic>)['payment_method'], 'cod');

      // A new attempt after a placed order gets a fresh key.
      await api.checkout(_details);
      expect(fake.requests[2].headers['Idempotency-Key'], isNot(first));
    });

    test('a 5xx or busy answer keeps the key; a definite rejection replaces it', () async {
      var status = 503;
      final fake = FakeTransport((r) => failResponse(status, 'yazan_idempotency_busy', ''));
      final api = StoreApi(fake.call);

      await expectLater(api.checkout(_details), throwsA(isA<StoreApiException>()));
      status = 409;
      await expectLater(api.checkout(_details), throwsA(isA<StoreApiException>()));
      status = 400;
      fake.handler = (r) => failResponse(status, 'woocommerce_rest_invalid_address', 'Postcode is required.');
      await expectLater(api.checkout(_details), throwsA(isA<StoreApiException>()));
      fake.handler = (r) => ok(checkoutSuccess());
      await api.checkout(_details);

      final keys = [for (final r in fake.requests) r.headers['Idempotency-Key']];
      expect(keys[1], keys[0]);
      expect(keys[2], keys[0]);
      expect(keys[3], isNot(keys[0]), reason: 'the 400 meant no order was created');
    });

    test('a double tap sends one request', () async {
      final fake = FakeTransport((r) => ok(checkoutSuccess()));
      final api = StoreApi(fake.call);
      final a = api.checkout(_details);
      final b = api.checkout(_details);
      final orders = await Future.wait([a, b]);
      expect(fake.requests, hasLength(1));
      expect(orders[0].orderId, orders[1].orderId);
    });
  });
}
