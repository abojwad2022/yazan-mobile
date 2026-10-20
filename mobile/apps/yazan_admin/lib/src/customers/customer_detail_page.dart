import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../orders/no_access_view.dart';
import '../orders/orders_format.dart';
import 'customer_api.dart';
import 'customer_detail_controller.dart';
import 'customer_permissions.dart';
import 'customer_summary.dart';
import 'customers_format.dart';

/// One customer, read-only: contact, billing address, orders and spend, and the last order. The
/// list row shows immediately; the rest is fetched when the screen opens and is not kept on the
/// phone, so it needs a connection.
class CustomerDetailPage extends StatefulWidget {
  const CustomerDetailPage({
    super.key,
    required this.summary,
    required this.load,
    this.permissions = const CustomerPermissions.unknown(),
  });

  final CustomerSummary summary;
  final CustomerLoader load;

  /// What the list already learned; used to explain withheld contact details.
  final CustomerPermissions permissions;

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  late final CustomerDetailController _c = CustomerDetailController(
    customerId: widget.summary.id,
    load: widget.load,
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

  String _name(AppLocalizations l) {
    final d = _c.detail;
    final fromServer = d == null ? '' : d.name;
    final n = fromServer.isNotEmpty ? fromServer : widget.summary.name;
    return n.isEmpty ? l.customerUnnamed : n;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(_name(l))),
        body: _c.noAccess ? NoAccessView(body: l.noAccessCustomersBody) : _body(context, l),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l) {
    final t = Theme.of(context).textTheme;
    final s = widget.summary;
    final d = _c.detail;
    final email = d != null && d.email.isNotEmpty ? d.email : s.email;
    final phone = d != null && d.phone.isNotEmpty ? d.phone : s.phone;
    final registered = d != null && d.registered.isNotEmpty ? d.registered : s.registered;
    final count = d != null && d.orderCount != null ? d.orderCount : s.orderCount;
    final spent = d != null && d.totalSpent.isNotEmpty ? d.totalSpent : s.totalSpent;
    final symbol = d == null ? '' : d.currencySymbol;
    final last = d?.lastOrder;
    final piiHidden = !widget.permissions.canViewPii;
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        Text(_name(l), style: t.titleMedium),
        if (registered.isNotEmpty) Text(l.customerSince(registered), style: t.bodySmall),
        const SizedBox(height: 16),
        Text(l.customerContact, style: t.titleSmall),
        const SizedBox(height: 4),
        if (email.isNotEmpty)
          _line(l.customerEmailLabel, email, key: const ValueKey('customer-email'), latin: true),
        if (phone.isNotEmpty)
          _line(l.customerPhoneLabel, phone, key: const ValueKey('customer-phone'), latin: true),
        if (piiHidden) Text(l.customerPiiHidden, key: const ValueKey('customer-pii-note')),
        if (d != null && d.addressLines.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l.customerAddress, style: t.titleSmall),
          const SizedBox(height: 4),
          for (final line in d.addressLines) Text(line),
        ],
        const SizedBox(height: 16),
        if (count != null) _line(l.customerOrders, '$count', key: const ValueKey('customer-orders')),
        if (spent.isNotEmpty)
          _line(l.customerTotalSpent, customerMoney(spent, symbol), key: const ValueKey('customer-spent')),
        const SizedBox(height: 16),
        if (_c.loading)
          const Center(child: CircularProgressIndicator())
        else if (_c.failed) ...[
          Text(l.customerDetailFailed),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(onPressed: _c.load, child: Text(l.retry)),
          ),
        ] else ...[
          Text(l.customerLastOrder, style: t.titleSmall),
          const SizedBox(height: 4),
          if (last == null)
            Text(l.customerNoOrders, key: const ValueKey('customer-no-orders'))
          else
            Card(
              key: const ValueKey('customer-last-order'),
              child: Padding(
                padding: const EdgeInsetsDirectional.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.orderNumber(last.number.isEmpty ? '${last.id}' : last.number), style: t.titleSmall),
                    if (last.date.isNotEmpty) Text(last.date, style: t.bodySmall),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: Text(statusLabel(l, last.status))),
                        const SizedBox(width: 12),
                        Text(customerMoney(last.total, symbol)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _line(String label, String value, {Key? key, bool latin = false}) {
    return Padding(
      key: key,
      padding: const EdgeInsetsDirectional.only(bottom: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(value, textDirection: latin ? TextDirection.ltr : null),
        ],
      ),
    );
  }
}
