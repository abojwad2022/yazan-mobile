import 'package:yazan_domain/yazan_domain.dart';

import '../../l10n/app_localizations.dart';

/// "129.50 USD". Digits stay Latin; the server decides every amount.
String formatMoney(Money m) => '${m.toDecimalString()} ${m.currency}';

/// Localised label for a WooCommerce status slug; unknown slugs are shown as they are.
String statusLabel(AppLocalizations l, String status) {
  switch (status) {
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
  return status;
}
