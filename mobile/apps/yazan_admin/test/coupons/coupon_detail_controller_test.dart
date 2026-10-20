import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/coupons/coupon_detail_controller.dart';
import 'package:yazan_admin/src/more/staff_permissions.dart';
import 'package:yazan_domain/yazan_domain.dart';

import 'fakes.dart';

CouponDetailController _controller(
  FakeCouponServer server, {
  List<String> slugs = const ['coupons.view', 'coupons.edit'],
  List<String>? keys,
}) {
  var n = 0;
  return CouponDetailController(
    couponId: 21,
    load: server.loader,
    write: server.writer,
    permissions: StaffPermissions.of(slugs),
    newKey: () => keys == null ? 'key-${++n}' : keys[n++],
    clock: () => DateTime(2026, 10, 20, 15),
  );
}

void main() {
  test('load reads the coupon; expired follows the expiry date, the day itself counting as expired', () async {
    final server = FakeCouponServer();
    final c = _controller(server);
    await c.load();
    expect(c.code, 'SPRING20');
    expect(c.amount, '20.00');
    expect(c.isPercent, isTrue);
    expect(c.expired, isFalse);
    expect(c.usageLimit, 10);
    expect(c.canEdit, isTrue);

    server.expires = '2026-10-20';
    await c.load();
    expect(c.expired, isTrue);
    server.expires = '2026-10-21';
    await c.load();
    expect(c.expired, isFalse);
    server.expires = '';
    await c.load();
    expect(c.expired, isFalse);
  });

  test('a failed load is reported; a 403 is no access', () async {
    final server = FakeCouponServer()..loadError = Exception('offline');
    final c = _controller(server);
    await c.load();
    expect(c.failed, isTrue);
    expect(c.noAccess, isFalse);

    server.loadError = const ApiError(status: 403, code: 'rest_forbidden');
    await c.load();
    expect(c.noAccess, isTrue);
  });

  test('saveAmount sends the canonical amount with an idempotency key and shows the saved coupon', () async {
    final server = FakeCouponServer();
    final c = _controller(server);
    await c.load();
    expect(await c.saveAmount('٢٥'), CouponEditResult.done); // Arabic-Indic digits
    expect(server.writes.single.fields, {'amount': '25.00'});
    expect(server.writes.single.key, 'key-1');
    expect(server.writes.single.id, 21);
    expect(c.amount, '25.00');
  });

  test('a bad amount never reaches the network: zero, text, and a percentage over 100', () async {
    final server = FakeCouponServer();
    final c = _controller(server);
    await c.load();
    for (final bad in ['0', 'abc', '', '100.01', '-5']) {
      expect(await c.saveAmount(bad), CouponEditResult.invalid, reason: bad);
    }
    expect(await c.saveAmount('100'), CouponEditResult.done);
    expect(server.writes, hasLength(1));

    server.type = 'fixed_cart';
    await c.load();
    expect(await c.saveAmount('250'), CouponEditResult.done); // over 100 is fine for a fixed amount
  });

  test('saveExpiry validates the date, canonicalises it, and an empty date removes the expiry', () async {
    final server = FakeCouponServer();
    final c = _controller(server);
    await c.load();
    expect(await c.saveExpiry('2026-02-30'), CouponEditResult.invalid);
    expect(await c.saveExpiry('soon'), CouponEditResult.invalid);
    expect(await c.saveExpiry('2027-1-5'), CouponEditResult.done);
    expect(server.writes.single.fields, {'date_expires': '2027-01-05'});
    expect(await c.saveExpiry(''), CouponEditResult.done);
    expect(server.writes.last.fields, {'date_expires': ''});
    expect(c.expires, '');
  });

  test('expireNow sets today as the expiry and removeExpiry clears it', () async {
    final server = FakeCouponServer();
    final c = _controller(server);
    await c.load();
    expect(await c.expireNow(), CouponEditResult.done);
    expect(server.writes.last.fields, {'date_expires': '2026-10-20'});
    expect(c.expired, isTrue);
    expect(await c.removeExpiry(), CouponEditResult.done);
    expect(c.expired, isFalse);
  });

  test('offline keeps the attempt and a retry sends the same body under the same key', () async {
    final server = FakeCouponServer()..writeFailures.add(Exception('offline'));
    final c = _controller(server);
    await c.load();
    expect(await c.saveAmount('30'), CouponEditResult.offline);
    expect(c.canRetry, isTrue);
    expect(c.amount, '20.00'); // nothing changed on screen
    expect(await c.retry(), CouponEditResult.done);
    expect(server.writes.map((w) => w.key), ['key-1', 'key-1']);
    expect(server.writes.map((w) => w.fields), [
      {'amount': '30.00'},
      {'amount': '30.00'},
    ]);
    expect(c.canRetry, isFalse);
  });

  test('a different change starts a new attempt with a new key', () async {
    final server = FakeCouponServer()..writeFailures.add(Exception('offline'));
    final c = _controller(server);
    await c.load();
    await c.saveAmount('30');
    await c.saveAmount('35');
    expect(server.writes.map((w) => w.key), ['key-1', 'key-2']);
  });

  test('a 403 on a write is no access; a busy key can be retried; another error shows the server message', () async {
    final server = FakeCouponServer()
      ..writeFailures.addAll([
        const ApiError(status: 403, code: 'rest_forbidden'),
        const ApiError(status: 409, code: 'yazan_idempotency_busy'),
        const ApiError(status: 400, code: 'yazan_invalid', message: 'A percentage discount cannot exceed 100%.'),
      ]);
    final c = _controller(server);
    await c.load();
    expect(await c.saveAmount('30'), CouponEditResult.noAccess);
    expect(c.canRetry, isFalse);
    expect(await c.saveAmount('31'), CouponEditResult.busy);
    expect(c.canRetry, isTrue);
    expect(await c.saveAmount('32'), CouponEditResult.failed);
    expect(c.lastMessage, 'A percentage discount cannot exceed 100%.');
  });

  test('a 200 that did not apply the value is reported as not applied', () async {
    final server = FakeCouponServer()..ignoreWrites = true;
    final c = _controller(server);
    await c.load();
    expect(await c.saveAmount('30'), CouponEditResult.notApplied);
  });

  test('without coupons.edit nothing is sent', () async {
    final server = FakeCouponServer();
    final c = _controller(server, slugs: ['coupons.view']);
    await c.load();
    expect(c.canEdit, isFalse);
    expect(await c.saveAmount('30'), CouponEditResult.noAccess);
    expect(await c.expireNow(), CouponEditResult.noAccess);
    expect(server.writes, isEmpty);
  });

  test('parseDateInput accepts real dates only', () {
    expect(parseDateInput('2026-12-31'), '2026-12-31');
    expect(parseDateInput('٢٠٢٦-١٢-٣١'), '2026-12-31');
    expect(parseDateInput('2026-13-01'), isNull);
    expect(parseDateInput('2026-02-29'), isNull);
    expect(parseDateInput('2028-02-29'), '2028-02-29');
    expect(parseDateInput('31/12/2026'), isNull);
  });
}
