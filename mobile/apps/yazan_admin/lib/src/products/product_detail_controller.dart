import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import 'product_input.dart';
import 'product_permissions.dart';

/// A product body plus its version token (the ETag, quotes stripped).
typedef VersionedProduct = ({Map<String, dynamic> body, String? version});

/// Loads `/yazan/v1/products/{id}` with its version.
typedef VersionedProductLoader = Future<VersionedProduct> Function(int id);

/// Sends `PUT /yazan/v1/products/{id}` with `If-Match` and `Idempotency-Key`.
/// Throws [ApiError] for a server answer; any other exception means "no network".
typedef ProductWriter = Future<Map<String, dynamic>> Function(
  int id,
  Map<String, dynamic> fields, {
  required String version,
  required String idempotencyKey,
});

/// What is being edited. Both are online-only: nothing is ever queued on the phone.
enum ProductEditKind { price, stock }

/// What happened to a price or stock change.
///
/// [notApplied] is a 2xx answer after which the record does not hold the value that was sent
/// (the server dropped the field, for example for a missing permission): the person is told, not
/// shown a success.
enum ProductEditResult { done, offline, busy, conflict, noAccess, failed, notApplied }

/// A 412 on a change: what the person chose against what the server has now.
class ProductConflict {
  const ProductConflict({
    required this.kind,
    required this.mineRegular,
    required this.mineSale,
    required this.mineStock,
    required this.serverRegular,
    required this.serverSale,
    required this.serverStock,
    required this.serverVersion,
  });

  final ProductEditKind kind;

  /// The price the person chose (price edits; empty otherwise).
  final String mineRegular;
  final String mineSale;

  /// The quantity the person chose (stock edits; null otherwise).
  final int? mineStock;
  final String serverRegular;
  final String serverSale;
  final int? serverStock;
  final String? serverVersion;
}

class _Attempt {
  _Attempt(this.kind, this.fields, this.key);

  final ProductEditKind kind;

  /// The exact request body. A retry sends this same map under the same key.
  final Map<String, dynamic> fields;
  final String key;
}

/// State and actions of one product screen. Everything that talks to the network is injected.
///
/// The catalogue feed carries the record's version token. [feedVersion] (with [feedSyncedAt], when
/// that feed was last pulled to its end) lets a write go out without one more read, but only when
/// this screen's own read gave no version and the feed copy is younger than [feedFreshFor]; a
/// stale or missing one is never used and the record is read again right before the write. The
/// token is dropped after any write of this screen (it is outdated by then). It can only save a
/// read, never overwrite someone else's change: the server still checks `If-Match` and answers 412.
///
/// Price and final stock are online-only: a network failure keeps the attempt (same key) for a
/// retry and never queues anything. Every write carries `If-Match` with the version of the record
/// the person is looking at; a stale one (412) opens the conflict screen and writes nothing.
class ProductDetailController extends ChangeNotifier {
  ProductDetailController({
    required this.productId,
    required VersionedProductLoader load,
    required ProductWriter write,
    ProductPermissions permissions = const ProductPermissions.unknown(),
    PermissionsLoader? loadPermissions,
    String Function()? newKey,
    String? feedVersion,
    DateTime? feedSyncedAt,
    DateTime Function()? clock,
    this.feedFreshFor = const Duration(minutes: 2),
  })  : _feedVersion = feedVersion,
        _feedSyncedAt = feedSyncedAt,
        _clock = clock ?? DateTime.now,
        _load = load,
        _write = write,
        _permissions = permissions,
        _loadPermissions = loadPermissions,
        _newKey = newKey ?? YazanApiClient.newIdempotencyKey;

  final int productId;
  final VersionedProductLoader _load;
  final ProductWriter _write;
  final PermissionsLoader? _loadPermissions;
  final String Function() _newKey;

  /// How old the feed's copy of the version may be to be trusted as an `If-Match` base.
  final Duration feedFreshFor;
  final DateTime Function() _clock;
  String? _feedVersion;
  final DateTime? _feedSyncedAt;

  ProductPermissions _permissions;
  Map<String, dynamic>? _detail;
  String? _version;
  bool _loading = true;
  bool _failed = false;
  bool _noAccess = false;
  bool _sending = false;
  bool _disposed = false;
  _Attempt? _attempt;
  ProductConflict? _conflict;
  ProductEditResult? _lastResult;
  String _lastMessage = '';

  Map<String, dynamic>? get detail => _detail;

  /// True when the next write would be based on the feed's version instead of this screen's read.
  bool get usesFeedVersion => (_version == null || _version!.isEmpty) && _freshFeedVersion() != null;

  /// The version the next write is based on: the ETag of the last read. Null before the first read.
  String? get version => _version;

  bool get loading => _loading;
  bool get failed => _failed;

  /// The product itself may not be viewed.
  bool get noAccess => _noAccess;
  bool get sending => _sending;
  ProductPermissions get permissions => _permissions;
  ProductConflict? get conflict => _conflict;

  /// Outcome of the last change, for the inline message; null once it is dismissed.
  ProductEditResult? get lastResult => _lastResult;

  /// The server's message for [ProductEditResult.failed], when it sent one.
  String get lastMessage => _lastMessage;

  /// True when [retry] has an attempt to resend.
  bool get canRetry => _attempt != null;

  // ---- what the loaded record says -------------------------------------------------------------

  String get type => _text('type');
  bool get isVariable => type == 'variable';
  String get regularPrice => plainPrice(_text('regular_price'));
  String get salePrice => plainPrice(_text('sale_price'));
  String get stockStatus => _text('stock_status');
  bool get manageStock => _text('manage_stock') == 'true';

  /// Units on the shelf, or null when the product does not count units.
  int? get stockQuantity {
    final d = _detail;
    return d == null ? null : _intOf(d['stock_quantity']);
  }

  String get featuredUrl {
    final d = _detail;
    final images = d == null ? null : d['images'];
    if (images is Map) return '${images['featured_url'] ?? ''}';
    return '';
  }

  /// Price can be edited here: a simple product, a loaded record, and the permission.
  bool get canEditPrice => _detail != null && !isVariable && _permissions.canEditPrice;

  /// Stock can be edited here: a simple product that counts units, and the permission.
  bool get canEditStock =>
      _detail != null && !isVariable && manageStock && stockQuantity != null && _permissions.canEditStock;

  String _text(String key) {
    final d = _detail;
    if (d == null) return '';
    final v = d[key];
    return v == null ? '' : '$v';
  }

  static int? _intOf(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v == null ? '' : '$v');
  }

  /// The feed's version token when it is recent enough to use, else null.
  String? _freshFeedVersion() {
    final v = _feedVersion;
    final at = _feedSyncedAt;
    if (v == null || v.isEmpty || at == null) return null;
    final age = _clock().difference(at);
    return !age.isNegative && age <= feedFreshFor ? v : null;
  }

  static bool _forbidden(ApiError e) => e.action == ErrorAction.hideFeature || e.status == 403;

  // ---- reading ---------------------------------------------------------------------------------

  Future<void> load() async {
    _loading = true;
    _failed = false;
    _noAccess = false;
    _notify();
    try {
      final r = await _load(productId);
      _detail = r.body;
      _version = r.version;
      if (_version == null || _version!.isEmpty) _version = _freshFeedVersion();
    } on ApiError catch (e) {
      _noAccess = _forbidden(e);
      _failed = true;
    } on Exception {
      _failed = true;
    }
    if (!_permissions.known) {
      final loader = _loadPermissions;
      if (loader != null) {
        try {
          _permissions = ProductPermissions.fromMe(await loader());
        } on Exception {
          // Edits stay off until the permissions can be read.
        }
      }
    }
    _loading = false;
    _notify();
  }

  // ---- price / stock (online-only) -------------------------------------------------------------

  /// Sets the regular price, and the sale price (empty clears it). Both are already validated
  /// decimal strings ("129.50"). Resends the open attempt when it is the same request.
  Future<ProductEditResult> savePrice({required String regular, required String sale}) {
    if (!canEditPrice) return Future<ProductEditResult>.value(ProductEditResult.noAccess);
    return _start(ProductEditKind.price, {'regular_price': regular, 'sale_price': sale});
  }

  /// Sets the stock quantity. `original_stock_quantity` (what this screen last read) lets the
  /// server refuse the write as well when the shelf moved since.
  Future<ProductEditResult> saveStock(int quantity) {
    if (!canEditStock) return Future<ProductEditResult>.value(ProductEditResult.noAccess);
    return _start(ProductEditKind.stock, {
      'stock_quantity': quantity,
      'original_stock_quantity': stockQuantity,
    });
  }

  Future<ProductEditResult> _start(ProductEditKind kind, Map<String, dynamic> fields) {
    final open = _attempt;
    final attempt = open != null && open.kind == kind && mapEquals(open.fields, fields)
        ? open
        : _Attempt(kind, fields, _newKey());
    _attempt = attempt;
    return _send(attempt);
  }

  /// Resends the open attempt with the same Idempotency-Key.
  Future<ProductEditResult> retry() async {
    final open = _attempt;
    if (open == null) return ProductEditResult.failed;
    return _send(open);
  }

  /// Dismisses the inline message and forgets the open attempt.
  void dismiss() {
    _attempt = null;
    _lastResult = null;
    _notify();
  }

  Future<ProductEditResult> _send(_Attempt attempt) async {
    _sending = true;
    _lastResult = null;
    _lastMessage = '';
    _notify();
    final result = await _sendOnce(attempt);
    _lastResult = result == ProductEditResult.conflict ? null : result;
    _sending = false;
    _notify();
    return result;
  }

  Future<ProductEditResult> _sendOnce(_Attempt attempt) async {
    try {
      // A write is based on the version of a record read on this screen, or of a fresh feed copy;
      // with neither the record is read again first.
      var v = _version;
      if (v == null || v.isEmpty) v = _freshFeedVersion();
      if (v == null || v.isEmpty) {
        final r = await _load(productId);
        _detail = r.body;
        _version = r.version;
        v = r.version;
      }
      if (v == null || v.isEmpty) return ProductEditResult.failed;
      final answer = await _write(productId, attempt.fields, version: v, idempotencyKey: attempt.key);
      _attempt = null;
      _feedVersion = null;
      // A write answers without an ETag: read the record again for its new version and the truth.
      var truth = answer;
      try {
        final r = await _load(productId);
        _detail = r.body;
        _version = r.version;
        truth = r.body;
      } on Exception {
        // The change went through; the next write would get a 412 and show the conflict screen.
        _detail = answer;
        _version = null;
      }
      return _took(attempt, truth) ? ProductEditResult.done : ProductEditResult.notApplied;
    } on ApiError catch (e) {
      switch (e.action) {
        case ErrorAction.showConflict:
          return _openConflict(attempt, e);
        case ErrorAction.waitAndRetrySameKey:
          return ProductEditResult.busy;
        default:
          if (_forbidden(e)) {
            _attempt = null;
            return ProductEditResult.noAccess;
          }
          _lastMessage = e.message;
          return ProductEditResult.failed;
      }
    } on Exception {
      // No network. Nothing is queued: the attempt (and its key) waits for "Try again".
      return ProductEditResult.offline;
    }
  }

  /// True when [record] holds what [attempt] asked for.
  bool _took(_Attempt attempt, Map<String, dynamic> record) {
    switch (attempt.kind) {
      case ProductEditKind.price:
        return samePrice('${record['regular_price'] ?? ''}', '${attempt.fields['regular_price']}') &&
            samePrice('${record['sale_price'] ?? ''}', '${attempt.fields['sale_price']}');
      case ProductEditKind.stock:
        return _intOf(record['stock_quantity']) == attempt.fields['stock_quantity'];
    }
  }

  Future<ProductEditResult> _openConflict(_Attempt attempt, ApiError e) async {
    // The record moved on: whatever the feed said is out of date.
    _feedVersion = null;
    try {
      final r = await _load(productId);
      final b = r.body;
      final mine = attempt.fields['stock_quantity'];
      _conflict = ProductConflict(
        kind: attempt.kind,
        mineRegular: '${attempt.fields['regular_price'] ?? ''}',
        mineSale: '${attempt.fields['sale_price'] ?? ''}',
        mineStock: mine is int ? mine : null,
        serverRegular: plainPrice('${b['regular_price'] ?? ''}'),
        serverSale: plainPrice('${b['sale_price'] ?? ''}'),
        serverStock: _intOf(b['stock_quantity']),
        serverVersion: r.version ?? e.current,
      );
      return ProductEditResult.conflict;
    } on Exception {
      return ProductEditResult.offline;
    }
  }

  /// "Keep server version": drop the local choice and show the server's copy.
  Future<void> keepServer() async {
    _conflict = null;
    _attempt = null;
    await load();
  }

  /// "Overwrite with mine": send the same change again against the server's current version.
  ///
  /// This is a new attempt with a new key: the 412 wrote nothing, and the server never finishes
  /// the idempotency record of a request its precondition gate refused. A stock change is based on
  /// the quantity the server holds now, so the server's own stale-stock check lets it through.
  Future<ProductEditResult> overwrite() async {
    final c = _conflict;
    if (c == null) return ProductEditResult.failed;
    _conflict = null;
    final v = c.serverVersion;
    if (v != null && v.isNotEmpty) _version = v;
    final Map<String, dynamic> fields;
    switch (c.kind) {
      case ProductEditKind.price:
        fields = {'regular_price': c.mineRegular, 'sale_price': c.mineSale};
      case ProductEditKind.stock:
        fields = {'stock_quantity': c.mineStock, 'original_stock_quantity': c.serverStock};
    }
    final attempt = _Attempt(c.kind, fields, _newKey());
    _attempt = attempt;
    return _send(attempt);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
