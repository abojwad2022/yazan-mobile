import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import '../../l10n/app_localizations.dart';
import '../rewards/rewards_api.dart';
import '../rewards/rewards_page.dart';
import '../session_scope.dart';
import '../verify/serial_scanner.dart';
import '../verify/verify_api.dart';
import '../verify/verify_page.dart';

enum _Extra { verify, rewards }

/// The app bar's "More" menu: verify a ring (open to everyone) and rewards (needs an account; a
/// guest is asked to sign in first, the same way favourites does it).
///
/// The server routes are built from [client]; tests pass fakes instead.
class ExtrasMenuButton extends StatelessWidget {
  const ExtrasMenuButton({
    super.key,
    required this.client,
    required this.onSessionEnded,
    this.verifyApi,
    this.rewardsApi,
    this.scanner,
  });

  final YazanApiClient client;

  /// The server says the session is over: carry on as a guest.
  final VoidCallback onSessionEnded;

  final VerifyApi? verifyApi;
  final RewardsApi? rewardsApi;

  /// The QR scanner to offer; defaults to the app's own (see [defaultSerialScanner]).
  final SerialScanner? scanner;

  Future<void> _open(BuildContext context, _Extra extra) async {
    switch (extra) {
      case _Extra.verify:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VerifyPage(
              api: verifyApi ?? ClientVerifyApi(client),
              scanner: scanner ?? defaultSerialScanner(),
            ),
          ),
        );
      case _Extra.rewards:
        if (!await requireSignIn(context)) return;
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RewardsPage(
              api: rewardsApi ?? ClientRewardsApi(client),
              onSessionEnded: onSessionEnded,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopupMenuButton<_Extra>(
      tooltip: l.moreMenu,
      icon: const Icon(Icons.more_vert),
      onSelected: (extra) => _open(context, extra),
      itemBuilder: (_) => [
        PopupMenuItem<_Extra>(
          value: _Extra.verify,
          child: ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: Text(l.verifyRing),
          ),
        ),
        PopupMenuItem<_Extra>(
          value: _Extra.rewards,
          child: ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(l.rewards),
          ),
        ),
      ],
    );
  }
}
