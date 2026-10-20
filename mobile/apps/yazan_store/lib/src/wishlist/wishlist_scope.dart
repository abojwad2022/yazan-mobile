import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../account/failure.dart';
import 'wishlist_controller.dart';

/// Makes the [WishlistController] reachable from every route (product page, app bar, account).
class WishlistScope extends InheritedNotifier<WishlistController> {
  const WishlistScope({super.key, required WishlistController controller, required super.child})
      : super(notifier: controller);

  static WishlistController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WishlistScope>()?.notifier;
}

/// A message for a favourites failure; offline names what needs the connection.
String wishlistErrorMessage(AppLocalizations l, Failure f) =>
    f.kind == FailureKind.offline ? l.favouritesOffline : failureMessage(l, f);
