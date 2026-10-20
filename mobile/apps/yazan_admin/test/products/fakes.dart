import 'package:yazan_admin/src/products/product_detail_controller.dart';

/// One recorded product write.
class ProductWrite {
  ProductWrite(this.fields, this.version, this.key);

  final Map<String, dynamic> fields;
  final String version;
  final String key;
}

/// An in-memory stand-in for the product endpoints. No network anywhere.
class FakeProductServer {
  String type = 'simple';
  String name = 'Agate Ring';
  String sku = 'YZ-100';
  String regular = '120.00';
  String sale = '';
  bool manageStock = true;
  int? stock = 3;
  String stockStatus = 'instock';
  String? version = 'v1';

  /// When set, `load` throws it.
  Exception? loadError;

  /// Thrown by the next writes, in order; `null` means "accept".
  final List<Exception?> writeFailures = [];
  final List<ProductWrite> writes = [];

  /// A server that answers 200 but ignores the price fields (for example a missing permission).
  bool ignorePrice = false;
  int loads = 0;
  int _versions = 1;

  Map<String, dynamic> body() => {
        'id': 7,
        'name': name,
        'sku': sku,
        'type': type,
        'status': 'publish',
        'regular_price': regular,
        'sale_price': sale,
        'manage_stock': manageStock,
        'stock_quantity': stock,
        'stock_status': stockStatus,
        'images': {'featured': 0, 'featured_url': ''},
      };

  Future<VersionedProduct> load(int id) async {
    loads++;
    final err = loadError;
    if (err != null) throw err;
    return (body: body(), version: version);
  }

  Future<Map<String, dynamic>> write(
    int id,
    Map<String, dynamic> fields, {
    required String version,
    required String idempotencyKey,
  }) async {
    writes.add(ProductWrite(Map<String, dynamic>.from(fields), version, idempotencyKey));
    final failure = writeFailures.isEmpty ? null : writeFailures.removeAt(0);
    if (failure != null) throw failure;
    if (fields.containsKey('regular_price') && !ignorePrice) {
      regular = '${fields['regular_price']}';
      sale = '${fields['sale_price'] ?? ''}';
    }
    if (fields.containsKey('stock_quantity')) {
      final q = fields['stock_quantity'] as int;
      stock = q;
      stockStatus = q > 0 ? 'instock' : 'outofstock';
    }
    _versions++;
    this.version = 'v$_versions-after';
    return body();
  }

  /// The `/me` answer for a staff member holding [slugs].
  static Map<String, dynamic> me(List<String> slugs) => {
        'id': 1,
        'scope': 'admin',
        'permissions': {for (final s in slugs) s: true},
      };
}

/// All four product permissions the quick edits need.
const List<String> allProductPermissions = [
  'products.view',
  'products.edit',
  'products.change_price',
  'products.change_stock',
];
