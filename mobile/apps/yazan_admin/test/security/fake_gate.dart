import 'package:yazan_admin/src/security/biometric_gate.dart';

/// Scripted gate: answers [results] in order (then [fallback]) and records the calls.
/// [availability] is what [canCheck] answers; [throwOnCheck] makes it throw instead.
class FakeBiometricGate implements BiometricGate {
  FakeBiometricGate({
    bool available = true,
    GateAvailability? availability,
    List<bool>? results,
    this.fallback = false,
    this.throwOnCheck = false,
  })  : availability = availability ??
            (available ? GateAvailability.available : GateAvailability.unavailable),
        results = List.of(results ?? const []);

  GateAvailability availability;
  final List<bool> results;
  bool fallback;
  bool throwOnCheck;
  int authCalls = 0;
  int checkCalls = 0;
  final reasons = <String>[];

  /// Shorthand: true = available, false = an explicit "nothing enrolled".
  bool get available => availability == GateAvailability.available;
  set available(bool value) =>
      availability = value ? GateAvailability.available : GateAvailability.unavailable;

  @override
  Future<GateAvailability> canCheck() async {
    checkCalls++;
    if (throwOnCheck) throw StateError('canCheck failed');
    return availability;
  }

  @override
  Future<bool> authenticate(String reason) async {
    authCalls++;
    reasons.add(reason);
    return results.isEmpty ? fallback : results.removeAt(0);
  }
}
