import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import '../dashboard/dashboard_format.dart';
import '../orders/no_access_view.dart';
import 'inventory_repository.dart';
import 'stock_snapshot.dart';

/// Out-of-stock and low-stock products from the stock report, with a search box. Read only.
///
/// Tapping a row shows the quantity and SKU in a sheet. Changing a quantity is the products
/// screen's job, so the sheet only offers a link there when [onOpenProduct] is given. With
/// [showAppBar] the page brings its own title bar, for use as a pushed route.
class InventoryPage extends StatefulWidget {
  const InventoryPage({
    super.key,
    required this.repository,
    this.onOpenProduct,
    this.showAppBar = false,
  });

  final InventoryRepository repository;

  /// Called with the product id when the person asks to open the product from the sheet.
  final void Function(int id)? onOpenProduct;
  final bool showAppBar;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String _query = '';

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
    return Scaffold(appBar: AppBar(title: Text(l.inventoryTitle)), body: body);
  }

  Widget _content(BuildContext context, AppLocalizations l) {
    final repo = widget.repository;
    if (repo.noAccess) return NoAccessView(body: l.inventoryNoAccessBody);
    final snap = repo.snapshot;
    if (snap == null && !repo.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snap == null) {
      return RefreshIndicator(
        onRefresh: repo.refresh,
        child: ListView(
          key: const ValueKey('inventory-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.all(24),
          children: [
            if (repo.lastRefreshFailed) StaleBadge(label: l.ordersRefreshFailed),
            const SizedBox(height: 16),
            Text(l.inventoryLoadFailed, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final q = _query.trim().toLowerCase();
    final out = [for (final r in snap.outOfStock) if (r.matches(q)) r];
    final low = [for (final r in snap.lowStock) if (r.matches(q)) r];
    final limit = snap.lowThreshold;
    final items = <Widget>[
      if (out.isNotEmpty) ...[
        _Header(l.inventoryOutOfStock(out.length), key: const ValueKey('inventory-out-header')),
        for (final r in out) _StockTile(row: r, onTap: () => _show(r)),
      ],
      if (low.isNotEmpty) ...[
        _Header(
          limit == null
              ? l.inventoryLowStockNoLimit(low.length)
              : l.inventoryLowStock(isolate('≤ $limit'), low.length),
          key: const ValueKey('inventory-low-header'),
        ),
        for (final r in low) _StockTile(row: r, onTap: () => _show(r)),
      ],
      if (out.isEmpty && low.isEmpty)
        Padding(
          padding: const EdgeInsetsDirectional.all(24),
          child: Text(
            snap.isEmpty ? l.inventoryEmpty : l.inventoryNoMatch,
            key: const ValueKey('inventory-empty'),
            textAlign: TextAlign.center,
          ),
        ),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l.dashboardAsOf(formatAsOf(snap.fetchedAt)),
                    key: const ValueKey('inventory-asof'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (repo.lastRefreshFailed)
                    StaleBadge(key: const ValueKey('inventory-stale'), label: l.ordersRefreshFailed),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('inventory-search'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l.inventorySearchHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: repo.refresh,
            child: ListView(
              key: const ValueKey('inventory-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
              children: items,
            ),
          ),
        ),
      ],
    );
  }

  void _show(StockRow row) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) {
        final l = AppLocalizations.of(sheet);
        final t = Theme.of(sheet).textTheme;
        final open = widget.onOpenProduct;
        return SafeArea(
          child: Padding(
            key: const ValueKey('inventory-detail'),
            padding: const EdgeInsetsDirectional.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.name, style: t.titleMedium),
                const SizedBox(height: 8),
                if (row.qty != null)
                  Text(
                    l.inventoryQuantity(row.qty!),
                    key: const ValueKey('inventory-detail-qty'),
                    style: t.headlineSmall,
                  )
                else
                  Text(l.inventoryQuantityUnknown, key: const ValueKey('inventory-detail-qty')),
                if (row.sku.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(l.inventorySku(isolate(row.sku)), key: const ValueKey('inventory-detail-sku')),
                ],
                if (open != null) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('inventory-open-product'),
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      open(row.id);
                    },
                    child: Text(l.inventoryOpenProduct),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(top: 12, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _StockTile extends StatelessWidget {
  const _StockTile({required this.row, required this.onTap});

  final StockRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      child: ListTile(
        key: ValueKey('inventory-row-${row.id}'),
        onTap: onTap,
        title: Text(row.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: row.sku.isEmpty ? null : Text(row.sku, textDirection: TextDirection.ltr),
        trailing: Text(
          row.qty == null ? '-' : '${row.qty}',
          style: Theme.of(context).textTheme.titleLarge,
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}
