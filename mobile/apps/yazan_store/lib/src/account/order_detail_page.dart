import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../catalogue/price_text.dart';
import 'account_api.dart';
import 'account_models.dart';
import 'account_widgets.dart';
import 'failure.dart';

/// One order, read only: lines, the server's totals, payment, delivery address and tracking.
/// The list row it was opened from fills the header while the detail loads.
class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
    super.key,
    required this.api,
    required this.summary,
    required this.onSessionEnded,
  });

  final AccountApi api;
  final OrderSummary summary;
  final VoidCallback onSessionEnded;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  OrderDetail? _detail;
  Failure? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.api.order(widget.summary.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final failure = Failure.from(e);
      if (failure.isSignedOut) {
        endSession(context, widget.onSessionEnded);
        return;
      }
      setState(() {
        _failure = failure;
        _loading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _failure = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detail = _detail;
    final failure = _failure;
    final summary = widget.summary;
    final header = [orderDateText(context, summary), orderStatusLabel(l, summary)]
        .where((s) => s.isNotEmpty)
        .join(' - ');
    final Widget body;
    if (detail != null) {
      body = _DetailList(detail: detail, header: header);
    } else if (failure != null) {
      body = MessageView(text: failureMessage(l, failure), onRetry: _retry);
    } else {
      body = const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.orderNumber(summary.number))),
      body: _loading && detail == null
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.all(16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(header, style: theme.textTheme.titleSmall),
                  ),
                ),
                const Expanded(child: Center(child: CircularProgressIndicator())),
              ],
            )
          : body,
    );
  }
}

class _DetailList extends StatelessWidget {
  const _DetailList({required this.detail, required this.header});

  final OrderDetail detail;
  final String header;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summary = detail.summary;
    return ListView(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
      children: [
        _Pad(child: Text(header, style: theme.textTheme.titleSmall)),
        const SizedBox(height: 8),
        _Pad(child: Text(l.orderItems, style: theme.textTheme.titleMedium)),
        for (final line in detail.items) _LineRow(line: line),
        const Divider(height: 24),
        if (detail.subtotal.isNotEmpty) _AmountRow(label: l.subtotal, value: detail.subtotal),
        if (detail.discount.isNotEmpty) _AmountRow(label: l.discount, value: '-${detail.discount}'),
        if (detail.shipping.isNotEmpty) _AmountRow(label: l.shipping, value: detail.shipping),
        if (detail.tax.isNotEmpty) _AmountRow(label: l.tax, value: detail.tax),
        _AmountRow(label: l.total, value: summary.total, emphasis: true),
        if (detail.paymentMethod.isNotEmpty) ...[
          const Divider(height: 24),
          _AmountRow(label: l.paymentMethod, value: detail.paymentMethod),
        ],
        if (detail.address.isNotEmpty) ...[
          const Divider(height: 24),
          _Pad(child: Text(l.shipTo, style: theme.textTheme.titleMedium)),
          const SizedBox(height: 4),
          _Pad(child: Text(detail.address.join('\n'))),
        ],
        if (detail.shipments.isNotEmpty) ...[
          const Divider(height: 24),
          _Pad(child: Text(l.tracking, style: theme.textTheme.titleMedium)),
          const SizedBox(height: 4),
          for (final s in detail.shipments)
            _Pad(
              child: Text(s.carrier.isEmpty ? s.number : '${s.carrier} - ${s.number}'),
            ),
        ],
      ],
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 4),
        child: child,
      );
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final OrderLine line;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final image = line.image;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ProductImageView(url: image),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(l.quantityLabel(line.quantity), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(line.total, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.value, this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasis ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(value, style: style),
        ],
      ),
    );
  }
}
