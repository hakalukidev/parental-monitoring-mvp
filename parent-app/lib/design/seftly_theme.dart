import 'package:flutter/material.dart';

abstract final class SeftlyTokens {
  static const primary = Color(0xFF176B5B);
  static const secondary = Color(0xFF526778);
  static const ink = Color(0xFF192F2A);
  static const canvas = Color(0xFFF5F7F5);
  static const success = Color(0xFF286D46);
  static const warning = Color(0xFF8A5700);
  static const error = Color(0xFFB53333);
  static const gutter = 20.0;
  static const radius = 20.0;
  static const contentWidth = 1100.0;
}

abstract final class SeftlyTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData _build(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: SeftlyTokens.primary,
      brightness: brightness,
      secondary: SeftlyTokens.secondary,
      error: SeftlyTokens.error,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return base.copyWith(
      scaffoldBackgroundColor:
          brightness == Brightness.light ? SeftlyTokens.canvas : colors.surface,
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.0),
        headlineMedium: base.textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.7),
        titleLarge:
            base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium:
            base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: base.textTheme.titleMedium
            ?.copyWith(color: colors.onSurface, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SeftlyTokens.radius),
            side:
                BorderSide(color: colors.outlineVariant.withValues(alpha: .5))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLowest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.outlineVariant)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.outlineVariant)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.primary, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(48, 52),
              shape: shape,
              textStyle: const TextStyle(
                  fontFamily: "Roboto",
                  fontSize: 14,
                  fontWeight: FontWeight.w600))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 50), shape: shape)),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              minimumSize: const Size(48, 48), shape: shape)),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
          elevation: 0,
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          shape: shape),
      dialogTheme: DialogThemeData(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: colors.surface),
      bottomSheetTheme: BottomSheetThemeData(
          showDragHandle: true,
          backgroundColor: colors.surface,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
      snackBarTheme:
          SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: shape),
      dividerTheme: DividerThemeData(
          color: colors.outlineVariant.withValues(alpha: .6), thickness: 1),
      chipTheme: base.chipTheme
          .copyWith(shape: const StadiumBorder(), side: BorderSide.none),
    );
  }
}

extension SeftlyPalette on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  Color get muted => colors.onSurfaceVariant;
}
