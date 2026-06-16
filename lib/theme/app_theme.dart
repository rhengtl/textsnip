import 'package:flutter/material.dart';

/// Centralised brand design system for TextSnip.
///
/// Colours are derived from the app logo: a bright cyan accent over a dark
/// slate, on a near-white surface. Both the main-app screens *and* the
/// (separate-isolate) overlay widgets reference these constants, so the floating
/// bubble and selection UI stay visually consistent with the app even though the
/// overlay isolate has no access to the app's [Theme].
class AppColors {
  AppColors._();

  /// Bright cyan accent from the logo — the primary brand colour.
  static const Color brandCyan = Color(0xFF12A4C4);

  /// Deeper teal used as the second stop of the brand gradient.
  static const Color brandCyanDeep = Color(0xFF0B7C95);

  /// Dark slate from the logo's document frame.
  static const Color brandSlate = Color(0xFF34454F);

  /// Cyan→teal sweep used on the floating bubble and hero accents.
  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandCyan, brandCyanDeep],
  );
}

/// Bundled image assets (registered under `flutter.assets` in pubspec.yaml).
class AppAssets {
  AppAssets._();

  /// Transparent-background logo — composites cleanly over any surface.
  static const String logo = 'assets/images/TextSnip-transparent.png';
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandCyan,
      brightness: brightness,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0.5,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          side: BorderSide(color: scheme.outlineVariant),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
