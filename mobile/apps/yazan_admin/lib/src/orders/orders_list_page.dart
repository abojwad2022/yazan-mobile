import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import 'no_access_view.dart';
import 'order_summary.dart';
import 'orders_format.dart';
import 'orders_repository.dart';

class OrdersListPage extends StatefulWidget {
  const OrdersListPage({super.key, required this.repository, required this.onOpen});

  final OrdersRepository repository;
  final void Function(OrderSummary order) onOpen;

  @override
  State<OrdersListPage> createState() => _OrdersListPageState();
}

class _OrdersListPageState extends State<OrdersListPage> {
  @override
  void initState() {
    super.initState();
    widget.repository.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final repo = widget.repository;
        if (repo.noAccess) return const NoAccessView();
        final orders = repo.orders;
        if (!repo.loaded && orders.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: repo.refresh,
          child: orders.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsetsDirectional.all(24),
                  children: [
                    if (repo.lastRefreshFailed) StaleBadge(label: l.ordersRefreshFailed),
                    const SizedBox(height: 16),
                    Text(
                      repo.lastRefreshFailed ? l.ordersLoadFailed : l.ordersEmpty,
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: orders.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return repo.lastRefreshFailed
                          ? Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: StaleBadge(label: l.ordersRefreshFailed),
                              ),
                            )
                          : const SizedBox.shrink();
                    }
                    return _OrderRow(order: orders[i - 1], onTap: widget.onOpen);
                  },
                ),
        );
      },
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order, required this.onTap});

  final OrderSummary order;
  final void Function(OrderSummary order) onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = order.customerName.isEmpty ? l.guestCustomer : order.customerName;
    return ListTile(
      key: ValueKey('order-${order.id}'),
      onTap: () => onTap(order),
      title: Text(l.orderNumber(order.number)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                label: Text(statusLabel(l, order.status)),
                visualDensity: VisualDensity.compact,
              ),
              Text(l.orderItems(order.itemCount)),
            ],
          ),
        ],
      ),
      trailing: Text(formatMoney(order.total)),
    );
  }
}
