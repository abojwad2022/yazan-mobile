import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../../l10n/app_localizations.dart';
import '../web_sign_in/web_sign_in.dart';
import 'account_api.dart';
import 'failure.dart';

/// "Delete your account": the customer confirms with the password, and the dialog makes the call
/// itself so a wrong password can be said in place. Pops true once the account is gone.
///
/// [onWebsite] opens the website's account-deletion page (for an account without a password, or
/// anyone who prefers to ask there); null hides the link.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.api, this.onWebsite});

  final AccountApi api;
  final VoidCallback? onWebsite;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _errorCode;

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final password = _pass.text;
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _errorCode = null;
    });
    try {
      await widget.api.deleteAccount(password: password);
      if (mounted) Navigator.of(context).pop(true);
      return;
    } catch (e) {
      _describe(l, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _describe(AppLocalizations l, Object e) {
    if (e is ApiError) {
      if (e.status == 429 || e.action == ErrorAction.backOff) {
        _error = l.tooManyAttempts;
        return;
      }
      if (e.code == 'yazan_mobile_reauth_required') {
        _error = l.deleteReauthRequired;
        return;
      }
      if (e.code == 'yazan_mobile_cannot_delete') {
        _error = l.deleteNotAllowed;
        return;
      }
      if (e.action == ErrorAction.genericLoginFailure || e.code.contains('password')) {
        _error = l.deletePasswordWrong;
        return;
      }
      if (signInTrouble(e) == SignInTrouble.websiteNotUpdated) {
        _error = l.websiteNotUpdated;
        return;
      }
      final failure = Failure.from(e);
      if (failure.kind != FailureKind.other) {
        _error = failureMessage(l, failure);
        return;
      }
      _error = l.signInUnexpected;
      _errorCode = signInErrorDetail(e);
      return;
    }
    if (signInTrouble(e) == SignInTrouble.connection) {
      _error = l.signInConnection;
      return;
    }
    _error = l.signInUnexpected;
    _errorCode = signInErrorDetail(e);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final error = _error;
    final code = _errorCode;
    final onWebsite = widget.onWebsite;
    return AlertDialog(
      title: Text(l.deleteAccountTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.deleteAccountBody),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('delete-password'),
              controller: _pass,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l.password,
                helperText: l.deleteNoPasswordHint,
                helperMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: _obscure ? l.showPassword : l.hidePassword,
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error,
                key: const ValueKey('delete-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              if (code != null)
                Text(
                  '($code)',
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodySmall,
                ),
            ],
            if (onWebsite != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('delete-on-website'),
                  onPressed: onWebsite,
                  child: Text(l.deleteOnWebsite),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('delete-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _busy ? null : _submit,
          child: Text(l.deleteAccountConfirm),
        ),
      ],
    );
  }
}
