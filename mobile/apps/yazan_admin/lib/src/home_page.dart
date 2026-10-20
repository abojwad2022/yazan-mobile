import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../l10n/app_localizations.dart';
import 'orders/order_api.dart';
import 'orders/order_detail_page.dart';
import 'orders/order_summary.dart';
import 'orders/orders_list_page.dart';
import 'orders/orders_repository.dart';
import 'products/product_api.dart';
import 'products/product_detail_page.dart';
import 'products/product_summary.dart';
import 'products/products_list_page.dart';
import 'products/products_repository.dart';

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
  late final ProductsRepository _products = ProductsRepository.forClient(widget.client);
  late final OutboxStore _outbox = widget.outbox ?? MemoryOutboxStore();
  late final SyncEngine _sync = SyncEngine(store: _outbox, send: outboxSender(widget.client));

  /// 0 = orders, 1 = products. The products page is built the first time it is opened, so a
  /// signed-in start costs one feed pull, not two.
  int _tab = 0;
  bool _productsOpened = false;

  @override
  void dispose() {
    _orders.dispose();
    _products.dispose();
    super.dispose();
  }

  void _openProduct(ProductSummary product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailPage(
          summary: product,
          load: productLoader(widget.client),
          write: productWriter(widget.client),
          permissions: _products.permissions,
          loadPermissions: permissionsLoader(widget.client),
        ),
      ),
    );
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
      body: IndexedStack(
        index: _tab,
        children: [
          OrdersListPage(repository: _orders, onOpen: _open),
          if (_productsOpened)
            ProductsListPage(repository: _products, onOpen: _openProduct)
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          if (i == 1) _productsOpened = true;
        }),
        destinations: [
          NavigationDestination(
            key: const ValueKey('tab-orders'),
            icon: const Icon(Icons.receipt_long_outlined),
            label: l.ordersTitle,
          ),
          NavigationDestination(
            key: const ValueKey('tab-products'),
            icon: const Icon(Icons.diamond_outlined),
            label: l.productsTitle,
          ),
        ],
      ),
    );
  }
}
