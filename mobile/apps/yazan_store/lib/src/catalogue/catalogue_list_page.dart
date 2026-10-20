import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import 'catalogue_repository.dart';
import 'category_repository.dart';
import 'price_text.dart';
import 'product.dart';
import 'product_page.dart';

/// Grid of products from the local cache, refreshed on open and by pull-to-refresh.
class CatalogueListPage extends StatefulWidget {
  const CatalogueListPage({super.key, required this.repository, this.categories});

  final CatalogueRepository repository;

  /// Public categories for the browse chips; without it the list has no category filter.
  final CategoryRepository? categories;

  @override
  State<CatalogueListPage> createState() => _CatalogueListPageState();
}

class _CatalogueListPageState extends State<CatalogueListPage> {
  List<Product> _products = const [];
  CategoryTree _tree = CategoryTree(const []);
  bool _stale = false;

  /// The chosen level-one category, and a child of it; null means "all".
  int? _top;
  int? _child;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await widget.repository.products();
    final tree = await _readTree();
    if (!mounted) return;
    setState(() {
      _products = cached;
      _tree = tree;
    });
    await _refresh();
  }

  Future<CategoryTree> _readTree() async {
    final repo = widget.categories;
    if (repo == null) return _tree;
    try {
      return await repo.tree();
    } catch (_) {
      return _tree;
    }
  }

  Future<void> _refresh() async {
    var failed = false;
    try {
      await widget.repository.refresh();
    } catch (_) {
      failed = true;
    }
    // Categories are a nicety: a failure keeps the cached ones and raises no badge of its own.
    try {
      await widget.categories?.refresh();
    } catch (_) {
      // Keeps the saved categories.
    }
    final fresh = await widget.repository.products();
    final tree = await _readTree();
    if (!mounted) return;
    setState(() {
      _products = fresh;
      _tree = tree;
      _stale = failed;
      // A category that no longer exists must not leave the list filtered to nothing.
      final known = {for (final c in tree.topLevel) c.id};
      if (_top != null && _child != null && !tree.childrenOf(_top!).any((c) => c.id == _child)) {
        _child = null;
      }
      if (_top != null && !known.contains(_top)) {
        _top = null;
        _child = null;
      }
    });
  }

  /// Products in the chosen category (a top-level one includes its children) whose name matches
  /// the search text.
  List<Product> get _visible {
    final selected = _child ?? _top;
    final ids = selected == null ? null : _tree.idsUnder(selected);
    final q = _query.trim().toLowerCase();
    return [
      for (final p in _products)
        if ((ids == null || p.categories.any(ids.contains)) &&
            (q.isEmpty || p.name.toLowerCase().contains(q)))
          p,
    ];
  }

  Widget _searchField(AppLocalizations l) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 12, end: 12, top: 8),
        child: TextField(
          key: const ValueKey<String>('catalogue-search'),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l.searchHint,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      );

  Widget _chipRow(List<Widget> chips) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 4),
          children: [
            for (final c in chips)
              Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: c),
          ],
        ),
      );

  /// "All" plus the top-level categories, and below it the chosen one's children (one level).
  List<Widget> _categoryRows(AppLocalizations l) {
    if (_tree.topLevel.isEmpty) return const [];
    final children = _top == null ? const <ProductCategory>[] : _tree.childrenOf(_top!);
    return [
      _chipRow([
        ChoiceChip(
          key: const ValueKey<String>('category-all'),
          label: Text(l.allCategories),
          selected: _top == null,
          onSelected: (_) => setState(() {
            _top = null;
            _child = null;
          }),
        ),
        for (final c in _tree.topLevel)
          ChoiceChip(
            key: ValueKey<String>('category-${c.id}'),
            label: Text(c.name),
            selected: _top == c.id,
            onSelected: (_) => setState(() {
              _top = c.id;
              _child = null;
            }),
          ),
      ]),
      if (children.isNotEmpty)
        _chipRow([
          ChoiceChip(
            key: const ValueKey<String>('category-sub-all'),
            label: Text(l.allInCategory),
            selected: _child == null,
            onSelected: (_) => setState(() => _child = null),
          ),
          for (final c in children)
            ChoiceChip(
              key: ValueKey<String>('category-${c.id}'),
              label: Text(c.name),
              selected: _child == c.id,
              onSelected: (_) => setState(() => _child = c.id),
            ),
        ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final visible = _visible;
    return Column(
      children: [
        _searchField(l),
        ..._categoryRows(l),
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
            child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.all(32),
                        child: Center(
                          child: Text(
                            _products.isEmpty ? l.emptyCatalogue : l.noMatchingProducts,
                            textAlign: TextAlign.center,
                          ),
                        ),
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
                    itemCount: visible.length,
                    itemBuilder: (context, i) => _ProductCard(product: visible[i]),
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
