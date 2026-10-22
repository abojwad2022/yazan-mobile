import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../l10n/app_localizations.dart';
import 'web_sign_in/web_sign_in.dart';

/// Staff sign-in.
///
/// The primary action is the website's own dashboard login ([WebSignIn], client `admin`): password,
/// second factor or passkey, and Google / Apple wherever the website allows them, exactly as on
/// `/dashboard`. The in-app username, password and 6-digit code form stays below it as a secondary
/// option.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.client, required this.onSignedIn, this.webSignIn});

  final YazanApiClient client;
  final VoidCallback onSignedIn;

  /// The website sign-in (tests inject one with a fake browser). Null = the system auth browser on
  /// the site [client] talks to.
  final WebSignIn? webSignIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _code = TextEditingController();
  late final WebSignIn _web =
      widget.webSignIn ?? WebSignIn.forClient(widget.client, browser: const SystemAuthBrowser());
  String? _challenge;
  String? _error;

  /// Small print under an unexpected error: its code and status, so the owner can report it.
  String? _errorCode;
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {bool web = false}) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _errorCode = null;
    });
    try {
      await action();
    } on ApiError catch (e) {
      final known = (web && e.code == 'yazan_mobile_bad_code' ? l.webSignInExpired : null) ??
          switch (e.action) {
            ErrorAction.backOff => l.tooManyAttempts,
            ErrorAction.enrolOnWeb => l.enrolFirst,
            ErrorAction.genericLoginFailure => l.signInFailed,
            _ => null,
          };
      if (known != null) {
        _error = known;
      } else {
        _unexpected(l, e);
      }
    } on WebSignInException {
      _error = l.webSignInFailed;
    } catch (e) {
      _unexpected(l, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// An error with no message of its own: the website not updated for the app yet (the route is
  /// missing, e.g. 404 `rest_no_route`), no connection or a timeout, or else a generic message with
  /// the code in small print so the owner can report it.
  void _unexpected(AppLocalizations l, Object e) {
    switch (signInTrouble(e)) {
      case SignInTrouble.websiteNotUpdated:
        _error = l.websiteNotUpdated;
      case SignInTrouble.connection:
        _error = l.signInConnection;
      case SignInTrouble.other:
        _error = l.signInUnexpected;
        _errorCode = signInErrorDetail(e);
    }
  }

  Future<void> _submit() => _run(() async {
        if (_challenge == null) {
          final r = await widget.client.login(
            login: _user.text.trim(),
            password: _pass.text,
            platform: platformWire() ?? 'unknown',
          );
          if (r.challenge != null) {
            _challenge = r.challenge!.token;
          } else {
            widget.onSignedIn();
          }
        } else {
          await widget.client.verifySecondStep(challenge: _challenge!, code: _code.text.trim());
          widget.onSignedIn();
        }
      });

  /// "Sign in with the website": the dashboard login in the auth browser, then the one-time code is
  /// swapped for an admin session. A closed browser is not an error: the screen stays as it was.
  Future<void> _signInOnWebsite() => _run(() async {
        final r = await _web.signIn(widget.client, platform: platformWire());
        if (r == null) return;
        if (r.challenge != null) {
          _challenge = r.challenge!.token;
        } else {
          widget.onSignedIn();
        }
      }, web: true);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final message = _error;
    final code = _errorCode;
    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(24),
          children: [
            if (_challenge == null) ...[
              FilledButton(
                key: const ValueKey('web-sign-in'),
                onPressed: _busy ? null : _signInOnWebsite,
                child: Text(l.webSignIn, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 8),
              Text(
                l.webSignInHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
                    child: Text(l.signInHereInstead, style: theme.textTheme.bodySmall),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _user,
                decoration: InputDecoration(labelText: l.email),
                autofillHints: const [AutofillHints.username],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: InputDecoration(labelText: l.password),
                autofillHints: const [AutofillHints.password],
              ),
            ] else
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.code),
              ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message,
                key: const ValueKey('sign-in-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              if (code != null)
                Text(
                  '($code)',
                  key: const ValueKey('sign-in-error-code'),
                  // A technical code reads left to right in both languages.
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodySmall,
                ),
            ],
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: _busy ? null : _submit,
              child: Text(_challenge == null ? l.signIn : l.verify),
            ),
          ],
        ),
      ),
    );
  }
}
