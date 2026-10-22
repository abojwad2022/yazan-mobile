import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../products/product_permissions.dart' show PermissionsLoader;
import '../security/app_lock_controller.dart';
import '../security/require_unlock_tile.dart';
import 'more_registry.dart';
import 'staff_permissions.dart';

/// The More tab: the other sections as tiles. A tile the permission map does not allow is hidden;
/// while the map is unknown (not yet loaded, or offline) every tile shows and the server decides.
class MorePage extends StatefulWidget {
  const MorePage({
    super.key,
    required this.entries,
    required this.services,
    this.loadPermissions,
    this.lock,
  });

  final List<MoreEntry> entries;
  final MoreServices services;

  /// `GET /yazan-mobile/v1/me`; null keeps every tile.
  final PermissionsLoader? loadPermissions;

  /// The app lock; when present its "Require unlock" switch heads the list.
  final AppLockController? lock;

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  StaffPermissions _permissions = const StaffPermissions.unknown();
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    final loader = widget.loadPermissions;
    if (loader == null) return;
    try {
      final p = StaffPermissions.fromMe(await loader());
      if (!_disposed && mounted) setState(() => _permissions = p);
    } on Exception {
      // Offline or refused: keep every tile; each section checks again.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shown = [
      for (final e in widget.entries)
        if (e.visibleWith(_permissions)) e,
    ];
    if (shown.isEmpty && widget.lock == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(24),
          child: Text(l.moreEmpty, key: const ValueKey('more-empty'), textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      children: [
        if (widget.lock != null) RequireUnlockTile(controller: widget.lock!),
        for (final e in shown)
          ListTile(
            key: ValueKey('more-${e.key}'),
            leading: Icon(e.icon),
            title: Text(e.title(l)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (ctx) => e.builder(ctx, widget.services)),
            ),
          ),
      ],
    );
  }
}
