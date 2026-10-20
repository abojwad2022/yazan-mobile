import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_design_system/yazan_design_system.dart';

void main() {
  test('both theme variants use the brand gold as primary', () {
    for (final v in YazanThemeVariant.values) {
      expect(yazanTheme(v).colorScheme.primary, YazanColors.gold);
    }
    expect(yazanTheme(YazanThemeVariant.black).scaffoldBackgroundColor, YazanColors.obsidian);
    expect(yazanTheme(YazanThemeVariant.burgundy).scaffoldBackgroundColor, YazanColors.burgundy);
  });

  testWidgets('StaleBadge renders in right-to-left without overflow', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: yazanTheme(YazanThemeVariant.black),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: StaleBadge(label: 'قديم'))),
      ),
    ));
    expect(find.text('قديم'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
