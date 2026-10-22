import 'package:flutter/material.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

import '../../l10n/app_localizations.dart';
import '../dashboard/dashboard_format.dart';
import '../orders/no_access_view.dart';
import 'shipping_tax_repository.dart';
import 'shipping_tax_snapshot.dart';

/// Shipping zones with their methods and costs, then the tax options and rate tables. Read only:
/// the web dashboard is where these are changed.
///
/// Each part is drawn only when the server gave it to this account. With [showAppBar] the page
/// brings its own title bar, for use as a pushed route.
class ShippingTaxPage extends StatefulWidget {
  const ShippingTaxPage({super.key, required this.repository, this.showAppBar = false});

  final ShippingTaxRepository repository;
  final bool showAppBar;

  @override
  State<ShippingTaxPage> createState() => _ShippingTaxPageState();
}

class _ShippingTaxPageState extends State<ShippingTaxPage> {
  @override
  void initState() {
    super.initState();
    widget.repository.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final body = ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) => _content(context, l),
    );
    if (!widget.showAppBar) return body;
    return Scaffold(appBar: AppBar(title: Text(l.shippingTaxTitle)), body: body);
  }

  Widget _content(BuildContext context, AppLocalizations l) {
    final repo = widget.repository;
    if (repo.noAccess) return NoAccessView(body: l.shippingTaxNoAccessBody);
    final shipping = repo.shipping;
    final tax = repo.tax;
    if (shipping == null && tax == null && !repo.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (shipping == null && tax == null) {
      return RefreshIndicator(
        onRefresh: repo.refresh,
        child: ListView(
          key: const ValueKey('shiptax-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.all(24),
          children: [
            if (repo.lastRefreshFailed) StaleBadge(label: l.ordersRefreshFailed),
            const SizedBox(height: 16),
            Text(l.shippingTaxLoadFailed, key: const ValueKey('shiptax-failed'), textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: repo.refresh,
      child: ListView(
        key: const ValueKey('shiptax-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l.shippingTaxReadOnly, key: const ValueKey('shiptax-readonly'), style: t.bodySmall),
              if (repo.lastRefreshFailed)
                StaleBadge(key: const ValueKey('shiptax-stale'), label: l.ordersRefreshFailed),
            ],
          ),
          const SizedBox(height: 12),
          _SectionTitle(
            l.shippingZonesTitle,
            asOf: shipping?.fetchedAt,
            asOfKey: const ValueKey('shipping-asof'),
          ),
          if (repo.shippingNoAccess)
            _Note(l.shippingNoAccess, key: const ValueKey('shipping-no-access'))
          else if (shipping == null)
            _Note(l.shippingLoadFailed, key: const ValueKey('shipping-failed'))
          else if (shipping.zones.isEmpty)
            _Note(l.shippingNoZones, key: const ValueKey('shipping-empty'))
          else
            for (final z in shipping.zones) _ZoneCard(zone: z),
          const SizedBox(height: 16),
          _SectionTitle(l.taxTitle, asOf: tax?.fetchedAt, asOfKey: const ValueKey('tax-asof')),
          if (repo.taxNoAccess)
            _Note(l.taxNoAccess, key: const ValueKey('tax-no-access'))
          else if (tax == null)
            _Note(l.taxLoadFailed, key: const ValueKey('tax-failed'))
          else ...[
            _TaxSettingsCard(tax: tax),
            for (final c in tax.classes) _TaxClassCard(taxClass: c),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.asOf, required this.asOfKey});

  final String text;
  final DateTime? asOf;
  final Key asOfKey;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final time = asOf;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: t.titleMedium),
          if (time != null) Text(l.dashboardAsOf(formatAsOf(time)), key: asOfKey, style: t.bodySmall),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsetsDirectional.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(16),
          child: Text(text),
        ),
      );
}

/// A label on the start side and a value on the end side; the value keeps left-to-right order.
class _Line extends StatelessWidget {
  const _Line({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
      );
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({required this.zone});

  final ShippingZoneInfo zone;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final name = zone.isFallback ? l.shippingFallbackZone : zone.name;
    final region = zone.isFallback ? l.shippingFallbackRegion : zone.regionText;
    return Card(
      key: ValueKey('shipping-zone-${zone.id}'),
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: t.titleSmall),
            if (region.isNotEmpty) Text(region, style: t.bodySmall),
            const Divider(height: 16),
            if (zone.methods.isEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 4),
                child: Text(l.shippingNoMethods, key: ValueKey('shipping-zone-${zone.id}-empty')),
              )
            else
              for (final m in zone.methods) _MethodRow(method: m),
          ],
        ),
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({required this.method});

  final ShippingMethodInfo method;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final summary = methodCostSummary(l, method);
    final title = method.title.isNotEmpty ? method.title : method.methodTitle;
    return Padding(
      key: ValueKey('shipping-method-${method.instanceId}'),
      padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.bodyLarge),
                if (method.methodTitle.isNotEmpty && method.methodTitle != title)
                  Text(method.methodTitle, style: t.bodySmall),
                if (summary.isNotEmpty)
                  Text(summary, key: ValueKey('shipping-method-${method.instanceId}-cost')),
                for (final c in method.classCosts)
                  Text('${c.key}: ${isolate(c.value)}', style: t.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            method.enabled ? l.shippingMethodOn : l.shippingMethodOff,
            key: ValueKey('shipping-method-${method.instanceId}-state'),
            style: t.labelMedium?.copyWith(
              color: method.enabled ? null : Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// What a method charges, in the person's language: the flat cost, the free-shipping rule, or the
/// pickup cost. Empty when the method type has nothing simple to show. Costs stay as the server
/// stores them (a flat rate may be a formula), isolated left to right.
String methodCostSummary(AppLocalizations l, ShippingMethodInfo m) {
  final cost = m.value('cost');
  final min = m.value('min_amount');
  switch (m.methodId) {
    case 'flat_rate':
      return cost.isEmpty || cost == '0' ? l.shippingCostNone : l.shippingCost(isolate(cost));
    case 'free_shipping':
      final amount = isolate(min.isEmpty ? '0' : min);
      switch (m.value('requires')) {
        case 'coupon':
          return l.shippingFreeCoupon;
        case 'min_amount':
          return l.shippingFreeMin(amount);
        case 'either':
          return l.shippingFreeEither(amount);
        case 'both':
          return l.shippingFreeBoth(amount);
      }
      return l.shippingFreeAlways;
    case 'yazan_live_rates':
      return l.shippingLiveRates;
  }
  if (m.values.containsKey('cost')) {
    return cost.isEmpty || cost == '0' ? l.shippingCostNone : l.shippingCost(isolate(cost));
  }
  return '';
}

class _TaxSettingsCard extends StatelessWidget {
  const _TaxSettingsCard({required this.tax});

  final TaxSnapshot tax;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      key: const ValueKey('tax-settings'),
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tax.enabled ? l.taxOn : l.taxOff,
              key: const ValueKey('tax-enabled'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Divider(height: 16),
            for (final s in tax.settings)
              _Line(
                key: ValueKey('tax-setting-${s.option}'),
                label: taxSettingLabel(l, s),
                value: taxSettingValue(l, s),
              ),
          ],
        ),
      ),
    );
  }
}

/// The app's own wording for the options it knows; the server's label for any other.
String taxSettingLabel(AppLocalizations l, TaxSetting s) {
  switch (s.option) {
    case 'woocommerce_calc_taxes':
      return l.taxOptCalc;
    case 'woocommerce_prices_include_tax':
      return l.taxOptPricesInclude;
    case 'woocommerce_tax_based_on':
      return l.taxOptBasedOn;
    case 'woocommerce_shipping_tax_class':
      return l.taxOptShippingClass;
    case 'woocommerce_tax_round_at_subtotal':
      return l.taxOptRoundSubtotal;
    case 'woocommerce_tax_display_shop':
      return l.taxOptDisplayShop;
    case 'woocommerce_tax_display_cart':
      return l.taxOptDisplayCart;
    case 'woocommerce_price_display_suffix':
      return l.taxOptSuffix;
  }
  return s.label;
}

/// A setting's value in the person's language where the app knows it; otherwise the server's
/// choice label, or the stored text.
String taxSettingValue(AppLocalizations l, TaxSetting s) {
  if (s.isBool) return s.value == 'yes' ? l.taxYes : l.taxNo;
  final v = s.value;
  switch (s.option) {
    case 'woocommerce_prices_include_tax':
      if (v == 'yes') return l.taxValPricesIncl;
      if (v == 'no') return l.taxValPricesExcl;
    case 'woocommerce_tax_based_on':
      if (v == 'shipping') return l.taxValShipping;
      if (v == 'billing') return l.taxValBilling;
      if (v == 'base') return l.taxValBase;
    case 'woocommerce_tax_display_shop':
    case 'woocommerce_tax_display_cart':
      if (v == 'incl') return l.taxValIncl;
      if (v == 'excl') return l.taxValExcl;
    case 'woocommerce_shipping_tax_class':
      if (v == 'inherit') return l.taxValInherit;
      if (v.isEmpty) return l.taxClassStandard;
  }
  final choice = s.choices[v];
  if (choice != null && choice.isNotEmpty) return choice;
  return v.isEmpty ? l.taxValNone : v;
}

class _TaxClassCard extends StatelessWidget {
  const _TaxClassCard({required this.taxClass});

  final TaxClassRates taxClass;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final name = taxClass.isStandard ? l.taxClassStandard : taxClass.name;
    final id = taxClass.isStandard ? 'standard' : taxClass.slug;
    return Card(
      key: ValueKey('tax-class-$id'),
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.taxClassRates(name, taxClass.rates.length), style: t.titleSmall),
            const Divider(height: 16),
            if (taxClass.rates.isEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 4),
                child: Text(l.taxNoRates, key: ValueKey('tax-class-$id-empty')),
              )
            else
              for (final r in taxClass.rates) _RateRow(rate: r),
          ],
        ),
      ),
    );
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({required this.rate});

  final TaxRateInfo rate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final where = rate.location;
    final flags = [
      l.taxRatePriority(rate.priority),
      if (rate.shipping) l.taxRateShipping,
      if (rate.compound) l.taxRateCompound,
      if (rate.managed) l.taxRateManaged,
    ].join(' · ');
    return Padding(
      key: ValueKey('tax-rate-${rate.id}'),
      padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rate.name.isEmpty ? l.taxTitle : rate.name, style: t.bodyLarge),
                Text(
                  where.isEmpty ? l.taxRateEverywhere : isolate(where),
                  key: ValueKey('tax-rate-${rate.id}-where'),
                  style: t.bodySmall,
                ),
                Text(flags, style: t.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${rate.percent}%',
            key: ValueKey('tax-rate-${rate.id}-percent'),
            style: t.titleMedium,
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}
