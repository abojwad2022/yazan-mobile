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

/// The filter chips, in display order: null = all.
const List<String?> ordersFilterStatuses = [
  null,
  'pending',
  'processing',
  'on-hold',
  'completed',
  'cancelled',
  'refunded',
  'failed',
];

class _OrdersListPageState extends State<OrdersListPage> {
  late final TextEditingController _search = TextEditingController(text: widget.repository.query);

  @override
  void initState() {
    super.initState();
    widget.repository.refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final repo = widget.repository;
        if (repo.noAccess) return const NoAccessView();
        final everything = repo.orders;
        if (!repo.loaded && everything.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = repo.filtered;
        final counts = repo.statusCounts;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
              child: TextField(
                key: const ValueKey('orders-search'),
                controller: _search,
                onChanged: repo.setQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l.ordersSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            SingleChildScrollView(
              key: const ValueKey('orders-filter-bar'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final status in ordersFilterStatuses)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        key: ValueKey('orders-filter-${status ?? 'all'}'),
                        label: Text(l.ordersFilterChip(
                          status == null ? l.ordersFilterAll : statusLabel(l, status),
                          counts[status] ?? 0,
                        )),
                        selected: repo.statusFilter == status,
                        onSelected: (_) => repo.setStatus(status),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: repo.refresh,
                child: orders.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsetsDirectional.all(24),
                        children: [
                          if (repo.lastRefreshFailed) StaleBadge(label: l.ordersRefreshFailed),
                          const SizedBox(height: 16),
                          Text(_emptyText(l, repo, everything.isEmpty), textAlign: TextAlign.center),
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
              ),
            ),
          ],
        );
      },
    );
  }

  String _emptyText(AppLocalizations l, OrdersRepository repo, bool cacheEmpty) {
    if (!cacheEmpty) return l.ordersNoMatch;
    return repo.lastRefreshFailed ? l.ordersLoadFailed : l.ordersEmpty;
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
