import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import 'catalogue_repository.dart';
import 'price_text.dart';
import 'product.dart';
import 'product_page.dart';

/// Grid of products from the local cache, refreshed on open and by pull-to-refresh.
class CatalogueListPage extends StatefulWidget {
  const CatalogueListPage({super.key, required this.repository});

  final CatalogueRepository repository;

  @override
  State<CatalogueListPage> createState() => _CatalogueListPageState();
}

class _CatalogueListPageState extends State<CatalogueListPage> {
  List<Product> _products = const [];
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await widget.repository.products();
    if (!mounted) return;
    setState(() => _products = cached);
    await _refresh();
  }

  Future<void> _refresh() async {
    var failed = false;
    try {
      await widget.repository.refresh();
    } catch (_) {
      failed = true;
    }
    final fresh = await widget.repository.products();
    if (!mounted) return;
    setState(() {
      _products = fresh;
      _stale = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        if (_stale)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, end: 16, top: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: StaleBadge(label: l.staleBadge),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _products.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.all(32),
                        child: Center(child: Text(l.emptyCatalogue, textAlign: TextAlign.center)),
                      ),
                    ],
                  )
                : GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsetsDirectional.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.68,
                    ),
                    itemCount: _products.length,
                    itemBuilder: (context, i) => _ProductCard(product: _products[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ProductPage(product: product)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: ProductImageView(url: product.thumbUrl),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  if (product.isSoldOut)
                    Text(
                      l.soldOut,
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.error),
                    )
                  else
                    PriceText(product: product),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
