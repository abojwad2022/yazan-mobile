import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import '../dashboard/dashboard_format.dart';
import '../orders/no_access_view.dart';
import '../orders/orders_format.dart' show statusLabel;
import 'reports_repository.dart';
import 'reports_snapshot.dart';
import 'sales_bar_chart.dart';

/// Sales reports: net revenue per day over 7, 30 or 90 days, top products, orders by status and
/// refunds. Read only.
///
/// A section is drawn only when the server gave it to this account. With [showAppBar] the page
/// brings its own title bar, for use as a pushed route; without it the page is a body only.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.repository, this.showAppBar = false});

  final ReportsRepository repository;
  final bool showAppBar;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  @override
  void initState() {
    super.initState();
    widget.repository.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final body = ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) => _content(context, l),
    );
    if (!widget.showAppBar) return body;
    return Scaffold(appBar: AppBar(title: Text(l.reportsTitle)), body: body);
  }

  Widget _content(BuildContext context, AppLocalizations l) {
    final repo = widget.repository;
    if (repo.noAccess) return NoAccessView(body: l.reportsNoAccessBody);
    final snap = repo.snapshot;
    if (snap == null && !repo.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snap == null) {
      return RefreshIndicator(
        onRefresh: repo.refresh,
        child: ListView(
          key: const ValueKey('reports-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.all(24),
          children: [
            _PeriodPicker(repo: repo),
            const SizedBox(height: 16),
            if (repo.lastRefreshFailed) StaleBadge(label: l.ordersRefreshFailed),
            const SizedBox(height: 16),
            Text(l.reportsLoadFailed, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    final sales = snap.sales;
    final counts = snap.statusCounts;
    return RefreshIndicator(
      onRefresh: repo.refresh,
      child: ListView(
        key: const ValueKey('reports-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l.dashboardAsOf(formatAsOf(snap.fetchedAt)),
                key: const ValueKey('reports-asof'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (repo.lastRefreshFailed)
                StaleBadge(key: const ValueKey('reports-stale'), label: l.ordersRefreshFailed),
            ],
          ),
          const SizedBox(height: 8),
          _PeriodPicker(repo: repo),
          const SizedBox(height: 12),
          if (sales != null) ...[
            _Title(l.reportsSales),
            _SalesCard(sales: sales),
            const SizedBox(height: 12),
            _Title(l.reportsTopProducts),
            _TopProducts(sales: sales),
            const SizedBox(height: 12),
          ],
          if (counts != null) ...[
            _Title(l.reportsOrdersByStatus),
            _StatusCounts(counts: counts),
            const SizedBox(height: 12),
          ],
          if (sales != null) ...[
            _Title(l.reportsRefunds),
            _RefundsCard(sales: sales),
          ],
        ],
      ),
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.repo});

  final ReportsRepository repo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        key: const ValueKey('reports-period'),
        showSelectedIcon: false,
        segments: [
          for (final p in ReportsRepository.periods)
            ButtonSegment<int>(
              value: p,
              label: Text(l.dashboardPeriodDays(p), key: ValueKey('reports-period-$p')),
            ),
        ],
        selected: {repo.days},
        onSelectionChanged: (v) => repo.setDays(v.first),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Text(value, style: Theme.of(context).textTheme.titleMedium, textDirection: TextDirection.ltr),
          ],
        ),
      );
}

class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.sales});

  final SalesReport sales;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final hasSales = sales.series.any((d) => d.total > 0);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatAmount(sales.netRevenue, sales.symbol),
              key: const ValueKey('reports-net'),
              style: t.headlineSmall,
              textDirection: TextDirection.ltr,
            ),
            Text(l.dashboardNetRevenue, style: t.bodySmall),
            const SizedBox(height: 12),
            if (hasSales) ...[
              Directionality(
                textDirection: TextDirection.ltr,
                child: SalesBarChart(series: sales.series, semanticsLabel: l.reportsChartLabel),
              ),
              if (sales.series.length > 1)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(sales.series.first.date, style: t.bodySmall),
                      Text(sales.series.last.date, style: t.bodySmall),
                    ],
                  ),
                ),
            ] else
              Text(l.reportsNoSales, key: const ValueKey('reports-no-sales')),
            const Divider(height: 24),
            _Row(key: const ValueKey('reports-orders'), label: l.dashboardOrders, value: '${sales.orders}'),
            _Row(label: l.dashboardItemsSold, value: '${sales.itemsSold}'),
            _Row(label: l.dashboardAverageOrder, value: formatAmount(sales.averageOrder, sales.symbol)),
            _Row(label: l.reportsGrossRevenue, value: formatAmount(sales.grossRevenue, sales.symbol)),
          ],
        ),
      ),
    );
  }
}

class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.sales});

  final SalesReport sales;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (sales.top.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(16),
          child: Text(l.reportsNoSales, key: const ValueKey('reports-no-top')),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < sales.top.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              key: ValueKey('reports-top-${sales.top[i].id}'),
              title: Text(sales.top[i].name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(l.reportsTopProductSold(sales.top[i].qty)),
              trailing: Text(
                formatAmount(sales.top[i].revenue, sales.symbol),
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCounts extends StatelessWidget {
  const _StatusCounts({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            for (final status in ReportsRepository.statuses)
              if (counts.containsKey(status))
                _Row(
                  key: ValueKey('reports-status-$status'),
                  label: statusLabel(l, status),
                  value: '${counts[status]}',
                ),
          ],
        ),
      ),
    );
  }
}

class _RefundsCard extends StatelessWidget {
  const _RefundsCard({required this.sales});

  final SalesReport sales;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(
              key: const ValueKey('reports-refunded'),
              label: l.dashboardRefunded,
              value: formatAmount(sales.refunded, sales.symbol),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 8),
              child: Text(
                l.reportsRefundedOrders(sales.refundedOrders),
                key: const ValueKey('reports-refunded-orders'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
