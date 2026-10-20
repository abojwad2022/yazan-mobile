import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../wishlist/wishlist_page.dart';
import '../wishlist/wishlist_scope.dart';
import 'account_api.dart';
import 'account_models.dart';
import 'account_widgets.dart';
import 'failure.dart';
import 'orders_page.dart';

/// A minimal account: who is signed in, my orders, favourites and sign-out.
class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.api,
    required this.findProduct,
    required this.onSignOut,
    required this.onSessionEnded,
  });

  final AccountApi api;

  /// Looks a product up in the local catalogue (for opening a favourite).
  final ProductLookup findProduct;

  /// Ends the session on the server and on the phone, then shows the sign-in form.
  final Future<void> Function() onSignOut;

  /// The server says the session is over: show the sign-in form.
  final VoidCallback onSessionEnded;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Profile? _profile;
  Failure? _failure;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.api.profile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
      });
    } catch (e) {
      if (!mounted) return;
      final failure = Failure.from(e);
      if (failure.isSignedOut) {
        endSession(context, widget.onSessionEnded);
        return;
      }
      setState(() {
        _failure = failure;
      });
    }
  }

  void _retry() {
    setState(() {
      _failure = null;
    });
    _load();
  }

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    setState(() => _signingOut = true);
    await widget.onSignOut();
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final wishlist = WishlistScope.maybeOf(context);
    final profile = _profile;
    final failure = _failure;
    final Widget header;
    if (profile != null) {
      header = Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (profile.name.isNotEmpty) Text(profile.name, style: theme.textTheme.titleLarge),
            if (profile.email.isNotEmpty) Text(profile.email, style: theme.textTheme.bodyMedium),
            if (profile.phone.isNotEmpty) Text(profile.phone, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    } else if (failure != null) {
      header = Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(failureMessage(l, failure)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _retry, child: Text(l.retry)),
          ],
        ),
      );
    } else {
      header = const Padding(
        padding: EdgeInsetsDirectional.all(16),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.account)),
      body: ListView(
        children: [
          header,
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(l.myOrders),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OrdersPage(api: widget.api, onSessionEnded: widget.onSessionEnded),
              ),
            ),
          ),
          if (wishlist != null)
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: Text(l.favourites),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WishlistPage(
                    controller: wishlist,
                    findProduct: widget.findProduct,
                    onSessionEnded: widget.onSessionEnded,
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsetsDirectional.all(16),
            child: OutlinedButton(
              onPressed: _signingOut ? null : _signOut,
              child: Text(l.signOut),
            ),
          ),
        ],
      ),
    );
  }
}
