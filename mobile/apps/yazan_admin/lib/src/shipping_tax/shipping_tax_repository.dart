import 'package:flutter/foundation.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';

import 'shipping_tax_snapshot.dart';

/// `GET /yazan/v1/shipping/zones` (needs `shipping.view`): every zone with its methods.
typedef ZonesFetch = Future<Map<String, dynamic>> Function();

/// `GET /yazan/v1/tax` (needs `tax.view`): the store-wide tax options and the tax classes.
typedef TaxFetch = Future<Map<String, dynamic>> Function();

/// `GET /yazan/v1/tax/rates?class=<slug>` (needs `tax.view`): one class's rate table.
typedef TaxRatesFetch = Future<Map<String, dynamic>> Function(String taxClass);

ZonesFetch zonesFetch(YazanApiClient client) => () => client.getJson('/yazan/v1/shipping/zones');

TaxFetch taxFetch(YazanApiClient client) => () => client.getJson('/yazan/v1/tax');

TaxRatesFetch taxRatesFetch(YazanApiClient client) =>
    (taxClass) => client.getJson('/yazan/v1/tax/rates', query: {'class': taxClass});

/// Loads the shipping zones and the tax settings, read only, and keeps the last good answer of each
/// for offline use.
///
/// Online first: [refresh] asks the server and replaces each part it got. The two parts are two rows
/// of a [FeedStore] in the encrypted per-account database ([shippingRow], [taxRow]), each with its
/// own "as of" time. A part that fails keeps its cached copy and sets [lastRefreshFailed].
///
/// Access is per part, as on the server: a 403 (`ErrorAction.hideFeature`) on shipping sets
/// [shippingNoAccess] and drops the cached shipping copy, and the same for tax. When both are refused
/// [noAccess] is set, so a revoked permission does not leave settings on the phone.
class ShippingTaxRepository extends ChangeNotifier {
  ShippingTaxRepository({
    required ZonesFetch fetchZones,
    required TaxFetch fetchTax,
    required TaxRatesFetch fetchRates,
    FeedStore? store,
    DateTime Function()? clock,
  })  : _fetchZones = fetchZones,
        _fetchTax = fetchTax,
        _fetchRates = fetchRates,
        _store = store ?? MemoryFeedStore(),
        _clock = clock ?? DateTime.now {
    _ready = _reload();
  }

  /// The production wiring over the API client.
  factory ShippingTaxRepository.forClient(YazanApiClient client, {FeedStore? store}) =>
      ShippingTaxRepository(
        fetchZones: zonesFetch(client),
        fetchTax: taxFetch(client),
        fetchRates: taxRatesFetch(client),
        store: store,
      );

  /// Row ids of the two cached parts.
  static const shippingRow = 1;
  static const taxRow = 2;

  final ZonesFetch _fetchZones;
  final TaxFetch _fetchTax;
  final TaxRatesFetch _fetchRates;
  final FeedStore _store;
  final DateTime Function() _clock;
  late final Future<void> _ready;

  ShippingSnapshot? _shipping;
  TaxSnapshot? _tax;
  bool _loading = false;
  bool _again = false;
  bool _loaded = false;
  bool _failed = false;
  bool _shippingNoAccess = false;
  bool _taxNoAccess = false;
  bool _disposed = false;

  /// Completes once the cached copies have been read.
  Future<void> get ready => _ready;

  ShippingSnapshot? get shipping => _shipping;
  TaxSnapshot? get tax => _tax;
  bool get loading => _loading;

  /// True once a refresh has finished, successfully or not.
  bool get loaded => _loaded;
  bool get lastRefreshFailed => _failed;
  bool get shippingNoAccess => _shippingNoAccess;
  bool get taxNoAccess => _taxNoAccess;

  /// The server refused both parts to this account.
  bool get noAccess => _shippingNoAccess && _taxNoAccess;

  Future<void> _reload() async {
    try {
      for (final r in await _store.readAll()) {
        if (r['id'] == shippingRow) _shipping = ShippingSnapshot.fromJson(r);
        if (r['id'] == taxRow) _tax = TaxSnapshot.fromJson(r);
      }
    } on Exception {
      // An unreadable cache shows as empty; the next refresh fills it.
    }
    _notify();
  }

  Future<void> refresh() async {
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    _notify();
    await _ready;
    do {
      _again = false;
      final shippingFailed = await _refreshShipping();
      final taxFailed = await _refreshTax();
      _failed = shippingFailed || taxFailed;
    } while (_again && !_disposed);
    _loading = false;
    _loaded = true;
    _notify();
  }

  /// Returns true when the zones could not be fetched (the cached copy is kept).
  Future<bool> _refreshShipping() async {
    try {
      final next = ShippingSnapshot.fromServer(await _fetchZones(), fetchedAt: _clock());
      _shipping = next;
      _shippingNoAccess = false;
      await _save(shippingRow, next.toJson());
      return false;
    } on ApiError catch (e) {
      if (e.action != ErrorAction.hideFeature) return true;
      _shippingNoAccess = true;
      _shipping = null;
      await _drop(shippingRow);
      return false;
    } on Exception {
      return true;
    }
  }

  /// Returns true when the tax settings or a rate table could not be fetched.
  Future<bool> _refreshTax() async {
    try {
      final tax = await _fetchTax();
      final classes = TaxSnapshot.classesOf(tax);
      final wanted = [for (final c in classes) if (c.count != 0) c.slug];
      final answers = await Future.wait([for (final slug in wanted) _fetchRates(slug)]);
      final rates = <String, List<dynamic>>{
        for (var i = 0; i < wanted.length; i++)
          wanted[i]: answers[i]['items'] is List ? answers[i]['items'] as List : const [],
      };
      final next = TaxSnapshot.fromServer(tax, rates, fetchedAt: _clock());
      _tax = next;
      _taxNoAccess = false;
      await _save(taxRow, next.toJson());
      return false;
    } on ApiError catch (e) {
      if (e.action != ErrorAction.hideFeature) return true;
      _taxNoAccess = true;
      _tax = null;
      await _drop(taxRow);
      return false;
    } on Exception {
      return true;
    }
  }

  Future<void> _save(int id, Map<String, dynamic> row) async {
    try {
      await _store.apply(
        upserts: [
          {...row, 'id': id},
        ],
        deletedIds: const [],
        cursor: '',
        initial: false,
      );
    } on Exception {
      // A cache that cannot be written only means no offline copy next time.
    }
  }

  Future<void> _drop(int id) async {
    try {
      await _store.apply(upserts: const [], deletedIds: [id], cursor: '', initial: false);
    } on Exception {
      // Nothing more to do for an unwritable cache.
    }
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
