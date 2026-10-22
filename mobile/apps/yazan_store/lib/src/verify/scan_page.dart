import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'serial.dart';
import 'serial_scanner.dart';

/// The camera screen: reads a QR code and closes with the serial it held (null when the customer
/// goes back). A code that is not a serial is refused with a short message and scanning goes on.
class ScanSerialPage extends StatefulWidget {
  const ScanSerialPage({super.key, required this.scanner});

  final SerialScanner scanner;

  @override
  State<ScanSerialPage> createState() => _ScanSerialPageState();
}

class _ScanSerialPageState extends State<ScanSerialPage> {
  bool _done = false;
  bool _notSerial = false;
  bool _cameraFailed = false;

  void _onCode(String raw) {
    if (_done || !mounted) return;
    final serial = serialFromScan(raw);
    if (serial == null) {
      if (!_notSerial) setState(() => _notSerial = true);
      return;
    }
    // The preview reports the same code many times a second: only the first one counts.
    _done = true;
    Navigator.of(context).pop(serial);
  }

  /// Closes with no serial. Ignored once a code has already closed the screen.
  void _cancel() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop();
  }

  void _onError(Object error) {
    if (!mounted || _cameraFailed) return;
    setState(() => _cameraFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final Widget body;
    if (_cameraFailed) {
      body = Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.scanUnavailable, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _cancel,
                child: Text(l.scanTypeInstead),
              ),
            ],
          ),
        ),
      );
    } else {
      body = Column(
        children: [
          Expanded(
            child: widget.scanner.buildPreview(context, onCode: _onCode, onError: _onError),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    liveRegion: _notSerial,
                    child: Text(
                      _notSerial ? l.scanNotSerial : l.scanQrHelp,
                      textAlign: TextAlign.center,
                      style: _notSerial ? TextStyle(color: theme.colorScheme.error) : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _cancel,
                    child: Text(l.scanCancel),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.scanQrTitle)),
      body: body,
    );
  }
}
