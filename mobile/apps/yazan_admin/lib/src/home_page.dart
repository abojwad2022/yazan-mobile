import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../l10n/app_localizations.dart';
import 'orders/order_api.dart';
import 'orders/order_detail_page.dart';
import 'orders/order_summary.dart';
import 'orders/orders_list_page.dart';
import 'orders/orders_repository.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.client, required this.onSignedOut, this.outbox});

  final YazanApiClient client;
  final VoidCallback onSignedOut;

  /// The outbox; in memory until the encrypted store lands.
  final OutboxStore? outbox;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// The session does not carry a user id yet, and the queue lives only as long as this signed-in
  /// screen (it is cleared on sign-out), so one key isolates it.
  static const _accountId = 'admin-session';

  late final OrdersRepository _orders = OrdersRepository.forClient(widget.client);
  late final OutboxStore _outbox = widget.outbox ?? MemoryOutboxStore();
  late final SyncEngine _sync = SyncEngine(store: _outbox, send: outboxSender(widget.client));

  @override
  void dispose() {
    _orders.dispose();
    super.dispose();
  }

  void _open(OrderSummary order) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailPage(
          summary: order,
          accountId: _accountId,
          load: orderLoader(widget.client),
          sendStatus: statusSender(widget.client),
          sync: _sync,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          TextButton(
            onPressed: () async {
              await _outbox.clearAccount(_accountId);
              await widget.client.logout();
              widget.onSignedOut();
            },
            child: Text(l.signOut),
          ),
        ],
      ),
      body: OrdersListPage(repository: _orders, onOpen: _open),
    );
  }
}
