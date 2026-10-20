import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

/// One product category from `GET /sync/terms` (`{id, name, slug, parent, count, image}`).
class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    this.slug = '',
    this.parent = 0,
    this.count = 0,
  });

  /// Null for a record without a usable id.
  static ProductCategory? tryParse(Map<String, dynamic> r) {
    final id = _int(r['id']);
    if (id == null || id <= 0) return null;
    final name = r['name'];
    return ProductCategory(
      id: id,
      name: name is String ? name : '',
      slug: r['slug'] is String ? r['slug'] as String : '',
      parent: _int(r['parent']) ?? 0,
      count: _int(r['count']) ?? 0,
    );
  }

  final int id;
  final String name;
  final String slug;

  /// 0 for a top-level category.
  final int parent;
  final int count;

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// The category tree as the filter shows it: top-level categories and one level of children.
/// Deeper categories are folded into their level-one ancestor, so nothing is lost from filtering.
class CategoryTree {
  CategoryTree(List<ProductCategory> all) {
    final byId = {for (final c in all) c.id: c};
    final tops = <ProductCategory>[];
    final kids = <int, List<ProductCategory>>{};
    final folded = <int, Set<int>>{};

    // The level-one ancestor of [c], or null if the chain is broken or loops.
    int? topOf(ProductCategory c) {
      var cur = c;
      final seen = <int>{};
      while (cur.parent != 0) {
        if (!seen.add(cur.id)) return null;
        final next = byId[cur.parent];
        if (next == null) return null;
        cur = next;
      }
      return cur.id;
    }

    for (final c in all) {
      // A category whose parent is unknown is shown at the top level rather than hidden.
      if (c.parent == 0 || !byId.containsKey(c.parent)) {
        tops.add(c);
      } else {
        final top = topOf(c);
        if (top == null) continue;
        folded.putIfAbsent(top, () => <int>{}).add(c.id);
        if (c.parent == top) kids.putIfAbsent(top, () => []).add(c);
      }
    }
    int byName(ProductCategory a, ProductCategory b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    tops.sort(byName);
    for (final list in kids.values) {
      list.sort(byName);
    }
    topLevel = tops;
    _children = kids;
    _descendants = folded;
  }

  late final List<ProductCategory> topLevel;
  late final Map<int, List<ProductCategory>> _children;
  late final Map<int, Set<int>> _descendants;

  /// The direct children of [topId] (empty when it has none).
  List<ProductCategory> childrenOf(int topId) => _children[topId] ?? const [];

  /// The ids a product may carry to belong under [id]: the category itself plus, for a top-level
  /// one, everything below it.
  Set<int> idsUnder(int id) => {id, ...?_descendants[id]};
}

/// Fetches the category list (normally `GET /yazan-mobile/v1/sync/terms`, public).
typedef CategoryFetch = Future<List<Map<String, dynamic>>> Function();

/// Cached categories: a [FeedStore] (a separate feed from the products, durable in the apps) that
/// is replaced whole by each successful refresh. A failed refresh rethrows and leaves the cache as
/// it was, so the filter keeps working offline.
class CategoryRepository {
  CategoryRepository({required CategoryFetch fetch, FeedStore? store})
      : _fetch = fetch,
        _store = store ?? MemoryFeedStore();

  final CategoryFetch _fetch;
  final FeedStore _store;

  Future<void> refresh() async {
    final rows = await _fetch();
    final usable = [
      for (final r in rows)
        if (ProductCategory.tryParse(r) != null) {...r, 'id': ProductCategory.tryParse(r)!.id},
    ];
    await _store.apply(upserts: usable, deletedIds: const [], cursor: 'terms', initial: true);
  }

  Future<List<ProductCategory>> categories() async {
    final rows = await _store.readAll();
    return [
      for (final r in rows)
        if (ProductCategory.tryParse(r) != null) ProductCategory.tryParse(r)!,
    ];
  }

  Future<CategoryTree> tree() async => CategoryTree(await categories());
}

/// Downloads the category list from the public `sync/terms` route (works signed out).
Future<List<Map<String, dynamic>>> fetchCategories(YazanApiClient client) async {
  final body = await client.getJson('/yazan-mobile/v1/sync/terms', optionalAuth: true);
  final raw = body['categories'];
  return [
    if (raw is List)
      for (final r in raw)
        if (r is Map) Map<String, dynamic>.from(r),
  ];
}
