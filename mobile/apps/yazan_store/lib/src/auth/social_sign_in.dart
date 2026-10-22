import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

/// What a provider SDK handed back: the OpenID Connect ID token the server checks
/// (`POST /auth/social`), plus what that provider shares only once (Apple's name).
class SocialToken {
  const SocialToken({required this.idToken, this.nonce, this.firstName, this.lastName});

  final String idToken;

  /// The raw nonce given to the SDK, when one was used.
  final String? nonce;
  final String? firstName;
  final String? lastName;
}

/// The provider SDK failed in a way that is not "the customer closed it". [code] is a short
/// technical name for the small print under the message, e.g. `google_clientConfigurationError`.
class SocialSignInException implements Exception {
  const SocialSignInException(this.code);

  final String code;

  @override
  String toString() => 'SocialSignInException($code)';
}

/// One "Continue with ..." button: asks the phone's provider SDK for an ID token.
///
/// The app uses [GoogleTokenSource]; tests use fakes, so no plugin is touched.
abstract class SocialTokenSource {
  /// The `provider` value for `/auth/social`: `google` or `apple`.
  String get provider;

  /// The token, or null when the customer closed the provider's sheet (not an error). Throws
  /// [SocialSignInException] for anything else.
  Future<SocialToken?> obtain();

  /// Forgets the provider account on this phone (sign-out, account deleted). Never throws.
  Future<void> signOut();
}

/// Google through the `google_sign_in` 7.x plugin (Android Credential Manager).
///
/// [serverClientId] is the Web client id: Google issues the ID token for it, and the server accepts
/// tokens whose audience is in `YAZAN_MOBILE_GOOGLE_CLIENT_IDS`. Nothing touches the plugin until the
/// button is tapped.
class GoogleTokenSource implements SocialTokenSource {
  GoogleTokenSource({required this.serverClientId, this.clientId});

  final String serverClientId;

  /// The iOS client id (unused on Android).
  final String? clientId;

  Future<void>? _ready;

  @override
  String get provider => 'google';

  /// `initialize` may run once per app; a failed one is forgotten so a later tap tries again.
  Future<void> _initialize() async {
    final id = clientId;
    final pending = _ready ??= GoogleSignIn.instance.initialize(
      serverClientId: serverClientId,
      clientId: id == null || id.isEmpty ? null : id,
    );
    try {
      await pending;
    } catch (_) {
      if (identical(_ready, pending)) _ready = null;
      rethrow;
    }
  }

  @override
  Future<SocialToken?> obtain() async {
    try {
      await _initialize();
      final account = await GoogleSignIn.instance.authenticate();
      // Synchronous in 7.x; Future.value keeps this right if it ever returns a future.
      final auth = await Future.value(account.authentication);
      final token = auth.idToken;
      if (token == null || token.isEmpty) {
        throw const SocialSignInException('google_no_id_token');
      }
      return SocialToken(idToken: token);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw SocialSignInException('google_${e.code.name}');
    }
  }

  @override
  Future<void> signOut() async {
    if (_ready == null) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing to undo on the phone.
    }
  }
}

/// Whether this build may show "Continue with Google" on [platform].
///
/// * Android: when the Web client id was given at build time.
/// * iOS: only with the iOS client id too, and only beside Sign in with Apple (App Store rule 4.8:
///   an app that offers Google sign-in must offer Apple as well).
/// * Anything else (web, desktop): never.
bool googleSignInAllowed({
  required TargetPlatform platform,
  required String serverClientId,
  String iosClientId = '',
  bool appleShown = false,
}) {
  if (kIsWeb || serverClientId.isEmpty) return false;
  return switch (platform) {
    TargetPlatform.android => true,
    TargetPlatform.iOS => appleShown && iosClientId.isNotEmpty,
    _ => false,
  };
}

/// Whether this build may show "Continue with Apple": iOS only, with `YAZAN_APPLE_SIGNIN=1` and a
/// provider to ask.
bool appleSignInAllowed({
  required TargetPlatform platform,
  required bool enabled,
  required bool hasSource,
}) =>
    !kIsWeb && enabled && hasSource && platform == TargetPlatform.iOS;

/// The Google button of this build: a [GoogleTokenSource] when [googleSignInAllowed] says so for
/// the phone the app runs on and the ids given at build time ([AppConfig]), else null (no button).
/// [appleShown]: whether "Continue with Apple" is on screen too (needed on iOS).
SocialTokenSource? defaultGoogleSource({bool appleShown = false, TargetPlatform? platform}) {
  const serverClientId = AppConfig.googleServerClientId;
  const iosClientId = AppConfig.googleIosClientId;
  final allowed = googleSignInAllowed(
    platform: platform ?? defaultTargetPlatform,
    serverClientId: serverClientId,
    iosClientId: iosClientId,
    appleShown: appleShown,
  );
  if (!allowed) return null;
  return GoogleTokenSource(serverClientId: serverClientId, clientId: iosClientId);
}
