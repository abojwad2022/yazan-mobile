import 'package:yazan_store/src/account/account_api.dart';
import 'package:yazan_store/src/account/account_models.dart';
import 'package:yazan_store/src/wishlist/wishlist_api.dart';
import 'package:yazan_store/src/wishlist/wishlist_models.dart';

/// A row of `GET /yazan-mobile/v1/me/orders`.
Map<String, dynamic> orderJson(
  int id,
  String status, {
  String total = '340.00',
  int count = 3,
  String label = '',
}) =>
    <String, dynamic>{
      'id': id,
      'number': '$id',
      'status': status,
      'label': label.isEmpty ? status : label,
      'total': total,
      'currency': 'USD',
      'created': '2026-10-20T10:00:00+00:00',
      'count': count,
      'image': '',
    };

/// `GET /yazan-mobile/v1/me/orders/{id}`: the row plus lines, totals, address and tracking.
Map<String, dynamic> orderDetailJson(int id, {String status = 'processing'}) => <String, dynamic>{
      ...orderJson(id, status),
      'items': <Map<String, dynamic>>[
        {
          'name': 'Carnelian &amp; Silver Ring',
          'quantity': 2,
          'total': '240.00',
          'product_id': 13,
          'image': '',
        },
        {
          'name': 'Aqeeq Signet',
          'quantity': 1,
          'total': '90.00',
          'product_id': 14,
          'image': '',
        },
      ],
      'subtotal': '330.00',
      'shipping_total': '10.00',
      'tax_total': '0',
      'discount_total': '0',
      'payment_method': 'Cash on delivery',
      'billing': <String, dynamic>{'first_name': 'Noor', 'country': 'US'},
      'shipping': <String, dynamic>{
        'first_name': 'Noor',
        'last_name': 'Ali',
        'company': '',
        'address_1': '12 Market Street',
        'address_2': '',
        'city': 'Dearborn',
        'state': 'MI',
        'postcode': '48126',
        'country': 'US',
      },
      'shipments': <Map<String, dynamic>>[
        {'id': 's1', 'carrier': 'dhl', 'label': 'DHL', 'number': 'JD0146', 'url': ''},
      ],
    };

Map<String, dynamic> profileJson() => <String, dynamic>{
      'id': 7,
      'email': 'noor@yazan.test',
      'first_name': 'Noor',
      'last_name': 'Ali',
      'display_name': 'noor',
      'phone': '+13135550100',
    };

/// In-memory [AccountApi]. Set [failure] to make every call throw it.
class FakeAccountApi implements AccountApi {
  FakeAccountApi({List<Map<String, dynamic>>? pages})
      : pages = pages ??
            <Map<String, dynamic>>[
              {
                'orders': [orderJson(1042, 'processing'), orderJson(1031, 'completed')],
                'total': 3,
                'pages': 2,
              },
              {
                'orders': [orderJson(1020, 'on-hold')],
                'total': 3,
                'pages': 2,
              },
            ];

  final List<Map<String, dynamic>> pages;
  Object? failure;
  final List<String> calls = [];

  void _maybeFail() {
    final f = failure;
    if (f != null) throw f;
  }

  @override
  Future<Profile> profile() async {
    calls.add('profile');
    _maybeFail();
    return Profile.fromJson(profileJson());
  }

  @override
  Future<OrderPage> orders({int page = 1}) async {
    calls.add('orders:$page');
    _maybeFail();
    if (page < 1 || page > pages.length) {
      return const OrderPage(orders: [], total: 0, pages: 0);
    }
    return OrderPage.fromJson(pages[page - 1]);
  }

  @override
  Future<OrderDetail> order(int id) async {
    calls.add('order:$id');
    _maybeFail();
    return OrderDetail.fromJson(orderDetailJson(id));
  }
}

/// In-memory [WishlistApi] holding "the server's" list. Set [failure] to make every call throw it;
/// set [gate] to hold `list()` until it completes.
class FakeWishlistApi implements WishlistApi {
  FakeWishlistApi([List<WishlistItem>? server]) : server = server ?? <WishlistItem>[];

  final List<WishlistItem> server;
  Object? failure;
  Future<void>? gate;
  final List<String> calls = [];

  void _maybeFail() {
    final f = failure;
    if (f != null) throw f;
  }

  @override
  Future<List<WishlistItem>> list() async {
    calls.add('list');
    final g = gate;
    if (g != null) await g;
    _maybeFail();
    return List<WishlistItem>.of(server);
  }

  @override
  Future<WishlistToggle> toggle(int productId) async {
    calls.add('toggle:$productId');
    _maybeFail();
    final index = server.indexWhere((i) => i.id == productId);
    final bool inList;
    if (index >= 0) {
      server.removeAt(index);
      inList = false;
    } else {
      server.insert(0, WishlistItem(id: productId, name: 'Piece $productId'));
      inList = true;
    }
    return WishlistToggle(inList: inList, count: server.length);
  }
}

WishlistItem ring(int id, String name, {String price = r'$120.00'}) =>
    WishlistItem(id: id, name: name, price: price);
