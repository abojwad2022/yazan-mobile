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

  /// Thrown by [login] instead of an answer (a network failure, a timeout).
  Object? loginException;
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
    final failure = loginException;
    if (failure != null) throw failure;
    final error = loginError;
    if (error != null) throw error;
    final session = Session.fromJson(
        {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900});
    await tokens.write(session);
    return LoginResult.session(session);
  }

  ApiError? exchangeError;

  /// `code:codeVerifier:platform` for every website sign-in code swapped for a session.
  final List<String> exchanges = [];

  @override
  Future<LoginResult> exchangeAppCode({
    required String code,
    required String codeVerifier,
    String? deviceName,
    String? platform,
  }) async {
    exchanges.add('$code:$codeVerifier:${platform ?? ''}');
    final error = exchangeError;
    if (error != null) throw error;
    final session = Session.fromJson(
        {'access_token': 'yzm_w', 'refresh_token': 'yzr_w', 'expires_in': 900});
    await tokens.write(session);
    return LoginResult.session(session);
  }

  /// Thrown by [logout] before it clears anything (a sign-out the client could not finish).
  Object? logoutError;

  /// How many times the session was ended through [clearSession].
  int clearedSessions = 0;

  @override
  Future<void> logout() async {
    loggedOut = true;
    final error = logoutError;
    if (error != null) throw error;
    await tokens.clear();
  }

  @override
  Future<void> clearSession() async {
    clearedSessions++;
    await super.clearSession();
  }
}
