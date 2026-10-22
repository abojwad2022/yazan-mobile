import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import '../../l10n/app_localizations.dart';
import '../coupons/coupons_page.dart';
import '../storage/admin_stores.dart';
import '../sync/observed_sync_engine.dart';
import '../sync/sync_center_page.dart';
import '../users/staff_page.dart';
import 'section_hosts.dart';
import 'staff_permissions.dart';

/// What a section opened from the More tab may use. Built once by the home page.
class MoreServices {
  const MoreServices({required this.client, required this.stores, required this.sync});

  final YazanApiClient client;

  /// The signed-in account's feed mirrors and outbox (feeds are wiped with the account).
  final AdminStores stores;
  final ObservedSyncEngine sync;
}

/// One tile of the More tab.
class MoreEntry {
  const MoreEntry({
    required this.key,
    required this.title,
    required this.icon,
    required this.builder,
    this.permission,
    this.anyOf = const [],
  });

  /// Stable id; the tile's widget key is `more-<key>`.
  final String key;
  final String Function(AppLocalizations l) title;
  final IconData icon;

  /// The RBAC slug (from the `/me` permission map) that shows the tile; null means always shown.
  /// The server re-checks every request, this only hides tiles.
  final String? permission;

  /// For a section made of parts with their own permissions: the tile shows when any one of these
  /// slugs is allowed (and [permission], when set, too). Empty means no such condition.
  final List<String> anyOf;

  /// Whether the tile shows for [permissions].
  bool visibleWith(StaffPermissions permissions) =>
      permissions.allows(permission) && (anyOf.isEmpty || anyOf.any(permissions.allows));

  /// The page the tile opens. It owns its own state (repository, controllers).
  final Widget Function(BuildContext context, MoreServices services) builder;
}

/// The sections reachable from the More tab, in display order.
///
/// To add a section: write a self-contained page, then add one [MoreEntry] here (and its title to
/// both ARB files). Nothing else in the home page changes.
final List<MoreEntry> moreEntries = <MoreEntry>[
  MoreEntry(
    key: 'coupons',
    title: (l) => l.couponsTitle,
    icon: Icons.sell_outlined,
    permission: 'coupons.view',
    builder: (context, s) => CouponsPage(client: s.client, stores: s.stores),
  ),

  MoreEntry(
    key: 'reports',
    title: (l) => l.reportsTitle,
    icon: Icons.bar_chart_outlined,
    permission: 'reports.view',
    builder: (context, s) => ReportsHost(services: s),
  ),
  MoreEntry(
    key: 'inventory',
    title: (l) => l.inventoryTitle,
    icon: Icons.inventory_2_outlined,
    permission: 'inventory.view',
    builder: (context, s) => InventoryHost(services: s),
  ),
  MoreEntry(
    key: 'shipping-tax',
    title: (l) => l.shippingTaxTitle,
    icon: Icons.local_shipping_outlined,
    anyOf: const ['shipping.view', 'tax.view'],
    builder: (context, s) => ShippingTaxHost(services: s),
  ),

  MoreEntry(
    key: 'staff',
    title: (l) => l.staffTitle,
    icon: Icons.badge_outlined,
    permission: 'users.view',
    builder: (context, s) => StaffPage(client: s.client, stores: s.stores),
  ),

  MoreEntry(
    key: 'sync',
    title: (l) => l.syncCenterTitle,
    icon: Icons.sync,
    builder: (context, s) =>
        SyncCenterPage(accountId: s.stores.accountId, store: s.stores.outbox, engine: s.sync),
  ),
];
