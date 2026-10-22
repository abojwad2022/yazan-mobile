import 'package:test/test.dart';
import 'package:yazan_domain/yazan_domain.dart';

void main() {
  group('Money', () {
    test('parses decimals without floating point', () {
      expect(Money.parse('129.50').minor, 12950);
      expect(Money.parse('1,299').minor, 129900);
      expect(Money.parse('0.5').minor, 50);
      expect(Money.parse('-3.07').minor, -307);
    });
    test('rejects garbage', () {
      expect(() => Money.parse('12.345'), throwsFormatException);
      expect(() => Money.parse('abc'), throwsFormatException);
    });
    test('arithmetic and formatting', () {
      expect((Money.parse('10.10') + Money.parse('0.95')).toDecimalString(), '11.05');
      expect(Money.parse('2.50').times(3).toDecimalString(), '7.50');
      expect(const Money(-5).toDecimalString(), '-0.05');
    });
    test('refuses to mix currencies', () {
      expect(() => const Money(1, 'USD') + const Money(1, 'EUR'), throwsArgumentError);
    });
  });

  group('Session', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    final s = Session.fromJson(
      {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900},
      now: now,
    );
    test('computes expiry', () {
      expect(s.expiresAt, now.add(const Duration(seconds: 900)));
    });
    test('is expired inside the skew window', () {
      expect(s.isExpired(now: now), isFalse);
      expect(s.isExpired(now: now.add(const Duration(seconds: 871))), isTrue);
      expect(s.isExpired(now: now.add(const Duration(seconds: 901))), isTrue);
    });
    test('a payload without user has no user (old stored sessions still load)', () {
      expect(s.user, isNull);
      expect(s.userId, isNull);
    });
    test('reads the user from the login payload', () {
      final withUser = Session.fromJson({
        'access_token': 'a',
        'refresh_token': 'r',
        'expires_in': 900,
        'user': {'id': 12, 'name': 'Yazan', 'email': 'y@example.test', 'scope': 'store'},
      });
      expect(withUser.userId, 12);
      expect(withUser.user!.name, 'Yazan');
      expect(withUser.user!.email, 'y@example.test');
      expect(withUser.user!.scope, 'store');
      expect(SessionUser.tryFromJson(withUser.user!.toJson())!.id, 12);
    });
    test('tolerates a string id and ignores a user without an id', () {
      expect(SessionUser.tryFromJson({'id': '7'})!.id, 7);
      expect(SessionUser.tryFromJson({'name': 'x'}), isNull);
      expect(SessionUser.tryFromJson('nope'), isNull);
    });
    test('copyWith keeps the user across a token refresh', () {
      final a = Session(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.utc(2026),
        user: const SessionUser(id: 3),
      );
      final b = a.copyWith(accessToken: 'a2');
      expect(b.accessToken, 'a2');
      expect(b.userId, 3);
    });
    test('rejects a malformed payload', () {
      expect(() => Session.fromJson({'access_token': 1}), throwsFormatException);
    });
  });

  group('DeltaPage', () {
    test('splits upserts from tombstones', () {
      final p = DeltaPage.fromJson({
        'items': [
          {'id': 1, 'name': 'Ring'},
          {'id': 2, 'deleted': true},
        ],
        'cursor': 'abc',
        'has_more': true,
        'initial': false,
      });
      expect(p.upserts.single['id'], 1);
      expect(p.deletedIds, [2]);
      expect(p.hasMore, isTrue);
    });
  });

  group('ApiError', () {
    test('maps codes to actions', () {
      ApiError e(String c) => ApiError(status: 400, code: c);
      expect(e('yazan_mobile_bad_token').action, ErrorAction.refreshThenRetry);
      expect(e('yazan_mobile_bad_refresh').action, ErrorAction.signIn);
      expect(e('yazan_precondition_failed').action, ErrorAction.showConflict);
      expect(e('yazan_rate_limited').action, ErrorAction.backOff);
      expect(e('yazan_mobile_slow_down').action, ErrorAction.backOff);
      expect(e('nope').action, ErrorAction.other);
    });
    test('reads retry_after and current', () {
      final e = ApiError.fromJson(412, {
        'code': 'yazan_precondition_failed',
        'message': 'x',
        'data': {'status': 412, 'current': 'abc123', 'retry_after': 3},
      });
      expect(e.current, 'abc123');
      expect(e.retryAfter, 3);
    });
  });
}
