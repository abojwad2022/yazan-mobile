import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'biometric_gate.dart';

/// The real gate, on top of `local_auth` (Android BiometricPrompt, iOS LocalAuthentication).
/// Device credential is allowed as a fallback, so a phone with only a PIN still works.
class LocalAuthGate implements BiometricGate {
  LocalAuthGate([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canCheck() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } on PlatformException {
      return false;
    }
  }
}
