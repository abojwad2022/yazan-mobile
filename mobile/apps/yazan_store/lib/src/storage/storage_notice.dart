import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Tells the customer, once, that the saved data on this phone could not be read and was reset.
/// It sits above the navigator, so the message is shown on whichever screen is first.
class StorageNotice extends StatefulWidget {
  const StorageNotice({super.key, required this.show, required this.child});

  /// True when the local database was recreated at start-up.
  final bool show;
  final Widget child;

  @override
  State<StorageNotice> createState() => _StorageNoticeState();
}

class _StorageNoticeState extends State<StorageNotice> {
  @override
  void initState() {
    super.initState();
    if (widget.show) WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  void _announce() {
    if (!mounted) return;
    final message = AppLocalizations.of(context).storageReset;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
