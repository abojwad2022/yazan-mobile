import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Opens the sign-in screen on the navigator of [context]; true when the customer signed in.
/// [email] prefills the address (for example the one a guest just ordered with).
typedef SignInOpener = Future<bool> Function(BuildContext context, {String? email});

/// Tells every screen whether a customer is signed in. The app works without an account; only
/// favourites and "my orders" need one, and they use [requireSignIn] to ask politely.
class SessionScope extends InheritedWidget {
  const SessionScope({
    super.key,
    required this.signedIn,
    required this.openSignIn,
    required super.child,
  });

  final bool signedIn;
  final SignInOpener openSignIn;

  /// Rebuilds the caller when the sign-in state changes (use in `build`).
  static SessionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>();

  /// Reads the scope without subscribing (use in event handlers).
  static SessionScope? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessionScope>();

  @override
  bool updateShouldNotify(SessionScope oldWidget) => signedIn != oldWidget.signedIn;
}

/// True when the customer may go on: signed in already, no session scope at all (a bare screen),
/// or a guest who agreed to sign in and did. A guest who declines gets false and nothing changes.
///
/// Shows "Sign in to use this" with a way to sign in or carry on browsing.
Future<bool> requireSignIn(BuildContext context) async {
  final session = SessionScope.maybeRead(context);
  if (session == null || session.signedIn) return true;
  final wantsSignIn = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(l.signInRequiredTitle),
        content: Text(l.signInRequiredBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.notNow),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.signIn),
          ),
        ],
      );
    },
  );
  if (wantsSignIn != true || !context.mounted) return false;
  return session.openSignIn(context);
}
