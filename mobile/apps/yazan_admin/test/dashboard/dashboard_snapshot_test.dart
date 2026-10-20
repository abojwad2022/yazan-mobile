import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/dashboard/dashboard_format.dart';
import 'package:yazan_admin/src/dashboard/dashboard_snapshot.dart';

import 'fakes.dart';

DashboardSnapshot _parse(Map<String, dynamic> json) =>
    DashboardSnapshot.fromBootstrap(json, fetchedAt: fixedNow);

void main() {
  group('reading the bootstrap answer', () {
    test('an account that may read everything gets every figure', () {
      final s = _parse(bootstrapAnswer());
      expect(s.days, 30);
      expect(s.processing, 4);
      expect(s.onHold, 2);
      expect(s.outOfStock, 3);
      expect(s.lowStock, 5);
      expect(s.lowThreshold, 2);
      expect(s.recentOrders, hasLength(2));
      expect(s.isEmpty, isFalse);
      expect(s.hasOrders, isTrue);
    });

    test('sales: totals stay the server strings, today is the last day of the window', () {
      final sales = _parse(bootstrapAnswer()).sales!;
      expect(sales.netRevenue, '450.00');
      expect(sales.orders, 3);
      expect(sales.itemsSold, 5);
      expect(sales.averageOrder, '150.00');
      expect(sales.refunded, '10.00');
      expect(sales.symbol, r'$');
      expect(sales.decimals, 2);
      expect(sales.rangeTo, '2026-10-20');
      expect(sales.todayRevenue, 150.5);
      expect(sales.todayOrders, 1);
    });

    test('the older half of the double window is the previous period', () {
      final sales = _parse(bootstrapAnswer()).sales!;
      expect(sales.previousRevenue, 300.0);
      expect(sales.previousOrders, 2);
      expect(sales.revenueDelta, closeTo(50.0, 1e-9));
      expect(sales.ordersDelta, closeTo(50.0, 1e-9));
    });

    test('without the longer report there is nothing to compare with', () {
      final sales = _parse(bootstrapAnswer(without: {'sales2x'})).sales!;
      expect(sales.previousRevenue, isNull);
      expect(sales.revenueDelta, isNull);
      expect(sales.ordersDelta, isNull);
    });

    test('a previous period with no sales has no percentage (no divide by zero)', () {
      final answer = bootstrapAnswer();
      answer['sales2x'] = {
        'series': [
          {'date': '2026-10-15', 'total': 0, 'orders': 0},
          {'date': '2026-10-16', 'total': 0.0, 'orders': 0},
          {'date': '2026-10-17', 'total': 0, 'orders': 0},
          ...(answer['sales']['series'] as List),
        ],
      };
      final sales = _parse(answer).sales!;
      expect(sales.previousRevenue, 0);
      expect(sales.revenueDelta, isNull);
    });

    test('a section the server left out is simply absent', () {
      // A warehouse role: stock yes, sales and orders no.
      final s = _parse(bootstrapAnswer(without: {'sales', 'sales2x', 'recentOrders', 'onHold', 'processing'}));
      expect(s.sales, isNull);
      expect(s.processing, isNull);
      expect(s.onHold, isNull);
      expect(s.recentOrders, isNull);
      expect(s.hasOrders, isFalse);
      expect(s.outOfStock, 3);
      expect(s.lowStock, 5);
      expect(s.isEmpty, isFalse);
    });

    test('out of stock falls back to the product counters when stock is not readable', () {
      final s = _parse(bootstrapAnswer(without: {'stock'}));
      expect(s.outOfStock, 3);
      expect(s.lowStock, isNull);
      expect(s.lowThreshold, isNull);
    });

    test('an answer with only the day count is empty (nothing the account may see)', () {
      final s = _parse({'days': 30});
      expect(s.isEmpty, isTrue);
      expect(_parse(const <String, dynamic>{}).isEmpty, isTrue);
    });

    test('odd fields never throw', () {
      final s = _parse({
        'days': 'x',
        'sales': {'totals': 'nope', 'series': 5, 'currency': []},
        'stock': {'low_stock_count': 'many'},
        'processing': {'total': '7'},
        'onHold': 5,
        'recentOrders': {'items': [1, null, {'id': 'z'}, {'id': 9}]},
      });
      expect(s.days, 30);
      expect(s.sales!.orders, 0);
      expect(s.sales!.todayRevenue, isNull);
      expect(s.lowStock, isNull);
      expect(s.processing, 7);
      expect(s.onHold, isNull);
      expect(s.recentOrders!.map((o) => o.id), [9]);
    });

    test('recent orders keep no email', () {
      final s = _parse(bootstrapAnswer());
      expect(jsonEncode(s.toJson()), isNot(contains('example.test')));
      expect(jsonEncode(s.toJson()), isNot(contains('"email"')));
      final first = s.recentOrders!.first;
      expect(first.number, '1005');
      expect(first.customer, 'Sara Ali');
      expect(first.total, r'$770.00');
    });
  });

  group('the copy kept on the phone', () {
    test('survives a JSON round trip, alerts and baseline included', () {
      final alert = NewOrdersAlert.fromServer(alertsAnswer(count: 2, latest: 1005))!;
      final s = DashboardSnapshot.fromBootstrap(
        bootstrapAnswer(),
        fetchedAt: fixedNow,
        alerts: alert,
        alertBaseline: 1003,
      );
      final back = DashboardSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(s.toJson())) as Map),
      );
      expect(back.toJson(), s.toJson());
      expect(back.fetchedAt.toUtc(), fixedNow.toUtc());
      expect(back.alertBaseline, 1003);
      expect(back.alerts!.count, 2);
      expect(back.alerts!.latest, 1005);
      expect(back.sales!.revenueDelta, closeTo(50.0, 1e-9));
    });

    test('an unreadable copy still builds', () {
      final s = DashboardSnapshot.fromJson({'sales': 3, 'recent_orders': 'x', 'fetched_at': 'never'});
      expect(s.isEmpty, isTrue);
      expect(s.days, 30);
    });

    test('no new orders is no alert', () {
      expect(NewOrdersAlert.fromServer(alertsAnswer()), isNull);
    });
  });

  group('wording of numbers', () {
    test('amounts are grouped and carry the store symbol', () {
      expect(formatAmount('450.00', r'$'), r'450.00 $');
      expect(formatAmount('12345678.5', 'SAR'), '12,345,678.5 SAR');
      expect(formatAmount('-1234.00', ''), '-1,234.00');
      expect(formatAmount('n/a', r'$'), r'n/a $');
      expect(formatSum(150.5, 2, r'$'), r'150.50 $');
    });

    test('changes carry a sign', () {
      expect(formatDelta(50), '+50.0%');
      expect(formatDelta(-3.26), '-3.3%');
      expect(formatDelta(0.01), '0.0%');
    });

    test('the as-of time is local, to the minute', () {
      expect(formatAsOf(fixedNow), contains('2026-10-20 14:05'));
    });
  });
}
