import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import '../orders/no_access_view.dart';
import '../orders/orders_format.dart' show statusLabel;
import 'dashboard_format.dart';
import 'dashboard_repository.dart';
import 'dashboard_snapshot.dart';

/// The staff member's home: sales, what needs attention, and the newest orders.
///
/// Read only. Every card is drawn only when the server gave its figures (a section the account may
/// not read is left out of the answer). Tapping a card opens the tab it belongs to through
/// [onOpenOrders] / [onOpenProducts]; [onOpenOrders] also receives the order status the card is
/// about (`processing`, `on-hold`) so a list that can filter by status may do so.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.repository,
    required this.onOpenOrders,
    required this.onOpenProducts,
  });

  final DashboardRepository repository;
  final void Function(String? status) onOpenOrders;
  final VoidCallback onOpenProducts;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    widget.repository.refresh();
  }

  void _openAlerts() {
    widget.repository.acknowledgeAlerts();
    widget.onOpenOrders(null);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final repo = widget.repository;
        if (repo.noAccess) return NoAccessView(body: l.noAccessDashboardBody);
        final snap = repo.snapshot;
        if (snap == null && !repo.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap == null) {
          return RefreshIndicator(
            onRefresh: repo.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsetsDirectional.all(24),
              children: [
                if (repo.lastRefreshFailed) StaleBadge(label: l.ordersRefreshFailed),
                const SizedBox(height: 16),
                Text(l.dashboardLoadFailed, textAlign: TextAlign.center),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: repo.refresh,
          child: ListView(
            key: const ValueKey('dash-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsetsDirectional.all(16),
            children: [
              _Header(repo: repo, snapshot: snap),
              const SizedBox(height: 12),
              if (snap.alerts != null) ...[
                _AlertCard(alert: snap.alerts!, onTap: _openAlerts),
                const SizedBox(height: 12),
              ],
              ..._attention(l, snap),
              if (snap.sales != null) ...[
                _SectionTitle(l.dashboardSales),
                _SalesCard(sales: snap.sales!, days: snap.days),
                const SizedBox(height: 12),
              ],
              if (snap.recentOrders != null && snap.recentOrders!.isNotEmpty) ...[
                _SectionTitle(l.dashboardRecentOrders),
                _RecentOrders(
                  orders: snap.recentOrders!,
                  onTap: () => widget.onOpenOrders(null),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _attention(AppLocalizations l, DashboardSnapshot s) {
    final tiles = <Widget>[
      if (s.processing != null)
        _CountTile(
          key: const ValueKey('dash-processing'),
          icon: Icons.inventory_2_outlined,
          label: l.dashboardProcessing,
          count: s.processing!,
          onTap: () => widget.onOpenOrders('processing'),
        ),
      if (s.onHold != null)
        _CountTile(
          key: const ValueKey('dash-onhold'),
          icon: Icons.pause_circle_outline,
          label: l.dashboardOnHold,
          count: s.onHold!,
          onTap: () => widget.onOpenOrders('on-hold'),
        ),
      if (s.outOfStock != null)
        _CountTile(
          key: const ValueKey('dash-outofstock'),
          icon: Icons.remove_shopping_cart_outlined,
          label: l.dashboardOutOfStock,
          count: s.outOfStock!,
          onTap: widget.onOpenProducts,
        ),
      if (s.lowStock != null)
        _CountTile(
          key: const ValueKey('dash-lowstock'),
          icon: Icons.warning_amber_outlined,
          label: s.lowThreshold == null
              ? l.dashboardLowStockNoLimit
              : l.dashboardLowStock(isolate('≤ ${s.lowThreshold}')),
          count: s.lowStock!,
          onTap: widget.onOpenProducts,
        ),
    ];
    if (tiles.isEmpty) return const [];
    return [
      _SectionTitle(l.dashboardNeedsAttention),
      ...tiles,
      const SizedBox(height: 12),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.repo, required this.snapshot});

  final DashboardRepository repo;
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l.dashboardAsOf(formatAsOf(snapshot.fetchedAt)),
              key: const ValueKey('dash-asof'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (repo.lastRefreshFailed)
              StaleBadge(key: const ValueKey('dash-stale'), label: l.ordersRefreshFailed),
          ],
        ),
        if (snapshot.sales != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final p in DashboardRepository.periods)
                  ButtonSegment<int>(value: p, label: Text(l.dashboardPeriodDays(p))),
              ],
              selected: {repo.days},
              onSelectionChanged: (v) => repo.setDays(v.first),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Text('$count', style: Theme.of(context).textTheme.titleLarge),
        onTap: onTap,
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onTap});

  final NewOrdersAlert alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('dash-alerts'),
      color: scheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.notifications_active_outlined, color: scheme.onSecondaryContainer),
        title: Text(
          l.dashboardAlertTitle(alert.count),
          style: TextStyle(color: scheme.onSecondaryContainer),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final o in alert.orders.take(3))
              Text(
                '${l.orderNumber(o.number)}  ${o.customer.isEmpty ? l.guestCustomer : o.customer}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            Text(l.dashboardAlertHint, style: TextStyle(color: scheme.onSecondaryContainer)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.sales, required this.days});

  final SalesSummary sales;
  final int days;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final vs = l.dashboardVsPrevious(days);
    final today = sales.todayRevenue;
    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (today != null) ...[
              Text(l.dashboardToday(isolate(sales.rangeTo)), style: t.labelLarge),
              const SizedBox(height: 4),
              Text(
                formatSum(today, sales.decimals, sales.symbol),
                key: const ValueKey('dash-today'),
                style: t.headlineSmall,
                textDirection: TextDirection.ltr,
              ),
              if (sales.todayOrders != null)
                Text(
                  l.dashboardOrdersCount(sales.todayOrders!),
                  key: const ValueKey('dash-today-orders'),
                ),
              const Divider(height: 24),
            ],
            _MetricRow(
              key: const ValueKey('dash-net'),
              label: l.dashboardNetRevenue,
              value: formatAmount(sales.netRevenue, sales.symbol),
              delta: sales.revenueDelta,
              deltaLabel: vs,
            ),
            _MetricRow(
              key: const ValueKey('dash-orders'),
              label: l.dashboardOrders,
              value: '${sales.orders}',
              delta: sales.ordersDelta,
              deltaLabel: vs,
            ),
            _MetricRow(
              label: l.dashboardAverageOrder,
              value: formatAmount(sales.averageOrder, sales.symbol),
            ),
            _MetricRow(label: l.dashboardItemsSold, value: '${sales.itemsSold}'),
            _MetricRow(
              label: l.dashboardRefunded,
              value: formatAmount(sales.refunded, sales.symbol),
            ),
            if (sales.rangeFrom.isNotEmpty && sales.rangeTo.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                isolate('${sales.rangeFrom} → ${sales.rangeTo}'),
                style: t.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.deltaLabel,
  });

  final String label;
  final String value;
  final double? delta;
  final String? deltaLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = delta;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: t.titleMedium, textDirection: TextDirection.ltr),
                if (d != null)
                  Text(
                    '${isolate(formatDelta(d))} ${deltaLabel ?? ''}'.trim(),
                    style: t.bodySmall,
                    textAlign: TextAlign.end,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({required this.orders, required this.onTap});

  final List<RecentOrder> orders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < orders.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              key: ValueKey('dash-recent-${orders[i].id}'),
              onTap: onTap,
              title: Text(l.orderNumber(orders[i].number)),
              subtitle: Text(
                '${orders[i].customer.isEmpty ? l.guestCustomer : orders[i].customer}'
                ' · ${statusLabel(l, orders[i].status)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(orders[i].total, textDirection: TextDirection.ltr),
            ),
          ],
        ],
      ),
    );
  }
}
