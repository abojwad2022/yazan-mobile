import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import '../orders/no_access_view.dart';
import 'product_summary.dart';
import 'products_format.dart';
import 'products_repository.dart';

/// The catalogue as the phone last saw it: search by name or SKU, stock at a glance. It reads the
/// local mirror first, so it works offline; pulling down fetches only what changed.
class ProductsListPage extends StatefulWidget {
  const ProductsListPage({super.key, required this.repository, required this.onOpen});

  final ProductsRepository repository;
  final void Function(ProductSummary product) onOpen;

  @override
  State<ProductsListPage> createState() => _ProductsListPageState();
}

class _ProductsListPageState extends State<ProductsListPage> {
  final TextEditingController _search = TextEditingController();

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
        if (repo.noAccess) return NoAccessView(body: l.noAccessProductsBody);
        final everything = repo.all;
        if (!repo.loaded && everything.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final shown = repo.products;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
              child: TextField(
                key: const ValueKey('product-search'),
                controller: _search,
                onChanged: repo.setQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l.productsSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: repo.refresh,
                child: shown.isEmpty
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
                        itemCount: shown.length + 1,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return repo.lastRefreshFailed
                                ? Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
                                    child: Align(
                                      alignment: AlignmentDirectional.centerStart,
                                      child: StaleBadge(label: l.ordersRefreshFailed),
                                    ),
                                  )
                                : const SizedBox.shrink();
                          }
                          return _ProductRow(product: shown[i - 1], onTap: widget.onOpen);
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _emptyText(AppLocalizations l, ProductsRepository repo, bool cacheEmpty) {
    if (!cacheEmpty) return l.productsNoMatch(repo.query.trim());
    return repo.lastRefreshFailed ? l.productsLoadFailed : l.productsEmpty;
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onTap});

  final ProductSummary product;
  final void Function(ProductSummary product) onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final stock = stockLabel(l, product);
    return ListTile(
      key: ValueKey('product-${product.id}'),
      onTap: () => onTap(product),
      leading: _Thumb(url: product.thumbUrl),
      title: Text(product.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (product.sku.isNotEmpty) Text(l.productSku(product.sku), style: t.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (stock.isNotEmpty)
                Chip(
                  key: ValueKey('stock-${product.id}'),
                  label: Text(stock),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
      trailing: Text(priceText(product.price, product.currency)),
    );
  }
}

/// A small product picture. Only the thumbnail size is fetched (Data Saver friendly); a missing or
/// broken picture shows a plain icon.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    final placeholder = SizedBox(
      width: size,
      height: size,
      child: Icon(Icons.diamond_outlined, color: Theme.of(context).disabledColor),
    );
    if (url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 144,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}
