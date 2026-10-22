/// What the phone said when asked whether it can check the person holding it.
enum GateAvailability {
  /// A fingerprint, face or screen-lock credential is there to answer.
  available,

  /// The phone said, explicitly, that it has nothing to check against (no credential enrolled, or
  /// no support at all). The only answer that lets the app run without a lock.
  unavailable,

  /// The question itself failed (plugin error, platform exception). Unknown is not "none": the app
  /// fails closed, stays locked and refuses sensitive actions until a check succeeds.
  error,
}

/// Asks the phone whether the person holding it is its owner. The app depends on this interface
/// only; the plugin lives in `local_auth_gate.dart` and tests use a fake.
abstract class BiometricGate {
  /// Whether the phone can check. Implementations should answer [GateAvailability.error] rather
  /// than throw; a throw is read as [GateAvailability.error] too.
  Future<GateAvailability> canCheck();

  /// Shows the system prompt (biometrics, falling back to the device PIN / pattern / passcode).
  /// Returns true only when the person passed. Cancel, failure, lock-out or any error is false.
  Future<bool> authenticate(String reason);
}
