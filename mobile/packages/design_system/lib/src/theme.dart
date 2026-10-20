import 'package:flutter/material.dart';

/// YAZAN brand palette: obsidian, agate carnelian, aged silver, restrained gold.
/// Two per-visitor themes mirror the website's Black and Burgundy.
class YazanColors {
  const YazanColors._();

  static const obsidian = Color(0xFF0E0E10);
  static const carnelian = Color(0xFF9C2A1F);
  static const burgundy = Color(0xFF5A1426);
  static const silver = Color(0xFFB8B8BC);
  static const gold = Color(0xFFB89B5E);
  static const ivory = Color(0xFFF5F1EA);
}

enum YazanThemeVariant { black, burgundy }

ThemeData yazanTheme(YazanThemeVariant variant) {
  final background =
      variant == YazanThemeVariant.black ? YazanColors.obsidian : YazanColors.burgundy;
  final scheme = ColorScheme.dark(
    surface: background,
    primary: YazanColors.gold,
    onPrimary: YazanColors.obsidian,
    secondary: YazanColors.carnelian,
    onSurface: YazanColors.ivory,
    outline: YazanColors.silver,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: YazanColors.ivory,
      elevation: 0,
    ),
    // Touch targets of at least 48dp for accessibility.
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
