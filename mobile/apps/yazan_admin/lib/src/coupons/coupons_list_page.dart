import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import '../orders/no_access_view.dart';
import 'coupon_summary.dart';
import 'coupons_format.dart';
import 'coupons_repository.dart';

/// The coupons as the phone last saw them: search by code or description, an Active / Expired
/// badge and the usage at a glance. It shows the offline copy first; pulling down refreshes.
class CouponsListPage extends StatefulWidget {
  const CouponsListPage({super.key, required this.repository, required this.onOpen});

  final CouponsRepository repository;
  final void Function(CouponSummary coupon) onOpen;

  @override
  State<CouponsListPage> createState() => _CouponsListPageState();
}

class _CouponsListPageState extends State<CouponsListPage> {
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
        if (repo.noAccess) return NoAccessView(body: l.noAccessCouponsBody);
        final everything = repo.all;
        if (!repo.loaded && everything.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final shown = repo.coupons;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
              child: TextField(
                key: const ValueKey('coupon-search'),
                controller: _search,
                onChanged: repo.setQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l.couponsSearchHint,
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
                          return _CouponRow(coupon: shown[i - 1], onTap: widget.onOpen);
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _emptyText(AppLocalizations l, CouponsRepository repo, bool cacheEmpty) {
    if (!cacheEmpty) return l.couponsNoMatch(repo.query.trim());
    return repo.lastRefreshFailed ? l.couponsLoadFailed : l.couponsEmpty;
  }
}

class _CouponRow extends StatelessWidget {
  const _CouponRow({required this.coupon, required this.onTap});

  final CouponSummary coupon;
  final void Function(CouponSummary coupon) onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    return ListTile(
      key: ValueKey('coupon-${coupon.id}'),
      onTap: () => onTap(coupon),
      leading: const CircleAvatar(child: Icon(Icons.sell_outlined)),
      // A code reads left to right even in an Arabic layout.
      title: Text(coupon.code, textDirection: TextDirection.ltr, textAlign: TextAlign.start),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${coupon.amountText} · ${couponUsageText(l, coupon.usageCount, coupon.usageLimit)}',
              style: t.bodySmall),
          Text(couponExpiryText(l, coupon), style: t.bodySmall),
        ],
      ),
      trailing: Text(
        coupon.expired ? l.couponExpired : l.couponActive,
        key: ValueKey('coupon-badge-${coupon.id}'),
        style: t.labelMedium,
      ),
    );
  }
}
