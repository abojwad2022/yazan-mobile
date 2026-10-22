import 'package:flutter/foundation.dart';

/// "Continue with Google" / "Continue with Apple" for the Store app.
///
/// The phone's provider SDK produces an OpenID Connect ID token; the app posts it to
/// `POST /yazan-mobile/v1/auth/social` (`YazanApiClient.socialLogin`) and gets the same session as
/// the password sign-in. The buttons are OFF unless the build turns them on:
///
///   --dart-define=`YAZAN_GOOGLE_SERVER_CLIENT_ID=WEB_SERVER_OAUTH_CLIENT_ID`   (Google)
///   --dart-define=YAZAN_APPLE_SIGNIN=1                                         (Apple, iOS only)
///
/// With neither flag (the CI default) the sign-in screen is exactly the password form.
///
/// NATIVE PROVIDER WORK STILL TO DO (needs the owner's accounts and IDs, so not added yet):
///
/// Google (Android + iOS):
///  * Add `google_sign_in` to pubspec.yaml and implement [SocialTokenSource.google] with it,
///    passing `serverClientId: config.googleServerClientId` so the ID token's `aud` is the server
///    client (the server also accepts the app's own client id as `azp`).
///  * Server: put the Android and iOS OAuth client ids in `YAZAN_MOBILE_GOOGLE_CLIENT_IDS`
///    (wp-config, comma list) and configure the website's Google sign-in (its client id is the
///    server client id above). Until then the route answers 404.
///  * Android: create an "Android" OAuth client in Google Cloud for package `com.yazanus.store`
///    (the applicationId mobile/tools/scaffold_platforms.sh sets) with the SHA-1 of the upload key
///    AND of the Play app-signing key (`keytool -list -v -keystore <keystore>` for the upload key;
///    Play Console > App integrity for the signing key).
///  * iOS: create an "iOS" OAuth client; in ios/Runner/Info.plist add `GIDClientID` (the iOS client
///    id) and, under `CFBundleURLTypes`, a URL scheme equal to the REVERSED iOS client id
///    (`com.googleusercontent.apps.<...>`). Optionally `GIDServerClientID` = the server client id.
///    ios/ and android/ are generated in CI, so these edits belong in
///    mobile/tools/scaffold_platforms.sh (the Store-only block), like the camera permission.
///
/// Apple (iOS only):
///  * Needs an Apple Developer Program account. Enable the "Sign in with Apple" capability on the
///    App ID and in Xcode (Runner > Signing & Capabilities), which adds
///    `com.apple.developer.applesignin` = `Default` to Runner.entitlements (also via the scaffold
///    script, plus `CODE_SIGN_ENTITLEMENTS` in the Runner target, since ios/ is generated).
///  * Add `sign_in_with_apple` (and `crypto` for sha256) to pubspec.yaml; implement
///    [SocialTokenSource.apple] by generating a random raw nonce, passing sha256(raw) to
///    `getAppleIDCredential(scopes: [email, fullName], nonce: ...)`, and returning the
///    `identityToken` with the RAW nonce plus `givenName`/`familyName` (Apple shares the name with
///    the app only on the first sign-in, never in the token).
///  * Server: put the app's bundle id (`com.yazanus.store`, the native token's `aud`) in
///    `YAZAN_MOBILE_APPLE_CLIENT_IDS` and configure the website's Apple sign-in.
///  * App Store rule 4.8: once Google sign-in ships on iOS, Sign in with Apple must be offered too.
class SocialSignInConfig {
  const SocialSignInConfig({this.googleServerClientId = '', this.apple = false});

  /// Both buttons hidden.
  static const none = SocialSignInConfig();

  /// The build's flags. Apple is iOS only, whatever the flag says.
  factory SocialSignInConfig.fromEnvironment({TargetPlatform? platform}) {
    const google = String.fromEnvironment('YAZAN_GOOGLE_SERVER_CLIENT_ID');
    const appleFlag = String.fromEnvironment('YAZAN_APPLE_SIGNIN');
    final target = platform ?? defaultTargetPlatform;
    return SocialSignInConfig(
      googleServerClientId: google.trim(),
      apple: !kIsWeb && appleFlag == '1' && target == TargetPlatform.iOS,
    );
  }

  /// The Google OAuth client the ID token must be addressed to; empty = Google off.
  final String googleServerClientId;

  /// Whether "Continue with Apple" is shown.
  final bool apple;

  bool get google => googleServerClientId.isNotEmpty;

  bool get any => google || apple;
}

/// What a provider SDK hands back.
class SocialToken {
  const SocialToken({required this.idToken, this.nonce, this.firstName, this.lastName});

  /// The OpenID Connect ID token (a JWT).
  final String idToken;

  /// The RAW nonce given to the SDK, if one was used (the server checks it, or its sha256).
  final String? nonce;

  /// Apple only, first sign-in only.
  final String? firstName;
  final String? lastName;
}

/// Gets an ID token from the phone's provider SDK. Returns null when the customer cancelled (or the
/// provider is not wired up); throws for a real failure.
abstract class SocialTokenSource {
  Future<SocialToken?> google();

  Future<SocialToken?> apple();
}

/// The default until `google_sign_in` / `sign_in_with_apple` are added (see [SocialSignInConfig]):
/// no provider is wired, so every request reads as "cancelled". The buttons stay hidden anyway
/// unless a build flag turns them on.
class UnconfiguredSocialTokenSource implements SocialTokenSource {
  const UnconfiguredSocialTokenSource();

  @override
  Future<SocialToken?> google() async => null;

  @override
  Future<SocialToken?> apple() async => null;
}

/// The `platform` value the server accepts (`android` / `ios`), or null for anything else.
String? socialPlatformWire([TargetPlatform? platform]) {
  if (kIsWeb) return null;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => null,
  };
}
