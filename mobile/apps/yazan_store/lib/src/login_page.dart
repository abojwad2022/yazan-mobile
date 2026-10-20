import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../l10n/app_localizations.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.client, required this.onSignedIn});

  final YazanApiClient client;
  final VoidCallback onSignedIn;

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

  Future<void> _run(Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiError catch (e) {
      _error = switch (e.action) {
        ErrorAction.backOff => l.tooManyAttempts,
        ErrorAction.genericLoginFailure => l.signInFailed,
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
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_challenge == null ? l.signIn : l.verify),
            ),
          ],
        ),
      ),
    );
  }
}
