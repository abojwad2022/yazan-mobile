import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import 'cart_controller.dart';
import 'store_api.dart';

/// Makes the [CartController] reachable from every route (product page, app bar badge).
class CartScope extends InheritedNotifier<CartController> {
  const CartScope({super.key, required CartController controller, required super.child})
      : super(notifier: controller);

  static CartController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CartScope>()?.notifier;
}

/// A short message for a Store API failure: offline, busy, the server's own words, or generic.
String storeErrorMessage(AppLocalizations l, StoreApiException e) {
  if (e.isNetwork) return l.offlineCart;
  if (e.isBusy) return l.checkoutBusy;
  if (e.message.isNotEmpty) return e.message;
  return l.genericError;
}
