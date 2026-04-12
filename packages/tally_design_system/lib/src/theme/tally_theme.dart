import 'package:flutter/material.dart';

import '../tokens/tally_colors.dart';

ThemeData buildTallyTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: TallyColors.seed,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: TallyColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: TallyColors.canvas,
      foregroundColor: TallyColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: TallyColors.actionPrimary,
      foregroundColor: Colors.white,
    ),
  );
}
