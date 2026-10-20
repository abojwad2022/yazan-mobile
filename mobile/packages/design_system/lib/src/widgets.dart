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
