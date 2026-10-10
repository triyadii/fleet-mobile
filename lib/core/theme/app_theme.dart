import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand palette shared by the theme and a few custom-painted widgets.
abstract final class AppColors {
  static const Color brand = Color(0xFF2563EB); // blue-600
  static const Color brandDeep = Color(0xFF1E3A8A); // blue-900
  static const Color ink = Color(0xFF0F172A); // slate-900
  static const Color accent = Color(0xFF38BDF8); // sky-400
  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);
}

/// Spacing & radius scale. Use these instead of magic numbers.
abstract final class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;

  /// Max content width so tablets/landscape don't stretch the layout.
  static const double maxContentWidth = 640;
}

/// Material 3 theme built on Plus Jakarta Sans.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: brightness,
      primary: isDark ? const Color(0xFF7AA2FF) : AppColors.brand,
      error: AppColors.danger,
      surface: isDark ? const Color(0xFF0B1220) : const Color(0xFFF6F8FC),
    );

    // Plus Jakarta Sans: modern geometric sans, highly legible at small sizes.
    // `decoration: none` is applied explicitly so no text is ever underlined.
    final baseText =
        GoogleFonts.plusJakartaSansTextTheme(
          ThemeData(brightness: brightness).textTheme,
        ).apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          decoration: TextDecoration.none,
        );
    final textTheme = baseText.copyWith(
      titleLarge: baseText.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
      titleSmall: baseText.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      labelLarge: baseText.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 14, height: 1.4),
      bodySmall: baseText.bodySmall?.copyWith(
        fontSize: 12,
        color: scheme.onSurfaceVariant,
      ),
    );

    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Insets.radiusMd),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // Compact default icon size; avoids the oversized look on small phones.
      iconTheme: IconThemeData(size: 20, color: scheme.onSurfaceVariant),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
        iconTheme: IconThemeData(size: 22, color: scheme.onSurface),
        systemOverlayStyle: _overlayStyle(isDark),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark ? const Color(0xFF111A2E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Insets.radiusLg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: rounded,
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
          iconSize: 20,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: rounded,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(iconSize: 20),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF16213A) : const Color(0xFFF1F4FA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Insets.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Insets.radiusMd),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Insets.radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Insets.radiusMd),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: rounded,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Insets.radiusLg),
        ),
        titleTextStyle: textTheme.titleMedium,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
    );
  }

  /// Transparent system bars for edge-to-edge drawing; content is kept clear
  /// of them with `SafeArea` / view padding in each screen.
  static SystemUiOverlayStyle _overlayStyle(bool isDark) =>
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      );
}
