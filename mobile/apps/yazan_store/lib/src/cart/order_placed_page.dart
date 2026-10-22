import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../session_scope.dart';
import 'cart.dart';

/// Confirmation after a cash-on-delivery order: the server's order number and what happens next.
///
/// A guest is offered, never pushed, "Save your details for next time": the sign-in screen with the
/// email of the order already filled in.
class OrderPlacedPage extends StatelessWidget {
  const OrderPlacedPage({super.key, required this.order, this.email = ''});

  final PlacedOrder order;

  /// The email the order was placed with (prefills the sign-in screen).
  final String email;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = SessionScope.maybeOf(context);
    // Only a guest is offered an account (rebuilt, and so hidden, once they sign in).
    final offerSignIn = session != null && !session.signedIn ? session.openSignIn : null;
    return Scaffold(
      appBar: AppBar(title: Text(l.orderPlacedTitle), automaticallyImplyLeading: false),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(l.orderPlaced, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                l.orderNumber(order.orderNumber),
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(l.payOnDelivery, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: Text(l.continueShopping),
              ),
              if (offerSignIn != null) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                Text(l.saveDetailsBody, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('save-details'),
                  onPressed: () => offerSignIn(context, email: email),
                  child: Text(l.saveDetailsTitle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
