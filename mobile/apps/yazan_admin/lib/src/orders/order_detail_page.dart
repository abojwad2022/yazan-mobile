import 'package:flutter/material.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../../l10n/app_localizations.dart';
import 'no_access_view.dart';
import 'order_summary.dart';
import 'orders_format.dart';

/// Loads the full order JSON (`/yazan/v1/orders/{id}`).
///
/// TODO: when the API client can return response headers (`getJsonWithEtag`), return the ETag
/// too and use it as the `If-Match` base for writes instead of [OrderSummary.version].
typedef OrderLoader = Future<Map<String, dynamic>> Function(int id);

/// Read-only order detail. Status changes are online-only, so this screen only explains that.
class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({super.key, required this.summary, required this.load});

  final OrderSummary summary;
  final OrderLoader load;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  Map<String, dynamic>? _detail;
  bool _failed = false;
  bool _noAccess = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final d = await widget.load(widget.summary.id);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _noAccess = e.action == ErrorAction.hideFeature;
        _failed = true;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = widget.summary;
    return Scaffold(
      appBar: AppBar(title: Text(l.orderNumber(s.number))),
      body: _noAccess ? const NoAccessView() : _body(context, l, s),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l, OrderSummary s) {
    final t = Theme.of(context).textTheme;
    final d = _detail;
    final rawLines = d?['items'];
    final lines = rawLines is List ? rawLines : const <Object?>[];
    final payment = d == null ? '' : '${d['payment_method'] ?? ''}';
    final billing = d == null ? '' : '${d['billing_formatted'] ?? ''}';
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        Text(s.customerName.isEmpty ? l.guestCustomer : s.customerName, style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(label: Text(statusLabel(l, s.status)), visualDensity: VisualDensity.compact),
            Text(l.orderItems(s.itemCount)),
          ],
        ),
        const SizedBox(height: 8),
        Text('${l.orderTotal}: ${formatMoney(s.total)}', style: t.titleSmall),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsetsDirectional.all(12),
            child: Row(
              children: [
                const Icon(Icons.wifi_off_outlined, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(l.orderStatusNeedsConnection)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_failed) ...[
          Text(l.orderDetailFailed),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(onPressed: _fetch, child: Text(l.retry)),
          ),
        ] else ...[
          if (lines.isNotEmpty) ...[
            Text(l.orderLines, style: t.titleSmall),
            for (final raw in lines)
              if (raw is Map)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${raw['name'] ?? ''}'),
                  subtitle: Text('x ${raw['quantity'] ?? ''}'),
                  trailing: Text('${raw['total'] ?? ''}'),
                ),
          ],
          if (payment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l.orderPayment, style: t.titleSmall),
            Text(payment),
          ],
          if (billing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l.orderBilling, style: t.titleSmall),
            Text(billing),
          ],
        ],
      ],
    );
  }
}
