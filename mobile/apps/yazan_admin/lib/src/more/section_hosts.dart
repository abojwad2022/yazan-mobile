import 'package:flutter/material.dart';

import '../activity/activity_page.dart';
import '../activity/activity_repository.dart';
import '../inventory/inventory_page.dart';
import '../inventory/inventory_repository.dart';
import '../reports/reports_page.dart';
import '../reports/reports_repository.dart';
import '../shipping_tax/shipping_tax_page.dart';
import '../shipping_tax/shipping_tax_repository.dart';
import '../storage/admin_stores.dart';
import 'more_registry.dart';

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
  Widget build(BuildContext context) => ShippingTaxPage(repository: _repository, showAppBar: true);
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
  Widget build(BuildContext context) => ActivityPage(repository: _repository, showAppBar: true);
}
