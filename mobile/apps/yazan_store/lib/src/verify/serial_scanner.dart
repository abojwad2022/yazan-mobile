import 'package:flutter/widgets.dart';

import 'mobile_serial_scanner.dart';

/// A QR scanner the verification screen can show.
///
/// Scanning needs the camera, which is a native plugin the unit tests cannot run, so the screen
/// only knows this interface. The app passes a real one (built on the camera plugin) when it has
/// one; without a scanner the screen offers typing the serial only. Tests pass a fake.
abstract class SerialScanner {
  /// A live camera preview that reports every code it reads.
  ///
  /// [onCode] gets the raw text of a code (possibly many times for the same code). [onError] is
  /// called once when the camera cannot be used (permission refused, no camera).
  Widget buildPreview(
    BuildContext context, {
    required ValueChanged<String> onCode,
    required ValueChanged<Object> onError,
  });
}

/// The scanner the app ships with: the camera one ([MobileSerialScanner]).
///
/// Typing the serial stays available next to it, and is what the customer is sent back to when the
/// camera cannot be used (permission refused, no camera).
SerialScanner? defaultSerialScanner() => const MobileSerialScanner();
