import 'package:flutter/foundation.dart';

/// The API client is built before the app, but the app has to react when the client finds the
/// session dead (refresh token refused). `main` hands [sessionEnded] to the client; the app shell
/// sets [onEnded].
class SessionEvents {
  /// Set by the app shell; one listener is enough.
  VoidCallback? onEnded;

  /// Pass this to `YazanApiClient(onSignedOut: ...)`.
  void sessionEnded() => onEnded?.call();
}
