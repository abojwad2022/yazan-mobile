import 'package:yazan_domain/yazan_domain.dart';

/// Build-time settings. Nothing secret lives here: the app holds only its own short-lived session.
class AppConfig {
  const AppConfig._();

  /// `--dart-define=YAZAN_BASE_URL=http://10.0.2.2` for the Android emulator against Local.
  static const baseUrl = String.fromEnvironment('YAZAN_BASE_URL', defaultValue: 'https://yazanus.com');
  static const env = String.fromEnvironment('YAZAN_ENV', defaultValue: 'prod');
  static const scope = AppScope.store;

  /// The OAuth "Web application" client id from Google Cloud (`...apps.googleusercontent.com`), given
  /// at build time: `--dart-define=YAZAN_GOOGLE_SERVER_CLIENT_ID=...`. Google puts it in the ID token's
  /// audience, and the server checks it against `YAZAN_MOBILE_GOOGLE_CLIENT_IDS`. Empty = no Google
  /// button. Not a secret (it ships in every app that signs in with Google).
  static const googleServerClientId = String.fromEnvironment('YAZAN_GOOGLE_SERVER_CLIENT_ID');

  /// The iOS OAuth client id, for Google sign-in on iPhone (`--dart-define=YAZAN_GOOGLE_IOS_CLIENT_ID=...`).
  /// Google on iOS also needs its reversed id as a URL type and Sign in with Apple beside it
  /// (App Store rule 4.8); until then it stays empty and iPhones show no Google button.
  static const googleIosClientId = String.fromEnvironment('YAZAN_GOOGLE_IOS_CLIENT_ID');

  /// `--dart-define=YAZAN_APPLE_SIGNIN=1` turns on "Continue with Apple" on iOS once the app has the
  /// Sign in with Apple capability and a provider behind it.
  static const appleSignIn = String.fromEnvironment('YAZAN_APPLE_SIGNIN') == '1';

  /// The store's base country, used at checkout when the server cart has no country yet.
  static const defaultCountry = 'US';
}
