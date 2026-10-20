import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../account/failure.dart';
import '../catalogue/price_text.dart';
import 'scan_page.dart';
import 'serial.dart';
import 'serial_scanner.dart';
import 'verify_api.dart';
import 'verify_models.dart';

enum _Phase { idle, loading, found, notFound, failed }

/// Checks a ring's serial number against YAZAN's records. Open to everyone (no account needed).
///
/// The result is exactly what the server returned: found (with its certificate fields), not found,
/// or too many checks. The app adds no statement about origin or silver purity of its own.
class VerifyPage extends StatefulWidget {
  const VerifyPage({super.key, required this.api, this.scanner, this.initialSerial});

  final VerifyApi api;

  /// A QR scanner, when the app has one. Without it only typing a serial is offered.
  final SerialScanner? scanner;

  /// A serial to check as soon as the screen opens.
  final String? initialSerial;

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  final TextEditingController _controller = TextEditingController();
  _Phase _phase = _Phase.idle;
  RingCertificate? _certificate;
  Failure? _failure;
  String _checked = '';
  bool _tooShort = false;

  /// Bumped on every check so a slow earlier answer cannot overwrite a newer one.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSerial;
    if (initial != null && initial.isNotEmpty) {
      _controller.text = cleanSerial(initial);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _check();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_phase == _Phase.loading) return;
    final serial = cleanSerial(_controller.text);
    if (serial.length < serialMinLength) {
      setState(() => _tooShort = true);
      return;
    }
    if (_controller.text != serial) _controller.text = serial;
    final attempt = ++_attempt;
    setState(() {
      _tooShort = false;
      _phase = _Phase.loading;
      _checked = serial;
      _certificate = null;
      _failure = null;
    });
    try {
      final certificate = await widget.api.lookup(serial);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _certificate = certificate;
        _phase = _Phase.found;
      });
    } catch (e) {
      if (!mounted || attempt != _attempt) return;
      final failure = Failure.from(e);
      setState(() {
        if (failure.kind == FailureKind.notFound) {
          _phase = _Phase.notFound;
        } else {
          _failure = failure;
          _phase = _Phase.failed;
        }
      });
    }
  }

  Future<void> _scan() async {
    final scanner = widget.scanner;
    if (scanner == null || _phase == _Phase.loading) return;
    final serial = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => ScanSerialPage(scanner: scanner)),
    );
    if (!mounted || serial == null) return;
    _controller.text = serial;
    _check();
  }

  /// Typing a new serial clears the old answer, so it is never read as the new serial's result.
  void _edited(String _) {
    if (_phase == _Phase.loading) return;
    if (_phase != _Phase.idle || _tooShort) {
      setState(() {
        _phase = _Phase.idle;
        _tooShort = false;
        _certificate = null;
        _failure = null;
      });
    }
  }

  String _failureText(AppLocalizations l, Failure f) {
    switch (f.kind) {
      case FailureKind.rateLimited:
        return l.verifyRateLimited;
      case FailureKind.offline:
        return l.offlineAccount;
      case FailureKind.signedOut:
      case FailureKind.unavailable:
      case FailureKind.notFound:
      case FailureKind.other:
        return l.genericError;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final loading = _phase == _Phase.loading;
    final certificate = _certificate;
    final failure = _failure;
    return Scaffold(
      appBar: AppBar(title: Text(l.verifyRing)),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(16),
        children: [
          Text(l.verifyIntro),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !loading,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.search,
            // A serial is Latin letters and digits: keep it left to right in Arabic too.
            textDirection: TextDirection.ltr,
            onChanged: _edited,
            onSubmitted: (_) => _check(),
            decoration: InputDecoration(
              labelText: l.serialLabel,
              hintText: l.serialHint,
              errorText: _tooShort ? l.serialTooShort : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: loading ? null : _check,
            child: Text(l.checkSerial),
          ),
          if (widget.scanner != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: loading ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(l.scanQr),
            ),
          ],
          const SizedBox(height: 24),
          if (loading) const Center(child: CircularProgressIndicator()),
          if (_phase == _Phase.found && certificate != null)
            _CertificateCard(certificate: certificate),
          if (_phase == _Phase.notFound)
            _Notice(
              icon: Icons.search_off,
              title: l.verifyNotFoundTitle,
              body: l.verifyNotFoundBody(_checked),
            ),
          if (_phase == _Phase.failed && failure != null)
            _Notice(
              icon: Icons.error_outline,
              title: null,
              body: _failureText(l, failure),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String? title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = title;
    return Semantics(
      liveRegion: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (heading != null) Text(heading, style: theme.textTheme.titleMedium),
                    if (heading != null) const SizedBox(height: 4),
                    Text(body),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  const _CertificateCard({required this.certificate});

  final RingCertificate certificate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = certificate;
    final rows = <(String, String)>[
      (l.certStone, c.stone),
      (l.certColor, c.color),
      (l.certMetal, c.metal),
      (l.certPurity, c.purity),
      (l.certOrigin, c.origin),
      (l.certShape, c.shape),
      (l.certCarat, c.carat),
      (l.certWearer, c.wearer),
      (l.certCollection, c.collection),
      (l.certYear, c.year),
    ];
    return Semantics(
      liveRegion: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l.verifyGenuineTitle, style: theme.textTheme.titleMedium)),
                ],
              ),
              const SizedBox(height: 8),
              Text(l.verifyGenuineBody),
              const SizedBox(height: 16),
              if (c.imageUrl != null) ...[
                SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ProductImageView(url: c.imageUrl),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (c.name.isNotEmpty) Text(c.name, style: theme.textTheme.titleMedium),
              if (c.oneOfOne)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Chip(label: Text(l.certOneOfOne)),
                  ),
                ),
              const SizedBox(height: 8),
              _Row(label: l.certSerial, value: c.serial, ltr: true),
              for (final (label, value) in rows)
                if (value.isNotEmpty) _Row(label: label, value: value),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.ltr = false});

  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            // Start-aligned in the page's direction, so the value sits next to its label in Arabic too.
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, textDirection: ltr ? TextDirection.ltr : null),
            ),
          ),
        ],
      ),
    );
  }
}
