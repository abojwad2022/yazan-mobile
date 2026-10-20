import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Shown on an `ApiError` with `ErrorAction.showConflict` (412). The caller decides what the two
/// buttons do: keep the server copy (drop the local edit) or retry the write against the server's
/// current version (`ApiError.current`).
class ConflictPage extends StatelessWidget {
  const ConflictPage({
    super.key,
    required this.local,
    required this.server,
    required this.onKeepServer,
    required this.onOverwrite,
    this.title,
    this.body,
  });

  /// Heading and explanation; default to the order wording.
  final String? title;
  final String? body;

  /// Field label to value, in display order.
  final List<MapEntry<String, String>> local;
  final List<MapEntry<String, String>> server;
  final VoidCallback onKeepServer;
  final VoidCallback onOverwrite;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title ?? l.conflictTitle)),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(16),
        children: [
          Text(body ?? l.conflictBody),
          const SizedBox(height: 16),
          _Section(title: l.conflictMine, rows: local),
          const SizedBox(height: 16),
          _Section(title: l.conflictServer, rows: server),
          const SizedBox(height: 24),
          FilledButton(onPressed: onKeepServer, child: Text(l.keepServer)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onOverwrite, child: Text(l.overwriteMine)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<MapEntry<String, String>> rows;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.titleSmall),
            const SizedBox(height: 8),
            for (final r in rows)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(r.key)),
                    const SizedBox(width: 12),
                    Flexible(child: Text(r.value, textAlign: TextAlign.end)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
