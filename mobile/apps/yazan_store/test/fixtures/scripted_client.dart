import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

/// A client that never touches the network: sign-in and sign-out are scripted.
class ScriptedClient extends YazanApiClient {
  ScriptedClient(TokenStore t)
      : super(
          baseUrl: 'https://example.test',
          scope: AppScope.store,
          deviceId: 'test-device',
          tokens: t,
        );

  ApiError? loginError;
  bool loggedOut = false;
  final List<String> logins = [];

  @override
  Future<LoginResult> login({
    required String login,
    required String password,
    String? deviceName,
    String platform = 'unknown',
  }) async {
    logins.add(login);
    final error = loginError;
    if (error != null) throw error;
    final session = Session.fromJson(
        {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900});
    await tokens.write(session);
    return LoginResult.session(session);
  }

  ApiError? socialError;

  /// `provider:idToken:nonce` for every social sign-in.
  final List<String> socialLogins = [];

  @override
  Future<LoginResult> socialLogin({
    required String provider,
    required String idToken,
    String? nonce,
    String? firstName,
    String? lastName,
    String? deviceName,
    String? platform,
  }) async {
    socialLogins.add('$provider:$idToken:${nonce ?? ''}');
    final error = socialError;
    if (error != null) throw error;
    final session = Session.fromJson(
        {'access_token': 'yzm_s', 'refresh_token': 'yzr_s', 'expires_in': 900});
    await tokens.write(session);
    return LoginResult.session(session);
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
    await tokens.clear();
  }
}
