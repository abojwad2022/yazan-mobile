import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/l10n/app_localizations.dart';
import 'package:yazan_admin/src/dashboard/dashboard_repository.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

/// A localised app around [home], with no network anywhere.
Widget dashboardHost(Locale locale, Widget home) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: home),
    );

/// A tall screen so the whole dashboard is built (lists only build what is near the viewport).
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The moment the fake phone clock reads when an answer arrives.
final DateTime fixedNow = DateTime(2026, 10, 20, 14, 5);

/// `GET /yazan/v1/dashboard/bootstrap` for an account that may read everything. A section named in
/// [without] is left out, which is how the server answers an account that may not read it.
///
/// Sales: the current window's series sums to 450.00 over 3 orders, the older half of the double
/// window to 300.00 over 2 orders (so both changes are +50.0%); the last day is 150.50 / 1 order.
Map<String, dynamic> bootstrapAnswer({
  int days = 30,
  Set<String> without = const {},
  int processing = 4,
  int onHold = 2,
}) {
  final all = <String, dynamic>{
    'stats': {
      'products': {'publish': 40, 'draft': 1, 'pending': 0},
      'outofstock': 3,
      'categories': 4,
    },
    'sales': {
      'range': {'from': '2026-10-18', 'to': '2026-10-20'},
      'totals': {
        'net_revenue': '450.00',
        'gross_revenue': '460.00',
        'refunded': '10.00',
        'orders': 3,
        'refunded_orders': 0,
        'items_sold': 5,
        'average_order': '150.00',
      },
      'series': [
        {'date': '2026-10-18', 'total': 100.0, 'orders': 1},
        {'date': '2026-10-19', 'total': 199.5, 'orders': 1},
        {'date': '2026-10-20', 'total': 150.5, 'orders': 1},
      ],
      'top': <dynamic>[],
      'currency': {'symbol': r'$', 'decimals': 2},
    },
    'sales2x': {
      'range': {'from': '2026-10-15', 'to': '2026-10-20'},
      'totals': {'net_revenue': '750.00', 'orders': 5},
      'series': [
        {'date': '2026-10-15', 'total': 100.0, 'orders': 1},
        {'date': '2026-10-16', 'total': 0, 'orders': 0},
        {'date': '2026-10-17', 'total': 200.0, 'orders': 1},
        {'date': '2026-10-18', 'total': 100.0, 'orders': 1},
        {'date': '2026-10-19', 'total': 199.5, 'orders': 1},
        {'date': '2026-10-20', 'total': 150.5, 'orders': 1},
      ],
    },
    'stock': {'low_threshold': 2, 'out_of_stock_count': 3, 'low_stock_count': 5},
    'recentOrders': {
      'items': [
        {
          'id': 1005,
          'number': '1005',
          'status': 'processing',
          'status_label': 'Processing',
          'customer': 'Sara Ali',
          'email': 'sara@example.test',
          'items': 2,
          'total': '770.00',
          'total_html': r'$770.00',
          'date': '2026-10-20 09:30',
        },
        {
          'id': 1004,
          'number': '1004',
          'status': 'on-hold',
          'customer': '',
          'email': '',
          'total': '120.00',
          'total_html': r'$120.00',
          'date': '2026-10-19 18:00',
        },
      ],
      'total': 9,
      'total_pages': 2,
    },
    'recentProducts': {'items': <dynamic>[], 'total': 0},
    'onHold': {'items': <dynamic>[], 'total': onHold},
    'processing': {'items': <dynamic>[], 'total': processing},
  };
  return {
    'days': days,
    for (final e in all.entries)
      if (!without.contains(e.key)) e.key: e.value,
  };
}

/// What `GET /yazan/v1/orders/alerts` answers when [count] orders are newer than the baseline.
Map<String, dynamic> alertsAnswer({int count = 0, int latest = 1005}) => {
      'latest': latest,
      'count': count,
      'orders': [
        for (var i = 0; i < count && i < 5; i++)
          {
            'id': latest - i,
            'number': '${latest - i}',
            'total': r'$50.00',
            'status': 'processing',
            'customer': 'Customer $i',
          },
      ],
    };

/// A scripted stand-in for the dashboard routes. No network anywhere.
class FakeDashboardServer {
  /// The next bootstrap answer; replace it between refreshes.
  Map<String, dynamic> answer = bootstrapAnswer();

  /// When set, the next bootstrap call throws it (and stays set until cleared).
  Object? failure;

  /// What the alerts route answers; the `since` it is asked for is recorded in [alertSinces].
  Map<String, dynamic> alerts = alertsAnswer();
  Object? alertsFailure;

  final List<int> daysAsked = [];
  final List<int?> alertSinces = [];

  Future<Map<String, dynamic>> fetch(int days) async {
    daysAsked.add(days);
    if (failure != null) throw failure!;
    return answer;
  }

  Future<Map<String, dynamic>> fetchAlerts(int? since) async {
    alertSinces.add(since);
    if (alertsFailure != null) throw alertsFailure!;
    return alerts;
  }

  DashboardRepository repository({FeedStore? store, DateTime Function()? clock, int days = 30}) {
    return DashboardRepository(
      fetch: fetch,
      fetchAlerts: fetchAlerts,
      store: store,
      clock: clock ?? () => fixedNow,
      days: days,
    );
  }
}
