/// The two app scopes the server issues sessions for.
enum AppScope {
  store,
  admin;

  String get wire => name;
}

/// A device session as returned by `/auth/login`, `/auth/2fa` and `/auth/refresh`.
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory Session.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    final ttl = json['expires_in'];
    if (access is! String || refresh is! String || ttl is! int) {
      throw const FormatException('Malformed session payload');
    }
    return Session(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: (now ?? DateTime.now().toUtc()).add(Duration(seconds: ttl)),
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// True when the access token is expired or within [skew] of expiring.
  bool isExpired({DateTime? now, Duration skew = const Duration(seconds: 30)}) =>
      !(now ?? DateTime.now().toUtc()).add(skew).isBefore(expiresAt);
}

/// A second-step challenge: the password was right, a code is still needed.
class Challenge {
  const Challenge({required this.token, required this.methods});

  factory Challenge.fromJson(Map<String, dynamic> json) {
    final token = json['challenge'];
    if (token is! String) {
      throw const FormatException('Malformed challenge payload');
    }
    return Challenge(
      token: token,
      methods: [for (final m in (json['methods'] as List? ?? const [])) '$m'],
    );
  }

  final String token;
  final List<String> methods;
}
