import 'package:yazan_api_client/yazan_api_client.dart';

import 'rewards_models.dart';

/// The customer's rewards on the server (`/yazan-rewards/v1`), read only.
///
/// Only the routes a store session may reach are used (`me`, `referral`). Methods throw `ApiError`
/// for a server answer and any other exception for a network problem.
abstract class RewardsApi {
  Future<RewardsSummary> summary();

  Future<ReferralInfo> referral();
}

class ClientRewardsApi implements RewardsApi {
  ClientRewardsApi(this._client);

  final YazanApiClient _client;

  static const _base = '/yazan-rewards/v1';

  @override
  Future<RewardsSummary> summary() async =>
      RewardsSummary.fromJson(await _client.getJson('$_base/me'));

  @override
  Future<ReferralInfo> referral() async =>
      ReferralInfo.fromJson(await _client.getJson('$_base/referral'));
}
