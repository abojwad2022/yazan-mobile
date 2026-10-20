import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import '../../l10n/app_localizations.dart';
import '../products/product_api.dart' show permissionsLoader;
import '../products/product_permissions.dart' show PermissionsLoader;
import '../storage/admin_stores.dart';
import 'coupon_api.dart';
import 'coupon_detail_page.dart';
import 'coupon_summary.dart';
import 'coupons_list_page.dart';
import 'coupons_repository.dart';

/// The Coupons section opened from the More tab: owns its repository (list + offline copy) and
/// opens the detail page. Self-contained: the More registry only needs the client and the stores.
class CouponsPage extends StatefulWidget {
  const CouponsPage({super.key, this.client, this.stores, this.repository, this.load, this.write, this.loadPermissions})
      : assert(client != null || (repository != null && load != null && write != null),
            'pass a client, or a repository with load and write (tests)');

  final YazanApiClient? client;
  final AdminStores? stores;

  /// For tests: a ready repository and the detail functions, instead of the client.
  final CouponsRepository? repository;
  final CouponLoader? load;
  final CouponWriter? write;
  final PermissionsLoader? loadPermissions;

  @override
  State<CouponsPage> createState() => _CouponsPageState();
}

class _CouponsPageState extends State<CouponsPage> {
  late final bool _ownsRepository = widget.repository == null;
  late final CouponsRepository _repo = widget.repository ??
      CouponsRepository.forClient(
        widget.client!,
        store: widget.stores?.feed(AdminFeeds.coupons),
      );
  late final CouponLoader _load = widget.load ?? couponLoader(widget.client!);
  late final CouponWriter _write = widget.write ?? couponWriter(widget.client!);
  late final PermissionsLoader? _loadPermissions =
      widget.loadPermissions ?? (widget.client == null ? null : permissionsLoader(widget.client!));

  @override
  void dispose() {
    if (_ownsRepository) _repo.dispose();
    super.dispose();
  }

  void _open(CouponSummary coupon) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CouponDetailPage(
          summary: coupon,
          load: _load,
          write: _write,
          permissions: _repo.permissions,
          loadPermissions: _loadPermissions,
          onChanged: _repo.refresh,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.couponsTitle)),
      body: CouponsListPage(repository: _repo, onOpen: _open),
    );
  }
}
