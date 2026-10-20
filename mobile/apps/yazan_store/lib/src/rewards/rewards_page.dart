import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../account/account_widgets.dart';
import '../account/failure.dart';
import 'rewards_api.dart';
import 'rewards_models.dart';

/// The customer's points balance, tier and referral code. Read only and online: the numbers are the
/// server's, and the screen shows nothing it did not just receive.
///
/// Reaching it needs an account (the caller asks guests to sign in first).
class RewardsPage extends StatefulWidget {
  const RewardsPage({super.key, required this.api, required this.onSessionEnded});

  final RewardsApi api;

  /// Called when the server says the session is over.
  final VoidCallback onSessionEnded;

  @override
  State<RewardsPage> createState() => _RewardsPageState();
}

class _RewardsPageState extends State<RewardsPage> {
  RewardsSummary? _summary;
  Failure? _summaryFailure;
  ReferralInfo? _referral;
  Failure? _referralFailure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<T> _guard<T>(Future<T> Function() call, void Function(Failure) onFailure, T fallback) async {
    try {
      return await call();
    } catch (e) {
      onFailure(Failure.from(e));
      return fallback;
    }
  }

  Future<void> _load() async {
    Failure? summaryFailure;
    Failure? referralFailure;
    final results = await Future.wait<Object?>([
      _guard<RewardsSummary?>(widget.api.summary, (f) => summaryFailure = f, null),
      _guard<ReferralInfo?>(widget.api.referral, (f) => referralFailure = f, null),
    ]);
    if (!mounted) return;
    if ((summaryFailure?.isSignedOut ?? false) || (referralFailure?.isSignedOut ?? false)) {
      endSession(context, widget.onSessionEnded);
      return;
    }
    setState(() {
      _summary = results[0] as RewardsSummary?;
      _summaryFailure = summaryFailure;
      _referral = results[1] as ReferralInfo?;
      _referralFailure = referralFailure;
      _loading = false;
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _summaryFailure = null;
      _referralFailure = null;
    });
    await _load();
  }

  Future<void> _copy(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = AppLocalizations.of(context).rewardsCopied;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copied)));
  }

  /// The words for a failure; a rewards system that is switched off reads as "not available".
  String _message(AppLocalizations l, Failure f) {
    if (f.kind == FailureKind.notFound || f.kind == FailureKind.unavailable) {
      return l.rewardsUnavailable;
    }
    return failureMessage(l, f);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final summary = _summary;
    final summaryFailure = _summaryFailure;
    final Widget body;
    if (summary == null) {
      if (_loading) {
        body = const Center(child: CircularProgressIndicator());
      } else {
        body = MessageView(
          text: summaryFailure == null ? l.genericError : _message(l, summaryFailure),
          onRetry: _reload,
        );
      }
    } else {
      body = RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.all(16),
          children: [
            _BalanceCard(summary: summary),
            const SizedBox(height: 16),
            _ReferralCard(
              info: _referral,
              failure: _referralFailure,
              loading: _loading,
              onRetry: _reload,
              onCopy: _copy,
              message: _message,
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.rewards)),
      body: body,
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});

  final RewardsSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final next = summary.next;
    final tier = summary.tierName.isEmpty ? l.rewardsNoTier : summary.tierName;
    final label = summary.label ?? l.pointsDefault;
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.rewardsBalance, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${summary.points}', style: theme.textTheme.displaySmall),
                const SizedBox(width: 8),
                Flexible(child: Text(label, style: theme.textTheme.titleMedium)),
              ],
            ),
            const Divider(height: 32),
            Text(l.rewardsTier, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.workspace_premium_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text(tier, style: theme.textTheme.titleMedium)),
              ],
            ),
            if (next != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: next.progress),
              const SizedBox(height: 4),
              Text(
                l.rewardsNextLevel(next.remaining, label, next.name),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReferralCard extends StatelessWidget {
  const _ReferralCard({
    required this.info,
    required this.failure,
    required this.loading,
    required this.onRetry,
    required this.onCopy,
    required this.message,
  });

  final ReferralInfo? info;
  final Failure? failure;
  final bool loading;
  final VoidCallback onRetry;
  final ValueChanged<String> onCopy;
  final String Function(AppLocalizations, Failure) message;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final referral = info;
    final Widget content;
    if (referral != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SelectableText(
                    referral.code,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ),
              IconButton(
                tooltip: l.rewardsCopyCode,
                onPressed: () => onCopy(referral.code),
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          if (referral.link.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(l.rewardsReferralLink, style: theme.textTheme.bodySmall),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SelectableText(
                      referral.link,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l.rewardsCopyLink,
                  onPressed: () => onCopy(referral.link),
                  icon: const Icon(Icons.link),
                ),
              ],
            ),
          ],
        ],
      );
    } else if (loading) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      final f = failure;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f == null ? l.rewardsReferralFailed : message(l, f)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: Text(l.retry)),
        ],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.rewardsReferral, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l.rewardsReferralHelp, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
    );
  }
}
