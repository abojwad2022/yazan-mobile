import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../orders/conflict_page.dart';
import '../orders/no_access_view.dart';
import 'product_detail_controller.dart';
import 'product_edit_dialogs.dart';
import 'product_input.dart';
import 'product_permissions.dart';
import 'product_summary.dart';
import 'products_format.dart';

enum _ConflictChoice { keepServer, overwrite }

/// Product detail with two online-only quick edits: price and stock quantity. Each one asks the
/// person to confirm, then sends one request with `If-Match` and an `Idempotency-Key`. Nothing is
/// queued on the phone; a 412 opens the conflict screen.
class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({
    super.key,
    required this.summary,
    required this.load,
    required this.write,
    this.permissions = const ProductPermissions.unknown(),
    this.loadPermissions,
    this.newKey,
    this.feedSyncedAt,
  });

  final ProductSummary summary;
  final VersionedProductLoader load;
  final ProductWriter write;

  /// What the list already learned; checked again on this screen when still unknown.
  final ProductPermissions permissions;
  final PermissionsLoader? loadPermissions;

  /// When the catalogue feed behind [summary] was last pulled to its end (null: unknown). With
  /// `summary.version` it lets an edit skip a read when this screen's own read gave no version.
  final DateTime? feedSyncedAt;

  /// Key factory for tests; defaults to `YazanApiClient.newIdempotencyKey`.
  final String Function()? newKey;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late final ProductDetailController _c = ProductDetailController(
    productId: widget.summary.id,
    load: widget.load,
    write: widget.write,
    permissions: widget.permissions,
    loadPermissions: widget.loadPermissions,
    newKey: widget.newKey,
    feedVersion: widget.summary.version,
    feedSyncedAt: widget.feedSyncedAt,
  );

  @override
  void initState() {
    super.initState();
    _c.load();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _name {
    final d = _c.detail;
    final n = d == null ? '' : '${d['name'] ?? ''}'.trim();
    return n.isEmpty ? widget.summary.name : n;
  }

  // ---- edits -----------------------------------------------------------------------------------

  Future<bool> _confirm(String text) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l.cancel)),
          FilledButton(
            key: const ValueKey('confirm-change'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.productConfirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _editPrice() async {
    final l = AppLocalizations.of(context);
    final input = await showDialog<PriceInput>(
      context: context,
      builder: (_) => PriceDialog(regular: _c.regularPrice, sale: _c.salePrice),
    );
    if (input == null || !mounted) return;
    if (samePrice(input.regular, _c.regularPrice) && samePrice(input.sale, _c.salePrice)) return;
    final text = input.sale.isEmpty
        ? l.productPriceConfirm(_name, input.regular)
        : l.productPriceConfirmSale(_name, input.regular, input.sale);
    if (!await _confirm(text) || !mounted) return;
    await _handle(await _c.savePrice(regular: input.regular, sale: input.sale));
  }

  Future<void> _editStock() async {
    final l = AppLocalizations.of(context);
    final current = _c.stockQuantity;
    if (current == null) return;
    final qty = await showDialog<int>(
      context: context,
      builder: (_) => StockDialog(current: current),
    );
    if (qty == null || !mounted) return;
    if (qty == current) return;
    if (!await _confirm(l.productStockConfirm(_name, qty, current)) || !mounted) return;
    await _handle(await _c.saveStock(qty));
  }

  Future<void> _handle(ProductEditResult result) async {
    if (!mounted) return;
    switch (result) {
      case ProductEditResult.done:
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.productUpdated)));
      case ProductEditResult.conflict:
        await _showConflict();
      case ProductEditResult.offline:
      case ProductEditResult.busy:
      case ProductEditResult.noAccess:
      case ProductEditResult.failed:
      case ProductEditResult.notApplied:
        // Shown inline from the controller's state.
        break;
    }
  }

  Future<void> _showConflict() async {
    final c = _c.conflict;
    if (c == null) return;
    final l = AppLocalizations.of(context);
    const dash = '—';
    final List<MapEntry<String, String>> mine;
    final List<MapEntry<String, String>> server;
    switch (c.kind) {
      case ProductEditKind.price:
        mine = [
          MapEntry(l.productRegularPrice, priceText(c.mineRegular)),
          MapEntry(l.productSalePriceShort, c.mineSale.isEmpty ? dash : priceText(c.mineSale)),
        ];
        server = [
          MapEntry(l.productRegularPrice, priceText(c.serverRegular)),
          MapEntry(l.productSalePriceShort, c.serverSale.isEmpty ? dash : priceText(c.serverSale)),
        ];
      case ProductEditKind.stock:
        mine = [MapEntry(l.productStockLabel, '${c.mineStock ?? dash}')];
        server = [MapEntry(l.productStockLabel, '${c.serverStock ?? dash}')];
    }
    final choice = await Navigator.of(context).push<_ConflictChoice>(
      MaterialPageRoute<_ConflictChoice>(
        builder: (ctx) => ConflictPage(
          title: l.conflictProductTitle,
          body: l.conflictProductBody,
          local: mine,
          server: server,
          onKeepServer: () => Navigator.of(ctx).pop(_ConflictChoice.keepServer),
          onOverwrite: () => Navigator.of(ctx).pop(_ConflictChoice.overwrite),
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _ConflictChoice.overwrite:
        await _handle(await _c.overwrite());
      case _ConflictChoice.keepServer:
      case null:
        await _c.keepServer();
    }
  }

  // ---- build -----------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(_name)),
        body: _c.noAccess ? NoAccessView(body: l.noAccessProductsBody) : _body(context, l),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l) {
    final t = Theme.of(context).textTheme;
    final s = widget.summary;
    final loaded = _c.detail != null;
    final regular = loaded ? _c.regularPrice : plainPrice(s.regularPrice);
    final sale = loaded ? _c.salePrice : plainPrice(s.salePrice);
    final status = loaded ? _c.stockStatus : s.stockStatus;
    final qty = loaded ? _c.stockQuantity : s.stock;
    final stock = stockLabelFor(l, status, qty);
    final image = _c.featuredUrl.isEmpty ? s.thumbUrl : _c.featuredUrl;
    final sku = loaded ? '${_c.detail!['sku'] ?? ''}'.trim() : s.sku;
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        if (image.isNotEmpty)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                image,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(height: 180),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(_name, style: t.titleMedium),
        if (sku.isNotEmpty) Text(l.productSku(sku), style: t.bodySmall),
        const SizedBox(height: 16),
        Text(l.productPriceLabel, style: t.titleSmall),
        const SizedBox(height: 4),
        _line(l.productRegularPrice, priceText(regular, s.currency), key: const ValueKey('regular-price')),
        if (sale.isNotEmpty)
          _line(l.productSalePriceShort, priceText(sale, s.currency), key: const ValueKey('sale-price')),
        const SizedBox(height: 12),
        Text(l.productStockLabel, style: t.titleSmall),
        const SizedBox(height: 4),
        if (stock.isNotEmpty) Text(stock, key: const ValueKey('stock-text')),
        if (s.variationAttributes.isNotEmpty) ..._variations(context, l, s.variationAttributes),
        const SizedBox(height: 16),
        if (_c.loading)
          const Center(child: CircularProgressIndicator())
        else if (_c.failed) ...[
          Text(l.productDetailFailed),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(onPressed: _c.load, child: Text(l.retry)),
          ),
        ] else
          _editCard(context, l),
      ],
    );
  }

  /// The sizes (and other variation attributes) of a variable product. Read-only: they are
  /// changed on the website, and the note says so.
  List<Widget> _variations(BuildContext context, AppLocalizations l, List<VariationAttribute> attributes) {
    final t = Theme.of(context).textTheme;
    return [
      const SizedBox(height: 12),
      Text(l.productVariationsLabel, style: t.titleSmall),
      const SizedBox(height: 4),
      for (final a in attributes)
        Padding(
          key: ValueKey('variation-${a.key}'),
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.label),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final o in a.options)
                    Chip(label: Text(o.label), visualDensity: VisualDensity.compact),
                ],
              ),
            ],
          ),
        ),
      Text(l.productVariationsWebNote, key: const ValueKey('variations-note'), style: t.bodySmall),
    ];
  }

  Widget _line(String label, String value, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsetsDirectional.only(bottom: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(value),
        ],
      ),
    );
  }

  /// Why the edit buttons are missing, in words; null when there is nothing to say.
  String? _editNote(AppLocalizations l) {
    if (_c.isVariable) return l.productVariableNote;
    final p = _c.permissions;
    if (!p.known) return l.productPermissionsUnknown;
    if (!p.canEditPrice && !p.canEditStock) return l.productReadOnly;
    if (p.canEditStock && !_c.canEditStock && !_c.manageStock) return l.productStockNotCounted;
    return null;
  }

  Widget _editCard(BuildContext context, AppLocalizations l) {
    String? message;
    var retry = false;
    switch (_c.lastResult) {
      case ProductEditResult.offline:
        message = l.needsConnection;
        retry = _c.canRetry;
      case ProductEditResult.busy:
        message = l.statusBusy;
        retry = _c.canRetry;
      case ProductEditResult.noAccess:
        message = l.productNoPermission;
      case ProductEditResult.failed:
        message = _c.lastMessage.isEmpty ? l.productChangeFailed : _c.lastMessage;
        retry = _c.canRetry;
      case ProductEditResult.notApplied:
        message = l.productNotApplied;
      case ProductEditResult.done:
      case ProductEditResult.conflict:
      case null:
        message = null;
    }
    final note = _editNote(l);
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(l.productOnlineOnly)),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 12),
              Text(note, key: const ValueKey('edit-note')),
            ],
            if (_c.canEditPrice || _c.canEditStock) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_c.canEditPrice)
                    FilledButton.tonal(
                      key: const ValueKey('edit-price'),
                      onPressed: _c.sending ? null : _editPrice,
                      child: Text(l.productEditPrice),
                    ),
                  if (_c.canEditStock)
                    FilledButton.tonal(
                      key: const ValueKey('edit-stock'),
                      onPressed: _c.sending ? null : _editStock,
                      child: Text(l.productEditStock),
                    ),
                  if (_c.sending)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message, key: const ValueKey('edit-message')),
              if (retry)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: _c.sending ? null : () async => _handle(await _c.retry()),
                    child: Text(l.retry),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
