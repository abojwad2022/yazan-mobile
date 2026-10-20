import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'account_models.dart';

/// The status in the app's language; a status the app does not know keeps the server's wording.
String orderStatusLabel(AppLocalizations l, OrderSummary order) {
  switch (order.status) {
    case 'pending':
      return l.statusPending;
    case 'processing':
      return l.statusProcessing;
    case 'on-hold':
      return l.statusOnHold;
    case 'completed':
      return l.statusCompleted;
    case 'cancelled':
      return l.statusCancelled;
    case 'refunded':
      return l.statusRefunded;
    case 'failed':
      return l.statusFailed;
  }
  return order.label.isNotEmpty ? order.label : order.status;
}

/// The date in the app's locale, or an empty string when the server sent none.
String orderDateText(BuildContext context, OrderSummary order) {
  final created = order.created;
  if (created == null) return '';
  return MaterialLocalizations.of(context).formatMediumDate(created.toLocal());
}

/// The session is over (refresh failed or the account was signed out elsewhere): leave every
/// pushed screen and let the app show the sign-in form.
void endSession(BuildContext context, VoidCallback onSessionEnded) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  onSessionEnded();
}

/// A centred message with an optional "Try again" button.
class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final retry = onRetry;
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (retry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: retry, child: Text(l.retry)),
            ],
          ],
        ),
      ),
    );
  }
}
