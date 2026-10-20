import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../catalogue/price_text.dart';
import 'account_api.dart';
import 'account_models.dart';
import 'account_widgets.dart';
import 'failure.dart';
import 'order_detail_page.dart';

/// The customer's own orders, newest first, ten at a time. Read only; needs a connection.
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key, required this.api, required this.onSessionEnded});

  final AccountApi api;

  /// Called after every pushed screen is closed when the server says the session is over.
  final VoidCallback onSessionEnded;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final List<OrderSummary> _orders = [];
  int _page = 0;
  int _pages = 0;
  bool _loading = true;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    _loadNext();
  }

  /// Fetches the next page. Callers set `_loading` first (it starts true for the first page).
  Future<void> _loadNext() async {
    try {
      final result = await widget.api.orders(page: _page + 1);
      if (!mounted) return;
      setState(() {
        _orders.addAll(result.orders);
        _page += 1;
        _pages = result.pages;
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

  void _request() {
    setState(() {
      _loading = true;
      _failure = null;
    });
    _loadNext();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final failure = _failure;
    final Widget body;
    if (_orders.isEmpty) {
      if (_loading) {
        body = const Center(child: CircularProgressIndicator());
      } else if (failure != null) {
        body = MessageView(text: failureMessage(l, failure), onRetry: _request);
      } else {
        body = MessageView(text: l.noOrders);
      }
    } else {
      body = ListView(
        children: [
          for (final order in _orders)
            _OrderTile(
              order: order,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OrderDetailPage(
                    api: widget.api,
                    summary: order,
                    onSessionEnded: widget.onSessionEnded,
                  ),
                ),
              ),
            ),
          if (failure != null)
            Padding(
              padding: const EdgeInsetsDirectional.all(16),
              child: Column(
                children: [
                  Text(
                    failureMessage(l, failure),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _request, child: Text(l.retry)),
                ],
              ),
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsetsDirectional.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_page < _pages)
            Padding(
              padding: const EdgeInsetsDirectional.all(16),
              child: OutlinedButton(onPressed: _request, child: Text(l.loadMore)),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.myOrders)),
      body: body,
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onTap});

  final OrderSummary order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final image = order.image;
    final parts = <String>[
      orderDateText(context, order),
      orderStatusLabel(l, order),
    ].where((s) => s.isNotEmpty).toList();
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 48,
        height: 48,
        child: image == null
            ? const Icon(Icons.receipt_long_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: ProductImageView(url: image),
              ),
      ),
      title: Text(l.orderNumber(order.number)),
      subtitle: Text(parts.join(' - ')),
      trailing: Text(order.total),
    );
  }
}
