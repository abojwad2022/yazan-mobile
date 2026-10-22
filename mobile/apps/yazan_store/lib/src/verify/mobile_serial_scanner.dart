import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_localizations.dart';
import 'serial_scanner.dart';

/// The app's real QR / barcode scanner, built on the `mobile_scanner` camera plugin.
///
/// It only reports what the camera reads; the scan page decides whether that is a serial. When
/// the camera cannot be used (permission refused, no camera on the device, the camera failed to
/// start) it calls `onError` once and the page falls back to typing the serial.
class MobileSerialScanner implements SerialScanner {
  const MobileSerialScanner();

  @override
  Widget buildPreview(
    BuildContext context, {
    required ValueChanged<String> onCode,
    required ValueChanged<Object> onError,
  }) =>
      _CameraPreview(onCode: onCode, onError: onError);
}

class _CameraPreview extends StatefulWidget {
  const _CameraPreview({required this.onCode, required this.onError});

  final ValueChanged<String> onCode;
  final ValueChanged<Object> onError;

  @override
  State<_CameraPreview> createState() => _CameraPreviewState();
}

class _CameraPreviewState extends State<_CameraPreview> with WidgetsBindingObserver {
  // Started by hand (autoStart off) so this state alone decides when the camera runs: on open, and
  // again when the app comes back to the foreground.
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// The camera started at least once, so pausing and resuming it with the app makes sense.
  /// (The permission prompt itself sends the app to "inactive"; nothing must stop the camera then.)
  bool _started = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onState);
    unawaited(_start());
  }

  /// The first start: any failure means the camera cannot be used here.
  Future<void> _start() async {
    if (_failed) return;
    try {
      await _controller.start();
      _started = true;
    } catch (e) {
      _fail(e);
    }
  }

  /// Back from the background. A camera that is somehow still running may refuse a second start;
  /// that is not a failure. A real one also lands in the controller's state, which [_onState] sees.
  Future<void> _resume() async {
    if (_failed) return;
    try {
      await _controller.start();
    } catch (_) {
      // Reported through the controller's state when it matters.
    }
  }

  void _onState() {
    final error = _controller.value.error;
    if (error != null) _fail(error);
  }

  void _fail(Object error) {
    if (_failed || !mounted) return;
    _failed = true;
    widget.onError(error);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_failed) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        widget.onCode(raw);
        return;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started || _failed) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_resume());
    } else if (state == AppLifecycleState.inactive) {
      unawaited(_controller.stop().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onState);
    unawaited(_controller.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // A frame to aim with; it does not limit where codes are read.
          IgnorePointer(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.7,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white70, width: 2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 12,
            end: 12,
            child: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) {
                if (state.torchState == TorchState.unavailable) return const SizedBox.shrink();
                final on = state.torchState == TorchState.on;
                return IconButton.filledTonal(
                  key: const Key('scan-torch'),
                  tooltip: on ? l.scanTorchOff : l.scanTorchOn,
                  isSelected: on,
                  icon: const Icon(Icons.flashlight_off),
                  selectedIcon: const Icon(Icons.flashlight_on),
                  onPressed: () => unawaited(_controller.toggleTorch().catchError((Object _) {})),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
