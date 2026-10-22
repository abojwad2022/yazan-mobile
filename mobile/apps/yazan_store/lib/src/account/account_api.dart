import 'package:yazan_api_client/yazan_api_client.dart';

import 'account_models.dart';

/// The customer's own account on the server (`yazan-mobile/v1/me/...`), plus deleting it.
///
/// Methods throw [ApiError] for a server answer and any other exception for a network problem;
/// screens turn both into a `Failure`.
abstract class AccountApi {
  Future<Profile> profile();

  /// Own orders, newest first, 10 per page (page numbers start at 1).
  Future<OrderPage> orders({int page = 1});

  Future<OrderDetail> order(int id);

  /// Deletes the account for good after the customer confirmed with [password] (empty: an account
  /// with Google / Apple, signed in within the last 5 minutes). On success the phone's session is
  /// already ended; the caller wipes the rest of the local data.
  Future<void> deleteAccount({required String password});
}

class ClientAccountApi implements AccountApi {
  ClientAccountApi(this._client);

  final YazanApiClient _client;

  static const _base = '/yazan-mobile/v1/me';

  @override
  Future<Profile> profile() async => Profile.fromJson(await _client.getJson('$_base/profile'));

  @override
  Future<OrderPage> orders({int page = 1}) async =>
      OrderPage.fromJson(await _client.getJson('$_base/orders', query: {'page': page}));

  @override
  Future<OrderDetail> order(int id) async =>
      OrderDetail.fromJson(await _client.getJson('$_base/orders/$id'));

  @override
  Future<void> deleteAccount({required String password}) =>
      _client.deleteAccount(password: password);
}
