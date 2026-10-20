import 'package:flutter/material.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../../l10n/app_localizations.dart';
import 'observed_sync_engine.dart';

/// The queue of changes made on this phone that the server has not confirmed yet: how many are
/// waiting, which need attention, when the last sync reached the server, and a way to retry.
///
/// Reads the [OutboxStore] of the signed-in account only.
class SyncCenterPage extends StatefulWidget {
  const SyncCenterPage({
    super.key,
    required this.accountId,
    required this.store,
    required this.engine,
  });

  final String accountId;
  final OutboxStore store;
  final ObservedSyncEngine engine;

  @override
  State<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends State<SyncCenterPage> {
  List<OutboxOp> _ops = const [];
  bool _loaded = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    widget.engine.status.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _disposed = true;
    widget.engine.status.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final ops = await widget.store.all(widget.accountId);
    if (_disposed) return;
    setState(() {
      _ops = ops;
      _loaded = true;
    });
  }

  Future<void> _syncNow() async {
    // The person asked, so ops that were waiting out a backoff are due now.
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final op in _ops) {
      if (op.state == OpState.pending && op.nextAttemptAt.isAfter(epoch)) {
        op.nextAttemptAt = epoch;
        await widget.store.update(op);
      }
    }
    await widget.engine.run(widget.accountId);
    await _reload();
  }

  Future<void> _retry(OutboxOp op) async {
    op
      ..state = OpState.pending
      ..attempts = 0
      ..lastError = null
      ..nextAttemptAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    await widget.store.update(op);
    await widget.engine.run(widget.accountId);
    await _reload();
  }

  Future<void> _discard(OutboxOp op) async {
    await widget.store.remove(op.id);
    await _reload();
  }

  static String _when(BuildContext context, DateTime t) {
    final local = t.toLocal();
    final m = MaterialLocalizations.of(context);
    return '${m.formatShortDate(local)} ${m.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  String _title(AppLocalizations l, OutboxOp op) {
    final entity = op.entity;
    if (op.kind == QueueableKind.orderNote && entity != null && entity.startsWith('order:')) {
      final id = int.tryParse(entity.substring(6));
      if (id != null) return l.syncOpNoteOnOrder(id);
    }
    return op.kind == QueueableKind.orderNote ? l.syncOpNote : l.syncOpOther;
  }

  String _state(AppLocalizations l, OutboxOp op) => switch (op.state) {
        OpState.pending || OpState.sending => l.noteWaiting,
        OpState.failed => l.noteSendFailed,
        OpState.conflict => l.syncStateConflict,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = widget.engine.status;
    final waiting =
        _ops.where((o) => o.state == OpState.pending || o.state == OpState.sending).length;
    final attention =
        _ops.where((o) => o.state == OpState.failed || o.state == OpState.conflict).length;
    final last = status.lastSuccessAt;
    final offline = status.lastReport?.offline ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(l.syncCenterTitle)),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsetsDirectional.all(16),
              children: [
                Text(l.syncWaitingCount(waiting), key: const ValueKey('sync-waiting')),
                const SizedBox(height: 4),
                Text(l.syncAttentionCount(attention), key: const ValueKey('sync-attention')),
                const SizedBox(height: 4),
                Text(
                  last == null ? l.syncNever : l.syncLastSync(_when(context, last)),
                  key: const ValueKey('sync-last'),
                ),
                if (offline) ...[
                  const SizedBox(height: 4),
                  Text(l.syncOffline, key: const ValueKey('sync-offline')),
                ],
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: status,
                  builder: (context, _) => FilledButton.icon(
                    key: const ValueKey('sync-center-run'),
                    onPressed: status.running ? null : _syncNow,
                    icon: const Icon(Icons.sync, size: 18),
                    label: Text(l.syncNow),
                  ),
                ),
                const SizedBox(height: 16),
                if (_ops.isEmpty)
                  Text(l.syncAllSent, key: const ValueKey('sync-empty'))
                else
                  for (final op in _ops)
                    Card(
                      key: ValueKey('sync-op-${op.id}'),
                      child: ListTile(
                        title: Text(_title(l, op)),
                        subtitle: Text(
                          [
                            _state(l, op),
                            if (op.attempts > 0) l.syncAttempts(op.attempts),
                          ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (op.state == OpState.failed)
                              IconButton(
                                key: ValueKey('sync-retry-${op.id}'),
                                tooltip: l.retry,
                                icon: const Icon(Icons.refresh),
                                onPressed: () => _retry(op),
                              ),
                            if (op.state == OpState.failed || op.state == OpState.conflict)
                              IconButton(
                                key: ValueKey('sync-discard-${op.id}'),
                                tooltip: l.syncDiscard,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _discard(op),
                              ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}
