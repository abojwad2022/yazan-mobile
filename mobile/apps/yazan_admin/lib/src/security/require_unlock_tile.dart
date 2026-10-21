import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'app_lock_controller.dart';

/// The "Require unlock" switch for a settings list.
class RequireUnlockTile extends StatelessWidget {
  const RequireUnlockTile({super.key, required this.controller});

  final AppLockController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SwitchListTile(
        key: const ValueKey('require-unlock'),
        title: Text(l.lockSettingTitle),
        subtitle: Text(controller.available ? l.lockSettingBody : l.lockSettingUnavailable),
        value: controller.shouldGuard,
        onChanged: controller.authenticating || !controller.available
            ? null
            : (v) => controller.setEnabled(v, reason: l.lockDisableReason),
      ),
    );
  }
}
