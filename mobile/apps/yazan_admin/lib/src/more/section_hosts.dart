import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../activity/activity_page.dart';
import '../activity/activity_repository.dart';
import '../inventory/inventory_page.dart';
import '../inventory/inventory_repository.dart';
import '../products/product_permissions.dart' show PermissionsLoader;
import '../reports/reports_page.dart';
import '../reports/reports_repository.dart';
import '../shipping_tax/shipping_tax_page.dart';
import '../shipping_tax/shipping_tax_repository.dart';
import '../storage/admin_stores.dart';
import 'more_registry.dart';
import 'staff_permissions.dart';

/// `GET /yazan-mobile/v1/me` over the services' client.
PermissionsLoader meLoader(MoreServices services) =>
    () => services.client.getJson('/yazan-mobile/v1/me');

/// Holds a section's page back until the `/me` permission map has been asked, so cached rows are
/// not shown to an account the map already says may not see them.
///
/// [apply] gets the map when it is known (the repository drops what the map does not allow); then
/// [builder]'s page is shown. An unknown map, a failed or missing [loadPermissions], or an answer
/// slower than [grace] shows the page as before (offline the cache still opens at once); an answer
/// that arrives after that is still applied.
class SectionPermissionGate extends StatefulWidget {
  const SectionPermissionGate({
    super.key,
    required this.loadPermissions,
    required this.apply,
    required this.title,
    required this.builder,
    this.grace = const Duration(seconds: 2),
  });

  final PermissionsLoader? loadPermissions;
  final Future<void> Function(StaffPermissions permissions) apply;
  final String Function(AppLocalizations l) title;
  final WidgetBuilder builder;
  final Duration grace;

  @override
  State<SectionPermissionGate> createState() => _SectionPermissionGateState();
}

class _SectionPermissionGateState extends State<SectionPermissionGate> {
  bool _open = false;
  Timer? _grace;

  @override
  void initState() {
    super.initState();
    final loader = widget.loadPermissions;
    if (loader == null) {
      _open = true;
      return;
    }
    _grace = Timer(widget.grace, _show);
    _check(loader);
  }

  Future<void> _check(PermissionsLoader loader) async {
    try {
      final permissions = StaffPermissions.fromMe(await loader());
      if (!mounted) return;
      if (permissions.known) await widget.apply(permissions);
    } catch (_) {
      // Offline or refused: the map stays unknown and the server decides.
    }
    _show();
  }

  void _show() {
    _grace?.cancel();
    if (!mounted || _open) return;
    setState(() => _open = true);
  }

  @override
  void dispose() {
    _grace?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_open) return widget.builder(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title(AppLocalizations.of(context)))),
      body: const Center(
        child: CircularProgressIndicator(key: ValueKey('section-permission-check')),
      ),
    );
  }
}

/// Owns the repository of the Reports section for as long as its page is open.
class ReportsHost extends StatefulWidget {
  const ReportsHost({super.key, required this.services});

  final MoreServices services;

  @override
  State<ReportsHost> createState() => _ReportsHostState();
}

class _ReportsHostState extends State<ReportsHost> {
  late final ReportsRepository _repository = ReportsRepository.forClient(
    widget.services.client,
    store: widget.services.stores.feed(AdminFeeds.reports),
  );

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ReportsPage(repository: _repository, showAppBar: true);
}

/// Owns the repository of the Inventory section for as long as its page is open.
class InventoryHost extends StatefulWidget {
  const InventoryHost({super.key, required this.services});

  final MoreServices services;

  @override
  State<InventoryHost> createState() => _InventoryHostState();
}

class _InventoryHostState extends State<InventoryHost> {
  late final InventoryRepository _repository = InventoryRepository.forClient(
    widget.services.client,
    store: widget.services.stores.feed(AdminFeeds.inventory),
  );

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InventoryPage(repository: _repository, showAppBar: true);
}

/// Owns the repository of the Shipping & tax section for as long as its page is open.
class ShippingTaxHost extends StatefulWidget {
  const ShippingTaxHost({super.key, required this.services});

  final MoreServices services;

  @override
  State<ShippingTaxHost> createState() => _ShippingTaxHostState();
}

class _ShippingTaxHostState extends State<ShippingTaxHost> {
  late final ShippingTaxRepository _repository = ShippingTaxRepository.forClient(
    widget.services.client,
    store: widget.services.stores.feed(AdminFeeds.shippingTax),
  );

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SectionPermissionGate(
        loadPermissions: meLoader(widget.services),
        apply: _repository.applyPermissions,
        title: (l) => l.shippingTaxTitle,
        builder: (_) => ShippingTaxPage(repository: _repository, showAppBar: true),
      );
}

/// Owns the repository of the Activity log section for as long as its page is open.
class ActivityHost extends StatefulWidget {
  const ActivityHost({super.key, required this.services});

  final MoreServices services;

  @override
  State<ActivityHost> createState() => _ActivityHostState();
}

class _ActivityHostState extends State<ActivityHost> {
  late final ActivityRepository _repository = ActivityRepository.forClient(
    widget.services.client,
    store: widget.services.stores.feed(AdminFeeds.activity),
  );

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SectionPermissionGate(
        loadPermissions: meLoader(widget.services),
        apply: _repository.applyPermissions,
        title: (l) => l.activityTitle,
        builder: (_) => ActivityPage(repository: _repository, showAppBar: true),
      );
}
