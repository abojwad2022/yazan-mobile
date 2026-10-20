import 'dart:math' as math;

import '../cart/cart.dart' show plainText;
import '../json_read.dart';

/// The next membership level and how far away it is.
class NextLevel {
  const NextLevel({required this.name, required this.remaining, required this.progress});

  final String name;

  /// Points still needed.
  final int remaining;

  /// 0 to 1.
  final double progress;
}

/// The customer's loyalty summary: `GET /yazan-rewards/v1/me`.
///
/// The server decides every number; the app only shows them.
class RewardsSummary {
  const RewardsSummary({
    required this.points,
    this.labelSingular = '',
    this.labelPlural = '',
    this.tierName = '',
    this.next,
  });

  /// Throws a [FormatException] when the answer has no points block (a foreign answer is not shown as zero points).
  factory RewardsSummary.fromJson(Map<String, dynamic> j) {
    final points = j['points'];
    if (points is! Map) throw const FormatException('rewards answer without points');
    final p = asMap(points);
    final label = asMap(p['label']);
    final level = asMap(j['level']);
    var tier = plainText(asStr(asMap(j['tier'])['name'])).trim();
    if (tier.isEmpty) tier = plainText(asStr(asMap(level['current'])['name'])).trim();
    NextLevel? next;
    final n = asMap(level['next']);
    final nextName = plainText(asStr(n['name'])).trim();
    if (nextName.isNotEmpty) {
      final progress = n['progress'];
      next = NextLevel(
        name: nextName,
        remaining: math.max(0, asInt(n['remaining']) ?? 0),
        progress: progress is num ? math.min(1.0, math.max(0.0, progress.toDouble())) : 0.0,
      );
    }
    return RewardsSummary(
      points: asInt(p['balance']) ?? 0,
      labelSingular: plainText(asStr(label['singular'])).trim(),
      labelPlural: plainText(asStr(label['plural'])).trim(),
      tierName: tier,
      next: next,
    );
  }

  final int points;

  /// The shop's own word for one point and for several (owner-editable on the website); may be empty.
  final String labelSingular;
  final String labelPlural;

  /// The current tier's name; empty when the customer has none yet.
  final String tierName;
  final NextLevel? next;

  /// The word for the balance: singular for exactly one point, plural otherwise; null when the
  /// server named none.
  String? get label {
    final word = points == 1 ? labelSingular : labelPlural;
    if (word.isNotEmpty) return word;
    final other = points == 1 ? labelPlural : labelSingular;
    return other.isEmpty ? null : other;
  }
}

/// The customer's referral code: `GET /yazan-rewards/v1/referral`.
class ReferralInfo {
  const ReferralInfo({required this.code, this.link = ''});

  /// Throws a [FormatException] when the answer has no code.
  factory ReferralInfo.fromJson(Map<String, dynamic> j) {
    final code = asStr(j['code']).trim();
    if (code.isEmpty) throw const FormatException('referral answer without a code');
    return ReferralInfo(code: code, link: asStr(j['link']).trim());
  }

  final String code;
  final String link;
}
