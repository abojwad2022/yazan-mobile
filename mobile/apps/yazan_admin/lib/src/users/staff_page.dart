import 'package:flutter/material.dart';
import 'package:yazan_api_client/yazan_api_client.dart';

import '../../l10n/app_localizations.dart';
import '../storage/admin_stores.dart';
import 'staff_api.dart';
import 'staff_detail_page.dart';
import 'staff_list_page.dart';
import 'staff_member.dart';
import 'staff_repository.dart';

/// The `feed` name of the cached staff list. Account-scoped like every feed, so the per-account
/// wipe on sign-out removes it.
const String staffFeedName = 'staff';

/// The Staff section opened from the More tab: owns its repository (list + offline copy) and opens
/// the detail page. Self-contained: the More registry only needs the client and the stores.
class StaffPage extends StatefulWidget {
  const StaffPage({super.key, this.client, this.stores, this.repository, this.loadRoles, this.signOut})
      : assert(client != null || (repository != null && loadRoles != null && signOut != null),
            'pass a client, or a repository with loadRoles and signOut (tests)');

  final YazanApiClient? client;
  final AdminStores? stores;

  /// For tests: a ready repository and the detail functions, instead of the client.
  final StaffRepository? repository;
  final StaffRolesLoader? loadRoles;
  final StaffSignOutEverywhere? signOut;

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  late final bool _ownsRepository = widget.repository == null;
  late final StaffRepository _repo = widget.repository ??
      StaffRepository.forClient(widget.client!, store: widget.stores?.feed(staffFeedName));
  late final StaffRolesLoader _loadRoles = widget.loadRoles ?? staffRolesLoader(widget.client!);
  late final StaffSignOutEverywhere _signOut = widget.signOut ?? staffSignOutEverywhere(widget.client!);

  @override
  void dispose() {
    if (_ownsRepository) _repo.dispose();
    super.dispose();
  }

  void _open(StaffMember member) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StaffDetailPage(
          member: member,
          loadRoles: _loadRoles,
          signOut: _signOut,
          permissions: _repo.permissions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.staffTitle)),
      body: StaffListPage(repository: _repo, onOpen: _open),
    );
  }
}
