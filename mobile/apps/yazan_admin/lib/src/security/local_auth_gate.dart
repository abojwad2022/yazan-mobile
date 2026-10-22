import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'biometric_gate.dart';

/// `local_auth` error codes that are an explicit "nothing to check against" answer (the values of
/// `package:local_auth/error_codes.dart`: notAvailable, notEnrolled, passcodeNotSet). Any other
/// exception is an error, never read as "no credential".
const Set<String> _noCredentialCodes = {'NotAvailable', 'NotEnrolled', 'PasscodeNotSet'};

/// The real gate, on top of `local_auth` (Android BiometricPrompt, iOS LocalAuthentication).
/// Device credential is allowed as a fallback, so a phone with only a PIN still works.
class LocalAuthGate implements BiometricGate {
  LocalAuthGate([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<GateAvailability> canCheck() async {
    try {
      return await _auth.isDeviceSupported()
          ? GateAvailability.available
          : GateAvailability.unavailable;
    } on PlatformException catch (e) {
      return _noCredentialCodes.contains(e.code)
          ? GateAvailability.unavailable
          : GateAvailability.error;
    } catch (_) {
      // MissingPluginException and the like: unknown, so fail closed.
      return GateAvailability.error;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } catch (_) {
      return false;
    }
  }
}
