import 'package:flutter/material.dart';

import '../inventory/inventory_page.dart';
import '../inventory/inventory_repository.dart';
import '../reports/reports_page.dart';
import '../reports/reports_repository.dart';
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
