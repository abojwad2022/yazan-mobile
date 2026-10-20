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
          child: Text(l.scanUnavailable, textAlign: TextAlign.center),
        ),
      );
    } else {
      body = Column(
        children: [
          Expanded(
            child: widget.scanner.buildPreview(context, onCode: _onCode, onError: _onError),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(16),
            child: Text(
              _notSerial ? l.scanNotSerial : l.scanQrHelp,
              textAlign: TextAlign.center,
              style: _notSerial ? TextStyle(color: theme.colorScheme.error) : null,
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
