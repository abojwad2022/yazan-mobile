/// The two app scopes the server issues sessions for.
enum AppScope {
  store,
  admin;

  String get wire => name;
}

/// The signed-in person, as carried in the `user` object of the login response.
class SessionUser {
  const SessionUser({required this.id, this.name = '', this.email = '', this.scope = ''});

  /// Null when the payload has no usable numeric id.
  static SessionUser? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final intId = id is int ? id : (id is String ? int.tryParse(id) : null);
    if (intId == null) return null;
    String str(Object? v) => v is String ? v : '';
    return SessionUser(
      id: intId,
      name: str(json['name']),
      email: str(json['email']),
      scope: str(json['scope']),
    );
  }

  final int id;
  final String name;
  final String email;
  final String scope;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email, 'scope': scope};
}

/// A device session as returned by `/auth/login`, `/auth/2fa` and `/auth/refresh`.
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.user,
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
      user: SessionUser.tryFromJson(json['user']),
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// Present when the response carried `user` (login / 2FA); null for refreshed or older stored
  /// sessions. Token stores that persist it should write [SessionUser.toJson] and read it back with
  /// [SessionUser.tryFromJson]; a stored session without it still loads (user is null).
  final SessionUser? user;

  /// The signed-in user id, or null when unknown.
  int? get userId => user?.id;

  /// A copy with new tokens/expiry that keeps [user] (refresh responses carry none).
  Session copyWith({String? accessToken, String? refreshToken, DateTime? expiresAt, SessionUser? user}) =>
      Session(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAt: expiresAt ?? this.expiresAt,
        user: user ?? this.user,
      );

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
