import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import '../l10n/app_localizations.dart';
import 'customers/customer_api.dart';
import 'customers/customer_detail_page.dart';
import 'customers/customer_summary.dart';
import 'customers/customers_list_page.dart';
import 'customers/customers_repository.dart';
import 'dashboard/dashboard_page.dart';
import 'dashboard/dashboard_repository.dart';
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
import 'storage/admin_stores.dart';
import 'sync/observed_sync_engine.dart';
import 'sync/sync_center_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.client,
    required this.onSignedOut,
    this.stores,
    this.onSessionEnded,
  });

  final YazanApiClient client;

  /// Called after a deliberate sign-out, once the local data is wiped and the server session ended.
  final VoidCallback onSignedOut;

  /// The signed-in staff member's feed mirrors and outbox: encrypted and durable in the app,
  /// memory in tests (the default).
  final AdminStores? stores;

  /// Called when a sync run finds the server session dead (the app shell then wipes and signs out).
  final VoidCallback? onSessionEnded;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AdminStores _stores = widget.stores ?? MemoryAdminStores();

  /// The staff account every cached row and queued op below belongs to.
  late final String _accountId = _stores.accountId;

  late final OrdersRepository _orders =
      OrdersRepository.forClient(widget.client, store: _stores.feed(AdminFeeds.orders));
  late final ProductsRepository _products =
      ProductsRepository.forClient(widget.client, store: _stores.feed(AdminFeeds.products));
  /// The home tab: one snapshot row in the encrypted store (feed name 'dashboard'), wiped with the
  /// rest of the account's data.
  late final DashboardRepository _dashboard =
      DashboardRepository.forClient(widget.client, store: _stores.feed(AdminFeeds.dashboard));
  late final OutboxStore _outbox = _stores.outbox;
  late final ObservedSyncEngine _sync = ObservedSyncEngine(
    store: _outbox,
    send: outboxSender(widget.client),
    onSessionEnded: widget.onSessionEnded,
  );

  /// Customers hold personal data: stored encrypted and per account, and wiped on sign-out,
  /// revoked session, or when the server stops showing them to this account.
  late final CustomersRepository _customers =
      CustomersRepository.forClient(widget.client, store: _stores.feed(AdminFeeds.customers));

  /// 0 = dashboard, 1 = orders, 2 = products, 3 = customers. The orders, products and customers
  /// pages are built the first time they are opened, so a signed-in start costs the dashboard's
  /// requests, not three feed pulls.
  int _tab = 0;
  bool _ordersOpened = false;
  bool _productsOpened = false;
  bool _customersOpened = false;

  void _goTo(int i) => setState(() {
        _tab = i;
        if (i == 1) _ordersOpened = true;
        if (i == 2) _productsOpened = true;
        if (i == 3) _customersOpened = true;
        if (i == 0) {
          // Coming back to the home tab: its figures may have changed while orders were handled.
          final shown = _dashboard.snapshot;
          if (shown == null || DateTime.now().difference(shown.fetchedAt) > const Duration(minutes: 1)) {
            _dashboard.refresh();
          }
        }
      });

  @override
  void initState() {
    super.initState();
    // When the server stops showing a feed to this account, its cached rows are deleted at once.
    _purgeOnNoAccess(_orders, () => _orders.noAccess, _orders.purge);
    _purgeOnNoAccess(_products, () => _products.noAccess, _products.purge);
    _purgeOnNoAccess(_customers, () => _customers.noAccess, _customers.purge);
  }

  void _purgeOnNoAccess(ChangeNotifier repo, bool Function() noAccess, Future<void> Function() purge) {
    var purged = false;
    repo.addListener(() {
      if (!noAccess()) {
        purged = false;
      } else if (!purged) {
        purged = true;
        purge();
      }
    });
  }

  Future<void> _signOut() async {
    final l = AppLocalizations.of(context);
    final unsent = (await _outbox.all(_accountId)).length;
    if (unsent > 0) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(l.signOutUnsentTitle),
          content: Text(l.signOutUnsentBody(unsent)),
          actions: [
            TextButton(
              key: const ValueKey('sign-out-cancel'),
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              key: const ValueKey('sign-out-anyway'),
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(l.signOutAnyway),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await _stores.wipe();
    } catch (_) {
      // Never trap someone in the app. The shell keeps the account id and retries the wipe.
    }
    await widget.client.logout();
    widget.onSignedOut();
  }

  void _openSyncCenter() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SyncCenterPage(accountId: _accountId, store: _outbox, engine: _sync),
      ),
    );
  }

  @override
  void dispose() {
    _dashboard.dispose();
    _orders.dispose();
    _products.dispose();
    _customers.dispose();
    super.dispose();
  }

  void _openCustomer(CustomerSummary customer) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerDetailPage(
          summary: customer,
          load: customerLoader(widget.client),
          permissions: _customers.permissions,
        ),
      ),
    );
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
          IconButton(
            key: const ValueKey('open-sync-center'),
            tooltip: l.syncCenterOpen,
            icon: const Icon(Icons.sync),
            onPressed: _openSyncCenter,
          ),
          TextButton(onPressed: _signOut, child: Text(l.signOut)),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          DashboardPage(
            repository: _dashboard,
            // The orders list has no status filter yet, so a card opens the whole tab.
            onOpenOrders: (_) => _goTo(1),
            onOpenProducts: () => _goTo(2),
          ),
          if (_ordersOpened)
            OrdersListPage(repository: _orders, onOpen: _open)
          else
            const SizedBox.shrink(),
          if (_productsOpened)
            ProductsListPage(repository: _products, onOpen: _openProduct)
          else
            const SizedBox.shrink(),
          if (_customersOpened)
            CustomersListPage(repository: _customers, onOpen: _openCustomer)
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _goTo,
        destinations: [
          NavigationDestination(
            key: const ValueKey('tab-dashboard'),
            icon: const Icon(Icons.dashboard_outlined),
            label: l.dashboardTitle,
          ),
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
          NavigationDestination(
            key: const ValueKey('tab-customers'),
            icon: const Icon(Icons.people_outline),
            label: l.customersTitle,
          ),
        ],
      ),
    );
  }
}
