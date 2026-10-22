import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../l10n/app_localizations.dart';
import 'web_sign_in/web_sign_in.dart';

/// The optional sign-in screen.
///
/// The primary action is the website's own sign-in page ([WebSignIn]): email and password, Google,
/// Apple once the site offers it, and creating a new account all happen there, exactly as on the
/// web. The in-app email and password form stays as a secondary option behind "Sign in with email
/// here".
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.client,
    required this.onSignedIn,
    this.webSignIn,
  });

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

  /// Whether the in-app email form is open (it starts folded away under the website button).
  bool _showEmail = false;

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
      final known = (web ? _webError(l, e) : null) ??
          switch (e.action) {
            ErrorAction.backOff => l.tooManyAttempts,
            ErrorAction.genericLoginFailure => l.signInFailed,
            ErrorAction.hideFeature => l.featureUnavailable,
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
  /// missing), no connection, or else a generic message with the code in small print.
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

  /// The exchange route's own answer: the one-time code expired, was already used or did not match
  /// (400 `yazan_mobile_bad_code`). Anything else falls through to the shared mapping.
  static String? _webError(AppLocalizations l, ApiError e) {
    if (e.code == 'yazan_mobile_bad_code') return l.webSignInExpired;
    return null;
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

  /// "Sign in or create account": the website in the auth browser, then the one-time code is swapped
  /// for a session. A closed browser is not an error: the screen simply stays as it was.
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
    final error = message == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
          );
    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(24),
          children: [
            if (_challenge != null) ...[
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.code),
              ),
              if (error != null) ...[const SizedBox(height: 12), error],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(l.verify),
              ),
            ] else ...[
              FilledButton(
                key: const ValueKey('web-sign-in'),
                onPressed: _busy ? null : _signInOnWebsite,
                child: Text(l.webSignIn),
              ),
              const SizedBox(height: 8),
              Text(
                l.webSignInHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              if (!_showEmail) ...[
                if (error != null) ...[const SizedBox(height: 12), error],
                const SizedBox(height: 16),
                TextButton(
                  key: const ValueKey('email-sign-in'),
                  onPressed: _busy ? null : () => setState(() => _showEmail = true),
                  child: Text(l.signInWithEmailHere),
                ),
              ] else ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                TextField(
                  controller: _user,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l.email),
                  autofillHints: const [AutofillHints.username],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!_busy) _submit();
                  },
                  decoration: InputDecoration(labelText: l.password),
                  autofillHints: const [AutofillHints.password],
                ),
                if (error != null) ...[const SizedBox(height: 12), error],
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: _busy ? null : _submit,
                  child: Text(l.signIn),
                ),
              ],
            ],
            const SizedBox(height: 16),
            // Signing in is optional: the shop, cart and checkout work without an account.
            Text(
              l.signInOptional,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
