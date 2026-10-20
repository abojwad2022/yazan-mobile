import 'package:flutter/widgets.dart';
import 'package:yazan_store/src/rewards/rewards_api.dart';
import 'package:yazan_store/src/rewards/rewards_models.dart';
import 'package:yazan_store/src/verify/serial_scanner.dart';
import 'package:yazan_store/src/verify/verify_api.dart';
import 'package:yazan_store/src/verify/verify_models.dart';

import 'scripted_client.dart';

/// `GET /yazan-mobile/v1/verify/{serial}` for a ring with a stone, silver purity and a collection
/// and no recorded origin or carat.
Map<String, dynamic> certificateJson({
  String serial = 'YZ-925-2026-00012',
  String origin = '',
  String purity = '925',
}) =>
    <String, dynamic>{
      'serial': serial,
      'product_id': 77,
      'name': 'Carnelian Signet',
      'permalink': 'https://yazan.test/product/carnelian-signet/',
      'image': '',
      'stone': 'Aqeeq',
      'color': 'Carnelian red',
      'metal': 'Sterling silver',
      'purity': purity,
      'origin': origin,
      'shape': 'Oval',
      'carat': '',
      'wearer': '',
      'collection': 'Heritage',
      'one_of_one': true,
      'year': '2026',
    };

/// In-memory [VerifyApi]. Set [failure] to make every lookup throw it.
class FakeVerifyApi implements VerifyApi {
  FakeVerifyApi({Map<String, dynamic>? answer}) : answer = answer ?? certificateJson();

  final Map<String, dynamic> answer;
  Object? failure;
  final List<String> calls = [];

  @override
  Future<RingCertificate> lookup(String serial) async {
    calls.add(serial);
    final f = failure;
    if (f != null) throw f;
    return RingCertificate.fromJson(answer);
  }
}

/// `GET /yazan-rewards/v1/me`.
Map<String, dynamic> rewardsMeJson({
  int balance = 1250,
  String tier = 'Silver',
  bool next = true,
}) =>
    <String, dynamic>{
      'user_id': 7,
      'points': {
        'balance': balance,
        'label': {'singular': 'Point', 'plural': 'Points'},
      },
      'wallet': {'enabled': false, 'balance': '0', 'balance_html': ''},
      'tier': {'slug': tier.toLowerCase(), 'name': tier},
      'level': {
        'lifetime': 1250,
        'current': {'slug': 'silver', 'name': 'Silver', 'threshold_points': 1000},
        'next': next
            ? {'name': 'Gold', 'threshold': 1500, 'remaining': 250, 'progress': 0.5}
            : null,
      },
      'ranking': {'rank': 4, 'total': 90, 'lifetime': 1250},
    };

/// `GET /yazan-rewards/v1/referral`.
Map<String, dynamic> referralJson() => <String, dynamic>{
      'code': 'NOOR7K',
      'link': 'https://yazan.test/?ref=NOOR7K',
      'stats': {'signups': 2, 'conversions': 1, 'points_earned': 100},
    };

/// In-memory [RewardsApi]. Set [summaryFailure] / [referralFailure] to make that call throw.
class FakeRewardsApi implements RewardsApi {
  FakeRewardsApi({Map<String, dynamic>? me, Map<String, dynamic>? referral})
      : me = me ?? rewardsMeJson(),
        referralAnswer = referral ?? referralJson();

  final Map<String, dynamic> me;
  final Map<String, dynamic> referralAnswer;
  Object? summaryFailure;
  Object? referralFailure;
  final List<String> calls = [];

  @override
  Future<RewardsSummary> summary() async {
    calls.add('me');
    final f = summaryFailure;
    if (f != null) throw f;
    return RewardsSummary.fromJson(me);
  }

  @override
  Future<ReferralInfo> referral() async {
    calls.add('referral');
    final f = referralFailure;
    if (f != null) throw f;
    return ReferralInfo.fromJson(referralAnswer);
  }
}

/// A scanner with no camera: the test pushes codes in with [emit] and camera trouble with [fail].
class FakeSerialScanner implements SerialScanner {
  ValueChanged<String>? _onCode;
  ValueChanged<Object>? _onError;
  int previews = 0;

  @override
  Widget buildPreview(
    BuildContext context, {
    required ValueChanged<String> onCode,
    required ValueChanged<Object> onError,
  }) {
    previews++;
    _onCode = onCode;
    _onError = onError;
    return const SizedBox(key: Key('fake-camera-preview'));
  }

  void emit(String raw) => _onCode?.call(raw);

  void fail() => _onError?.call(StateError('permission denied'));
}

/// A client whose `getJson` is scripted: it records the path and answers (or throws) what the test says.
class GetJsonClient extends ScriptedClient {
  GetJsonClient(super.t, this.handler);

  final Map<String, dynamic> Function(String path) handler;
  final List<({String path, bool optionalAuth})> gets = [];

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
    bool optionalAuth = false,
  }) async {
    gets.add((path: path, optionalAuth: optionalAuth));
    return handler(path);
  }
}
