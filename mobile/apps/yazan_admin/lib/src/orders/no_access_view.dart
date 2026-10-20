import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Shown when the server answers 403 for a feature the staff user may not use.
class NoAccessView extends StatelessWidget {
  const NoAccessView({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 40),
            const SizedBox(height: 12),
            Text(l.noAccessTitle, style: t.titleMedium),
            const SizedBox(height: 8),
            Text(l.noAccessBody, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
