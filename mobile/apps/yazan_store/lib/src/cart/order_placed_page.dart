import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'cart.dart';

/// Confirmation after a cash-on-delivery order: the server's order number and what happens next.
class OrderPlacedPage extends StatelessWidget {
  const OrderPlacedPage({super.key, required this.order});

  final PlacedOrder order;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.orderPlacedTitle), automaticallyImplyLeading: false),
      body: Center(
        child: Padding(
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
            ],
          ),
        ),
      ),
    );
  }
}
