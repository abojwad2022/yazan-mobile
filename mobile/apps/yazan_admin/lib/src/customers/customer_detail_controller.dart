import 'package:flutter/foundation.dart';
import 'package:yazan_domain/yazan_domain.dart';

import 'customer_api.dart';

/// The last order a customer placed, as `GET /yazan/v1/customers/{id}` reports it.
class CustomerLastOrder {
  const CustomerLastOrder({
    required this.id,
    required this.number,
    required this.date,
    required this.status,
    required this.total,
  });

  final int id;
  final String number;

  /// `YYYY-MM-DD`, or empty.
  final String date;

  /// WooCommerce status slug without the `wc-` prefix.
  final String status;

  /// A plain decimal string, or empty.
  final String total;
}

/// The loaded customer record. Parsing never throws; fields the server leaves out (it strips the
/// billing block without `customers.view_pii`, and the lifetime spend without `reports.view`) are
/// empty or null.
class CustomerDetail {
  const CustomerDetail({
    required this.name,
    required this.email,
    required this.phone,
    required this.registered,
    required this.orderCount,
    required this.totalSpent,
    required this.currencySymbol,
    required this.addressLines,
    required this.hasBilling,
    required this.lastOrder,
  });

  factory CustomerDetail.fromJson(Map<String, dynamic> json) {
    final billing = json['billing'];
    final billingMap = billing is Map ? billing : null;
    String b(String key) => billingMap == null ? '' : _str(billingMap[key]).trim();

    final person = '${b('first_name')} ${b('last_name')}'.trim();
    final cityLine = [b('postcode'), b('city')].where((s) => s.isNotEmpty).join(' ');
    final lines = <String>[
      person,
      b('company'),
      b('address_1'),
      b('address_2'),
      cityLine,
      b('state'),
      b('country'),
    ].where((s) => s.isNotEmpty).toList();

    final email = _str(json['email']).trim();
    final last = json['last_order'];
    return CustomerDetail(
      name: _str(json['name']).trim(),
      email: email.isEmpty ? b('email') : email,
      phone: b('phone'),
      registered: _str(json['registered']).trim(),
      orderCount: _int(json['order_count']),
      totalSpent: _str(json['total_spent']).trim(),
      currencySymbol: _str(json['currency_symbol']).trim(),
      addressLines: lines,
      hasBilling: billingMap != null,
      lastOrder: last is Map
          ? CustomerLastOrder(
              id: _int(last['id']) ?? 0,
              number: _str(last['number']).trim(),
              date: _str(last['date']).trim(),
              status: _str(last['status']).trim(),
              total: _str(last['total']).trim(),
            )
          : null,
    );
  }

  final String name;
  final String email;
  final String phone;
  final String registered;
  final int? orderCount;
  final String totalSpent;
  final String currencySymbol;

  /// The billing address as display lines; empty when none is on file or it is withheld.
  final List<String> addressLines;

  /// Whether the server sent a billing block at all.
  final bool hasBilling;
  final CustomerLastOrder? lastOrder;

  static String _str(Object? v) => v == null ? '' : '$v';

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(_str(v));
  }
}

/// State of one customer screen. The record is read-only and online-only: it is fetched when the
/// screen opens and never stored on the phone, so only the list row (already in the in-memory feed
/// cache) shows without a connection.
class CustomerDetailController extends ChangeNotifier {
  CustomerDetailController({required this.customerId, required CustomerLoader load}) : _load = load;

  final int customerId;
  final CustomerLoader _load;

  CustomerDetail? _detail;
  bool _loading = true;
  bool _failed = false;
  bool _noAccess = false;
  bool _disposed = false;

  CustomerDetail? get detail => _detail;
  bool get loading => _loading;
  bool get failed => _failed;

  /// The server refused this customer to the account (403).
  bool get noAccess => _noAccess;

  Future<void> load() async {
    _loading = true;
    _failed = false;
    _notify();
    try {
      _detail = CustomerDetail.fromJson(await _load(customerId));
      _noAccess = false;
    } on ApiError catch (e) {
      if (e.action == ErrorAction.hideFeature) {
        _noAccess = true;
      } else {
        _failed = true;
      }
    } on Exception {
      _failed = true;
    } on TypeError {
      // A malformed answer is shown as a failed load, not a crash.
      _failed = true;
    }
    _loading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
