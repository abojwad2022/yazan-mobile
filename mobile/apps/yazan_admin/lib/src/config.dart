import 'package:yazan_domain/yazan_domain.dart';

/// Build-time settings. Nothing secret lives here: the app holds only its own short-lived session.
class AppConfig {
  const AppConfig._();

  /// `--dart-define=YAZAN_BASE_URL=http://10.0.2.2` for the Android emulator against Local.
  static const baseUrl = String.fromEnvironment('YAZAN_BASE_URL', defaultValue: 'https://yazanus.com');
  static const env = String.fromEnvironment('YAZAN_ENV', defaultValue: 'prod');
  static const scope = AppScope.admin;
}
