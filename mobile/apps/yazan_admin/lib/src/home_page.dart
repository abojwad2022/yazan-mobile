import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import '../l10n/app_localizations.dart';
import 'orders/order_detail_page.dart';
import 'orders/order_summary.dart';
import 'orders/orders_list_page.dart';
import 'orders/orders_repository.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.client, required this.onSignedOut});

  final YazanApiClient client;
  final VoidCallback onSignedOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final OrdersRepository _orders = OrdersRepository.forClient(widget.client);

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
          load: (id) => widget.client.getJson('/yazan/v1/orders/$id'),
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
