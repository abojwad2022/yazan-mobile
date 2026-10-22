import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart' show FlutterWebAuth2;
import 'package:yazan_api_client/yazan_api_client.dart' show AuthBrowser, signInErrorCode;

/// Opens the auth session (`flutter_web_auth_2`'s `authenticate`); a parameter so tests can stand
/// in for the plugin.
typedef AuthLauncher = Future<String> Function({
  required String url,
  required String callbackUrlScheme,
});

/// The phone's auth browser for the shared `WebSignIn` flow (the PKCE, state and code checks live
/// in `yazan_api_client`): Custom Tabs on Android, ASWebAuthenticationSession on iOS.
///
/// * Closing the browser (`PlatformException` code `CANCELED`) resolves null, which the sign-in
///   screen treats as "nothing happened". Any other platform failure is passed on.
/// * The session shares the browser's cookies, so someone already signed in on the website in that
///   browser is not asked again.
/// * Android needs the package's `CallbackActivity` for this app's scheme in the manifest
///   (mobile/tools/scaffold_platforms.sh adds it); iOS needs no URL type for it.
///
/// Kept identical in both apps (apps/yazan_store and apps/yazan_admin).
class SystemAuthBrowser implements AuthBrowser {
  const SystemAuthBrowser({AuthLauncher launch = _flutterWebAuth2}) : _launch = launch;

  final AuthLauncher _launch;

  static Future<String> _flutterWebAuth2({
    required String url,
    required String callbackUrlScheme,
  }) =>
      FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: callbackUrlScheme);

  @override
  Future<String?> authenticate({required Uri url, required String callbackScheme}) async {
    try {
      return await _launch(url: url.toString(), callbackUrlScheme: callbackScheme);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      rethrow;
    }
  }
}

/// The `platform` value the sign-in routes accept (`android` / `ios`), or null for anything else.
String? platformWire([TargetPlatform? platform]) {
  if (kIsWeb) return null;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => null,
  };
}

/// The small print under a generic sign-in message: the error's code (and HTTP status) so the owner
/// can report it, e.g. `code: rest_invalid_param, 400`.
String signInErrorDetail(Object error) =>
    error is PlatformException ? 'code: ${error.code}' : signInErrorCode(error);
