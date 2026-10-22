import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_design_system/yazan_design_system.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../l10n/app_localizations.dart';
import 'auth/social_sign_in.dart';
import 'links.dart';
import 'web_sign_in/web_sign_in.dart';

/// The steps of the sign-in screen, one at a time.
enum SignInStep {
  /// "Welcome to YAZAN": Google / Apple when this build has them, then one email field.
  email,

  /// "Welcome back": the email has an account; the password, or "Forgot password?".
  password,

  /// "Create your YAZAN account": names, a new password, an unticked marketing box.
  create,

  /// "Check your inbox" after "Forgot password?", with a resend timer.
  inbox,

  /// The second-step code (an account with two-step sign-in).
  code,
}

/// Roughly an email address: something, one `@`, a dotted domain, no spaces. The server decides.
bool looksLikeEmail(String value) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

/// The hint under a new password.
enum PasswordStrength { tooShort, fair, strong }

/// At least 8 characters is the floor (the server checks too); 12 or more with three kinds of
/// character (lower, upper, digit, symbol) reads as strong.
PasswordStrength passwordStrength(String value) {
  if (value.length < 8) return PasswordStrength.tooShort;
  var kinds = 0;
  if (RegExp('[a-z]').hasMatch(value)) kinds++;
  if (RegExp('[A-Z]').hasMatch(value)) kinds++;
  if (RegExp('[0-9]').hasMatch(value)) kinds++;
  if (RegExp('[^A-Za-z0-9]').hasMatch(value)) kinds++;
  return value.length >= 12 && kinds >= 3 ? PasswordStrength.strong : PasswordStrength.fair;
}

/// The optional sign-in screen, the way global shopping apps do it: native and one step per screen.
///
/// 1. "Continue with Google" (and Apple on iOS) when this build has them, else just the email.
/// 2. `POST /auth/lookup` decides: "Welcome back" with the password, or "Create your YAZAN account".
/// 3. "Forgot password?" sends the reset email and always shows "Check your inbox".
///
/// The website's own sign-in page ([WebSignIn]) stays as the small "Other ways to sign in" link at
/// the bottom, for anything the app does not offer natively yet.
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.client,
    required this.onSignedIn,
    this.webSignIn,
    this.google,
    this.apple,
    this.openLink = openInBrowser,
    this.initialEmail = '',
  });

  final YazanApiClient client;
  final VoidCallback onSignedIn;

  /// The website sign-in (tests inject one with a fake browser). Null = the system auth browser on
  /// the site [client] talks to.
  final WebSignIn? webSignIn;

  /// "Continue with Google"; null hides the button.
  final SocialTokenSource? google;

  /// "Continue with Apple"; null hides the button.
  final SocialTokenSource? apple;

  /// Opens the Terms and the Privacy Policy.
  final LinkOpener openLink;

  /// Prefills the email (for example after a guest order).
  final String initialEmail;

  /// Seconds before "Resend email" can be tapped again.
  static const resendSeconds = 60;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _pass = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _code = TextEditingController();
  final _createForm = GlobalKey<FormState>();
  late final WebSignIn _web =
      widget.webSignIn ?? WebSignIn.forClient(widget.client, browser: const SystemAuthBrowser());

  SignInStep _step = SignInStep.email;
  AccountLookup? _lookup;
  String? _challenge;
  String? _error;

  /// Small print under an unexpected error: its code and status, so the owner can report it.
  String? _errorCode;

  /// A calm note that is not an error (for example "this email already has an account").
  String? _notice;
  bool _busy = false;
  bool _obscure = true;
  bool _marketing = false;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _email.dispose();
    _pass.dispose();
    _first.dispose();
    _last.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _emailValue => _email.text.trim();

  /// Moves to [step], clearing messages. Going back to the email forgets the password typed.
  void _go(SignInStep step) {
    setState(() {
      _step = step;
      _error = null;
      _errorCode = null;
      _notice = null;
      _obscure = true;
      if (step != SignInStep.inbox) _stopResendTimer();
      if (step == SignInStep.email) {
        _pass.clear();
        _challenge = null;
      }
    });
  }

  SignInStep? get _previous => switch (_step) {
        SignInStep.email => null,
        SignInStep.password || SignInStep.create || SignInStep.code => SignInStep.email,
        SignInStep.inbox => SignInStep.password,
      };

  void _back() {
    final previous = _previous;
    if (previous == null) {
      Navigator.of(context).maybePop();
    } else {
      _go(previous);
    }
  }

  Future<void> _run(Future<void> Function() action, {bool web = false}) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _errorCode = null;
      _notice = null;
    });
    try {
      await action();
    } on ApiError catch (e) {
      final known = _known(l, e, web: web);
      if (known != null) {
        _error = known;
      } else {
        _unexpected(l, e);
      }
    } on WebSignInException {
      _error = l.webSignInFailed;
    } on SocialSignInException catch (e) {
      _error = l.socialFailed;
      _errorCode = 'code: ${e.code}';
    } catch (e) {
      _unexpected(l, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// The server's answers that have a message of their own.
  static String? _known(AppLocalizations l, ApiError e, {required bool web}) {
    switch (e.code) {
      case 'yazan_mobile_bad_code':
        // The website's one-time code expired or was used; a wrong second-step code is generic.
        return web ? l.webSignInExpired : l.signInFailed;
      case 'yazan_mobile_weak_password':
        return l.weakPassword;
      case 'yazan_mobile_terms_required':
        return l.termsRequired;
      case 'yazan_mobile_bad_email':
        return l.badEmail;
      case 'yazan_mobile_bad_name':
        return l.badName;
      case 'yazan_mobile_registration_closed':
        return l.registrationClosed;
      case 'yazan_mobile_social_unavailable':
        return l.socialUnavailable;
      case 'yazan_mobile_social_failed':
        return l.socialFailed;
    }
    if (e.status == 429) return l.tooManyAttempts;
    return switch (e.action) {
      ErrorAction.backOff => l.tooManyAttempts,
      ErrorAction.genericLoginFailure => l.signInFailed,
      ErrorAction.hideFeature => l.featureUnavailable,
      _ => null,
    };
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

  /// A session, or the second-step code screen.
  void _finish(LoginResult r) {
    final challenge = r.challenge;
    if (challenge != null) {
      _challenge = challenge.token;
      _code.clear();
      _step = SignInStep.code;
      return;
    }
    widget.onSignedIn();
  }

  /// "Continue" on the email: does an account use it?
  Future<void> _continue() async {
    final l = AppLocalizations.of(context);
    if (!looksLikeEmail(_emailValue)) {
      setState(() {
        _error = l.badEmail;
        _errorCode = null;
        _notice = null;
      });
      return;
    }
    await _run(() async {
      final found = await widget.client.lookup(_emailValue);
      _lookup = found;
      _pass.clear();
      _obscure = true;
      _step = found.exists ? SignInStep.password : SignInStep.create;
    });
  }

  Future<void> _signIn() => _run(() async {
        final r = await widget.client.login(
          login: _emailValue,
          password: _pass.text,
          platform: platformWire() ?? 'unknown',
        );
        _finish(r);
      });

  Future<void> _create() async {
    final l = AppLocalizations.of(context);
    final form = _createForm.currentState;
    if (form == null || !form.validate()) return;
    await _run(() async {
      try {
        final r = await widget.client.register(
          firstName: _first.text.trim(),
          lastName: _last.text.trim(),
          email: _emailValue,
          password: _pass.text,
          marketingOptIn: _marketing,
          platform: platformWire(),
        );
        _finish(r);
      } on ApiError catch (e) {
        if (e.code != 'yazan_mobile_email_taken') rethrow;
        // Someone already has an account with this email: offer the sign-in step instead.
        _lookup = const AccountLookup(exists: true);
        _pass.clear();
        _obscure = true;
        _step = SignInStep.password;
        _notice = l.emailTaken;
      }
    });
  }

  /// "Forgot password?" and "Resend email": the answer is the same whether or not the email has an
  /// account, so the screen is too.
  Future<void> _forgot() => _run(() async {
        await widget.client.forgotPassword(_emailValue);
        _step = SignInStep.inbox;
        _startResendTimer();
      });

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendIn = LoginPage.resendSeconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendIn--;
        if (_resendIn <= 0) {
          _resendIn = 0;
          timer.cancel();
        }
      });
    });
  }

  void _stopResendTimer() {
    _resendTimer?.cancel();
    _resendTimer = null;
    _resendIn = 0;
  }

  Future<void> _verify() => _run(() async {
        await widget.client.verifySecondStep(challenge: _challenge!, code: _code.text.trim());
        widget.onSignedIn();
      });

  /// "Continue with Google / Apple": the provider's ID token goes to `/auth/social`. Closing the
  /// provider's sheet is not an error: the screen stays as it was.
  Future<void> _social(SocialTokenSource source) => _run(() async {
        final token = await source.obtain();
        if (token == null) return;
        final r = await widget.client.socialLogin(
          provider: source.provider,
          idToken: token.idToken,
          nonce: token.nonce,
          firstName: token.firstName,
          lastName: token.lastName,
          platform: platformWire(),
        );
        _finish(r);
      });

  /// "Other ways to sign in": the website in the auth browser, then the one-time code is swapped
  /// for a session. A closed browser is not an error.
  Future<void> _signInOnWebsite() => _run(() async {
        final r = await _web.signIn(widget.client, platform: platformWire());
        if (r == null) return;
        _finish(r);
      }, web: true);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final children = switch (_step) {
      SignInStep.email => _emailStep(l, theme),
      SignInStep.password => _passwordStep(l, theme),
      SignInStep.create => _createStep(l, theme),
      SignInStep.inbox => _inboxStep(l, theme),
      SignInStep.code => _codeStep(l, theme),
    };
    return PopScope<Object?>(
      // System back walks the steps first; on the first step it closes the screen.
      canPop: _step == SignInStep.email,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _step == SignInStep.email ? const CloseButton() : BackButton(onPressed: _back),
          bottom: _busy
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AutofillGroup(
                child: ListView(
                  key: ValueKey('sign-in-${_step.name}'),
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 24),
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- steps -----------------------------------------------------------------------------------

  List<Widget> _emailStep(AppLocalizations l, ThemeData theme) {
    final google = widget.google;
    final apple = widget.apple;
    return [
      YazanHeading(l.welcomeTitle),
      const SizedBox(height: 8),
      Text(l.welcomeSubtitle, style: theme.textTheme.bodyMedium),
      const SizedBox(height: 28),
      if (apple != null) ...[
        _socialButton(const ValueKey('apple-sign-in'), l.continueWithApple, Icons.apple, apple),
        const SizedBox(height: 12),
      ],
      if (google != null) ...[
        _socialButton(const ValueKey('google-sign-in'), l.continueWithGoogle, null, google),
        const SizedBox(height: 12),
      ],
      if (apple != null || google != null) ...[
        _OrDivider(label: l.orDivider),
        const SizedBox(height: 12),
      ],
      TextField(
        key: const ValueKey('auth-email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.go,
        // An address reads left to right in both languages.
        textDirection: TextDirection.ltr,
        autocorrect: false,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) {
          if (!_busy) _continue();
        },
        decoration: InputDecoration(labelText: l.emailAddress),
      ),
      ..._messages(theme),
      const SizedBox(height: 20),
      FilledButton(
        key: const ValueKey('auth-continue'),
        onPressed: _busy ? null : _continue,
        child: Text(l.continueAction),
      ),
      const SizedBox(height: 16),
      _consent(l, theme),
      const SizedBox(height: 24),
      Center(
        child: TextButton(
          key: const ValueKey('web-sign-in'),
          onPressed: _busy ? null : _signInOnWebsite,
          child: Text(l.otherWaysToSignIn),
        ),
      ),
      const SizedBox(height: 4),
      // Signing in is optional: the shop, cart and checkout work without an account.
      Text(l.signInOptional, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
    ];
  }

  List<Widget> _passwordStep(AppLocalizations l, ThemeData theme) {
    final google = widget.google;
    final noPassword = !(_lookup?.hasPassword ?? true);
    return [
      YazanHeading(l.welcomeBack),
      const SizedBox(height: 12),
      _emailRow(l, theme),
      const SizedBox(height: 16),
      if (noPassword) ...[
        Text(l.noPasswordYet, key: const ValueKey('auth-no-password'), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        if (google != null) ...[
          _socialButton(const ValueKey('google-sign-in'), l.continueWithGoogle, null, google),
          const SizedBox(height: 12),
        ],
      ],
      _passwordField(l, newPassword: false, onDone: _signIn),
      ..._messages(theme),
      const SizedBox(height: 20),
      FilledButton(
        key: const ValueKey('auth-sign-in'),
        onPressed: _busy ? null : _signIn,
        child: Text(l.signIn),
      ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          key: const ValueKey('auth-forgot'),
          onPressed: _busy ? null : _forgot,
          child: Text(l.forgotPassword),
        ),
      ),
    ];
  }

  List<Widget> _createStep(AppLocalizations l, ThemeData theme) {
    final hint = switch (passwordStrength(_pass.text)) {
      PasswordStrength.tooShort => l.passwordHintShort,
      PasswordStrength.fair => l.passwordHintFair,
      PasswordStrength.strong => l.passwordHintStrong,
    };
    String? filled(String? value) => (value ?? '').trim().isEmpty ? l.requiredField : null;
    return [
      YazanHeading(l.createAccountTitle),
      const SizedBox(height: 12),
      _emailRow(l, theme),
      const SizedBox(height: 16),
      Form(
        key: _createForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const ValueKey('auth-first-name'),
              controller: _first,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.givenName],
              validator: filled,
              decoration: InputDecoration(labelText: l.firstName),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('auth-last-name'),
              controller: _last,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.familyName],
              validator: filled,
              decoration: InputDecoration(labelText: l.lastName),
            ),
            const SizedBox(height: 12),
            _passwordField(
              l,
              newPassword: true,
              onDone: _create,
              helper: hint,
              validator: (value) => (value ?? '').length < 8 ? l.passwordTooShort : null,
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      CheckboxListTile(
        key: const ValueKey('auth-marketing'),
        value: _marketing,
        onChanged: _busy ? null : (v) => setState(() => _marketing = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsetsDirectional.zero,
        title: Text(l.marketingOptIn, style: theme.textTheme.bodyMedium),
      ),
      ..._messages(theme),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('auth-create'),
        onPressed: _busy ? null : _create,
        child: Text(l.createAccount),
      ),
      const SizedBox(height: 16),
      _consent(l, theme),
    ];
  }

  List<Widget> _inboxStep(AppLocalizations l, ThemeData theme) {
    final waiting = _resendIn > 0;
    return [
      const SizedBox(height: 8),
      Icon(Icons.mark_email_read_outlined, size: 48, color: theme.colorScheme.primary),
      const SizedBox(height: 16),
      YazanHeading(l.checkInboxTitle, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Text(
        l.resetSent(_emailValue),
        key: const ValueKey('auth-reset-sent'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      ..._messages(theme),
      const SizedBox(height: 24),
      OutlinedButton(
        key: const ValueKey('auth-resend'),
        onPressed: waiting || _busy ? null : _forgot,
        child: Text(waiting ? l.resendIn(_resendIn) : l.resendEmail),
      ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          key: const ValueKey('auth-back-to-sign-in'),
          onPressed: _busy ? null : () => _go(SignInStep.password),
          child: Text(l.backToSignIn),
        ),
      ),
    ];
  }

  List<Widget> _codeStep(AppLocalizations l, ThemeData theme) {
    return [
      YazanHeading(l.welcomeBack),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('auth-code'),
        controller: _code,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        autofillHints: const [AutofillHints.oneTimeCode],
        decoration: InputDecoration(labelText: l.code),
      ),
      ..._messages(theme),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _busy ? null : _verify,
        child: Text(l.verify),
      ),
    ];
  }

  // ---- pieces ----------------------------------------------------------------------------------

  Widget _socialButton(Key key, String label, IconData? icon, SocialTokenSource source) {
    void onPressed() => _social(source);
    final child = Text(label);
    return SizedBox(
      height: 48,
      child: icon == null
          ? OutlinedButton(key: key, onPressed: _busy ? null : onPressed, child: child)
          : OutlinedButton.icon(
              key: key,
              onPressed: _busy ? null : onPressed,
              icon: Icon(icon),
              label: child,
            ),
    );
  }

  /// The email being used, with "Change" to go back to the first step.
  Widget _emailRow(AppLocalizations l, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          // At the start of the row in both languages; the address itself reads left to right.
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _emailValue,
              key: const ValueKey('auth-email-shown'),
              textDirection: TextDirection.ltr,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
        TextButton(
          key: const ValueKey('auth-change-email'),
          onPressed: _busy ? null : () => _go(SignInStep.email),
          child: Text(l.changeEmail),
        ),
      ],
    );
  }

  Widget _passwordField(
    AppLocalizations l, {
    required bool newPassword,
    required Future<void> Function() onDone,
    String? helper,
    FormFieldValidator<String>? validator,
  }) {
    return TextFormField(
      key: const ValueKey('auth-password'),
      controller: _pass,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      textDirection: TextDirection.ltr,
      textInputAction: TextInputAction.done,
      autofillHints: [newPassword ? AutofillHints.newPassword : AutofillHints.password],
      validator: validator,
      // The strength hint follows what is typed.
      onChanged: newPassword ? (_) => setState(() {}) : null,
      onFieldSubmitted: (_) {
        if (!_busy) onDone();
      },
      decoration: InputDecoration(
        labelText: newPassword ? l.newPassword : l.password,
        helperText: helper,
        suffixIcon: IconButton(
          tooltip: _obscure ? l.showPassword : l.hidePassword,
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
      ),
    );
  }

  /// "By continuing you agree to ...", with the two pages one tap away.
  Widget _consent(AppLocalizations l, ThemeData theme) {
    final base = widget.client.baseUrl;
    return Column(
      children: [
        Text(l.consentLine, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              key: const ValueKey('auth-terms'),
              onPressed: () => widget.openLink(SiteLinks.terms(base)),
              child: Text(l.termsLink),
            ),
            TextButton(
              key: const ValueKey('auth-privacy'),
              onPressed: () => widget.openLink(SiteLinks.privacy(base)),
              child: Text(l.privacyLink),
            ),
          ],
        ),
      ],
    );
  }

  /// The error (with its code in small print) or the calm notice, under the field.
  List<Widget> _messages(ThemeData theme) {
    final message = _error;
    final code = _errorCode;
    final notice = _notice;
    return [
      if (notice != null) ...[
        const SizedBox(height: 12),
        Text(
          notice,
          key: const ValueKey('sign-in-notice'),
          style: TextStyle(color: theme.colorScheme.primary),
        ),
      ],
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
    ];
  }
}

/// A thin rule with "or" in the middle.
class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
