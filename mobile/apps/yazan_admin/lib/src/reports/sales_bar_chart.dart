import 'package:flutter/material.dart';

import 'reports_snapshot.dart';

/// Daily net revenue as bars, drawn with a [CustomPaint] (no chart package).
///
/// The time axis always runs left to right, like the digits of the dates and amounts around it, so
/// the chart reads the same in English and Arabic. Bars are scaled to the highest day; a day with
/// no sales keeps a hairline so the gap is visible. The chart is one semantic node described by
/// [semanticsLabel] (the individual bars carry no meaning for a screen reader).
class SalesBarChart extends StatelessWidget {
  const SalesBarChart({
    super.key,
    required this.series,
    required this.semanticsLabel,
    this.height = 120,
  });

  final List<DaySales> series;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            key: const ValueKey('reports-chart-paint'),
            painter: SalesBarPainter(
              values: [for (final d in series) d.total],
              barColor: scheme.primary,
              baseColor: scheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints [values] as evenly spaced bars. Public so tests can check what it would draw.
class SalesBarPainter extends CustomPainter {
  SalesBarPainter({required this.values, required this.barColor, required this.baseColor});

  final List<double> values;
  final Color barColor;
  final Color baseColor;

  /// The highest value, or 0 when there is none above zero.
  double get maxValue => values.fold<double>(0, (m, v) => v > m ? v : m);

  /// The bar height for [value] in a chart [height] tall: 0 for no sales, otherwise at least 2.
  double barHeight(double value, double height) {
    final max = maxValue;
    if (max <= 0 || value <= 0) return 0;
    final h = value / max * height;
    return h < 2 ? 2 : h;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = baseColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), base);
    if (values.isEmpty) return;

    final slot = size.width / values.length;
    final gap = slot > 6 ? slot * 0.2 : 1.0;
    final barWidth = (slot - gap).clamp(1.0, double.infinity);
    final paint = Paint()..color = barColor;
    final chartHeight = size.height - 1;
    for (var i = 0; i < values.length; i++) {
      final h = barHeight(values[i], chartHeight);
      if (h <= 0) continue;
      final left = i * slot + gap / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, chartHeight - h, barWidth, h),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(SalesBarPainter old) =>
      !_same(old.values, values) || old.barColor != barColor || old.baseColor != baseColor;

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
