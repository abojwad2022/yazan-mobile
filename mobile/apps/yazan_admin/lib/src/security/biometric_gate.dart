/// Asks the phone whether the person holding it is its owner. The app depends on this interface
/// only; the plugin lives in `local_auth_gate.dart` and tests use a fake.
abstract class BiometricGate {
  /// True when the phone has a fingerprint, face or a screen-lock credential the person can answer.
  /// False means nothing is enrolled (or the phone cannot check at all).
  Future<bool> canCheck();

  /// Shows the system prompt (biometrics, falling back to the device PIN / pattern / passcode).
  /// Returns true only when the person passed. Cancel, failure, lock-out or any error is false.
  Future<bool> authenticate(String reason);
}
