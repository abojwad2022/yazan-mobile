import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../l10n/app_localizations.dart';
import 'social/social_sign_in.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.client,
    required this.onSignedIn,
    this.social = SocialSignInConfig.none,
    this.socialTokens = const UnconfiguredSocialTokenSource(),
  });

  final YazanApiClient client;
  final VoidCallback onSignedIn;

  /// Which "Continue with ..." buttons to show; none by default (see [SocialSignInConfig]).
  final SocialSignInConfig social;

  /// Where the provider ID tokens come from.
  final SocialTokenSource socialTokens;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _code = TextEditingController();
  String? _challenge;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {bool social = false}) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiError catch (e) {
      _error = (social ? _socialError(l, e) : null) ??
          switch (e.action) {
            ErrorAction.backOff => l.tooManyAttempts,
            ErrorAction.genericLoginFailure => l.signInFailed,
            ErrorAction.hideFeature => l.featureUnavailable,
            _ => l.genericError,
          };
    } catch (_) {
      _error = l.genericError;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submit() => _run(() async {
        if (_challenge == null) {
          final r = await widget.client.login(login: _user.text.trim(), password: _pass.text);
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

  /// The social route's own answers: 404 while the provider is not set up on the server (or the
  /// server predates the route), one generic 401 for any refused token or account, 400 when the
  /// provider gave no verified email. Anything else falls through to the shared mapping.
  static String? _socialError(AppLocalizations l, ApiError e) {
    if (e.status == 404 || e.code == 'yazan_mobile_social_unavailable') return l.socialUnavailable;
    if (e.code == 'yazan_mobile_social_no_email' || e.code == 'yazan_mobile_social_unverified') {
      return l.socialEmailNeeded;
    }
    if (e.code == 'yazan_mobile_social_failed') return l.socialFailed;
    return null;
  }

  /// "Continue with Google / Apple": the provider SDK gives an ID token, the server swaps it for
  /// a session. A null token means the customer cancelled, which is not an error.
  Future<void> _social(String provider) => _run(() async {
        final token = provider == 'apple'
            ? await widget.socialTokens.apple()
            : await widget.socialTokens.google();
        if (token == null) return;
        final r = await widget.client.socialLogin(
          provider: provider,
          idToken: token.idToken,
          nonce: token.nonce,
          firstName: token.firstName,
          lastName: token.lastName,
          platform: socialPlatformWire(),
        );
        if (r.challenge != null) {
          _challenge = r.challenge!.token;
        } else {
          widget.onSignedIn();
        }
      }, social: true);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(24),
          children: [
            if (_challenge == null) ...[
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
            ] else
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.code),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_challenge == null ? l.signIn : l.verify),
            ),
            if (_challenge == null && widget.social.any) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
                    child: Text(l.socialOr, style: Theme.of(context).textTheme.bodySmall),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.social.google)
                OutlinedButton(
                  key: const ValueKey('social-google'),
                  onPressed: _busy ? null : () => _social('google'),
                  child: Text(l.continueWithGoogle),
                ),
              if (widget.social.google && widget.social.apple) const SizedBox(height: 12),
              if (widget.social.apple)
                OutlinedButton(
                  key: const ValueKey('social-apple'),
                  onPressed: _busy ? null : () => _social('apple'),
                  child: Text(l.continueWithApple),
                ),
            ],
            const SizedBox(height: 16),
            // Signing in is optional: the shop, cart and checkout work without an account.
            Text(
              l.signInOptional,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
