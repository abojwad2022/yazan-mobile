import 'package:flutter/material.dart';

/// Shown on any data that came from the cache while the network was unreachable.
class StaleBadge extends StatelessWidget {
  const StaleBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Directional padding: correct in both LTR (English) and RTL (Arabic).
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// The one heading of a screen, in the brand's serif display face (the website pairs a serif
/// display with a clean sans). Uses the phone's own serif (Noto Serif on Android, Georgia / New
/// York on iOS) so no font has to ship with the app; Arabic falls back to the system Naskh.
class YazanHeading extends StatelessWidget {
  const YazanHeading(this.text, {super.key, this.textAlign});

  final String text;
  final TextAlign? textAlign;

  /// The serif families tried in order.
  static const fontFamily = 'serif';
  static const fontFamilyFallback = <String>['Noto Serif', 'Georgia', 'Times New Roman', 'Noto Naskh Arabic'];

  /// The heading style on top of [theme]'s `headlineSmall`.
  static TextStyle style(ThemeData theme) => (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.3,
        height: 1.25,
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(text, textAlign: textAlign, style: style(Theme.of(context))),
    );
  }
}
