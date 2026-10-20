import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import '../orders/no_access_view.dart';
import 'customer_summary.dart';
import 'customers_format.dart';
import 'customers_repository.dart';

/// The customers as the phone last saw them: search by name, email or phone, orders and spend at a
/// glance. Read-only. It reads the local mirror first, so it works offline; pulling down refreshes.
class CustomersListPage extends StatefulWidget {
  const CustomersListPage({super.key, required this.repository, required this.onOpen});

  final CustomersRepository repository;
  final void Function(CustomerSummary customer) onOpen;

  @override
  State<CustomersListPage> createState() => _CustomersListPageState();
}

class _CustomersListPageState extends State<CustomersListPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.repository.refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final repo = widget.repository;
        if (repo.noAccess) return NoAccessView(body: l.noAccessCustomersBody);
        final everything = repo.all;
        if (!repo.loaded && everything.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final shown = repo.customers;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
              child: TextField(
                key: const ValueKey('customer-search'),
                controller: _search,
                onChanged: repo.setQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l.customersSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: repo.refresh,
                child: shown.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsetsDirectional.all(24),
                        children: [
                          if (repo.lastRefreshFailed) StaleBadge(label: l.ordersRefreshFailed),
                          const SizedBox(height: 16),
                          Text(_emptyText(l, repo, everything.isEmpty), textAlign: TextAlign.center),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: shown.length + 1,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return repo.lastRefreshFailed
                                ? Padding(
                                    padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
                                    child: Align(
                                      alignment: AlignmentDirectional.centerStart,
                                      child: StaleBadge(label: l.ordersRefreshFailed),
                                    ),
                                  )
                                : const SizedBox.shrink();
                          }
                          return _CustomerRow(customer: shown[i - 1], onTap: widget.onOpen);
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _emptyText(AppLocalizations l, CustomersRepository repo, bool cacheEmpty) {
    if (!cacheEmpty) return l.customersNoMatch(repo.query.trim());
    return repo.lastRefreshFailed ? l.customersLoadFailed : l.customersEmpty;
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.onTap});

  final CustomerSummary customer;
  final void Function(CustomerSummary customer) onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final count = customer.orderCount;
    return ListTile(
      key: ValueKey('customer-${customer.id}'),
      onTap: () => onTap(customer),
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(customer.name.isEmpty ? l.customerUnnamed : customer.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emails and phone numbers read left to right even in an Arabic layout.
          if (customer.email.isNotEmpty && customer.email != customer.name)
            Text(customer.email, style: t.bodySmall, textDirection: TextDirection.ltr),
          if (customer.phone.isNotEmpty)
            Text(customer.phone, style: t.bodySmall, textDirection: TextDirection.ltr),
          if (count != null) Text(l.customerOrdersCount(count), style: t.bodySmall),
        ],
      ),
      trailing: customer.totalSpent.isEmpty ? null : Text(customerMoney(customer.totalSpent)),
    );
  }
}
