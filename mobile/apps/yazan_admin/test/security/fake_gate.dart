import 'package:yazan_admin/src/security/biometric_gate.dart';

/// Scripted gate: answers [results] in order (then [fallback]) and records the calls.
class FakeBiometricGate implements BiometricGate {
  FakeBiometricGate({this.available = true, List<bool>? results, this.fallback = false})
      : results = List.of(results ?? const []);

  bool available;
  final List<bool> results;
  bool fallback;
  int authCalls = 0;
  final reasons = <String>[];

  @override
  Future<bool> canCheck() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    authCalls++;
    reasons.add(reason);
    return results.isEmpty ? fallback : results.removeAt(0);
  }
}
