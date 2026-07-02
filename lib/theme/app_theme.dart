import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// BeaconAI Resume — Theme System
/// Typography sourced from BeaconAI_Resume_Instructions.md §15
/// Fonts: Playfair Display (display/headlines), Inter (UI body), JetBrains Mono (data)
/// Rule §8: Never use hardcoded pixel font sizes — always use TextTheme styles
///          so textScaleFactor is respected throughout the app.
class AppTheme {
  AppTheme._();

  // ── Text Themes ─────────────────────────────────────────────────────────────

  static TextTheme _buildTextTheme() {
    return TextTheme(
      // Playfair Display — screen titles (e.g. 'Your Resume', 'Interview Prep')
      displayLarge: GoogleFonts.playfairDisplay(
        fontSize: 32,
        fontWeight: FontWeight.w700,
      ),

      // Playfair Display — section headings within screens
      headlineMedium: GoogleFonts.playfairDisplay(
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),

      // Inter — card titles, resume names, document titles in My Documents
      titleLarge: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),

      // Inter — section tab labels, form group labels
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),

      // Inter — primary body text, form field input text
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
      ),

      // Inter — secondary body text, bullet content, list items
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),

      // Inter — button labels, CTA text
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),

      // Inter — field hints, character counters, metadata
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
      ),

      // JetBrains Mono — ATS score display, dates, counters
      // Accessed via Theme.of(context).textTheme.bodySmall when mono is needed,
      // or use AppTheme.monoStyle(context) helper below.
      bodySmall: GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  // ── Light Theme ─────────────────────────────────────────────────────────────

  static ThemeData get light {
    final textTheme = _buildTextTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.accentLightColor,
        onPrimary: Colors.white,
        primaryContainer: AppColors.accentLightTint,
        onPrimaryContainer: AppColors.accentLightColor,
        secondary: AppColors.accentLightColor,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.accentLightTint,
        onSecondaryContainer: AppColors.accentLightColor,
        surface: AppColors.surfaceLight,
        onSurface: AppColors.primaryTextLight,
        surfaceContainerHighest: AppColors.backgroundLight,
        onSurfaceVariant: AppColors.secondaryTextLight,
        error: AppColors.errorLight,
        onError: Colors.white,
        errorContainer: Color(0xFFFEE2E2),
        onErrorContainer: AppColors.errorLight,
        outline: AppColors.borderLight,
        outlineVariant: AppColors.borderLight,
        scrim: Color(0x52000000),
        inverseSurface: AppColors.primaryTextLight,
        onInverseSurface: AppColors.surfaceLight,
        inversePrimary: AppColors.accentLightTint,
      ),
      scaffoldBackgroundColor: AppColors.backgroundLight,
      cardColor: AppColors.surfaceLight,
      dividerColor: AppColors.borderLight,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundLight,
        foregroundColor: AppColors.primaryTextLight,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: GoogleFonts.playfairDisplay(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryTextLight,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentLightColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48), // Rule: 48x48dp minimum tap target
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accentLightColor,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: AppColors.accentLightColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentLightColor,
          minimumSize: const Size(0, 48),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: AppColors.accentLightColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.errorLight, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.errorLight, width: 2),
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.secondaryTextLight,
        ),
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.secondaryTextLight,
        ),
        errorStyle: GoogleFonts.inter(
          fontSize: 12,
          color: AppColors.errorLight,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderLight),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.accentLightTint,
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.accentLightColor,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentLightColor,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceLight,
        selectedItemColor: AppColors.accentLightColor,
        unselectedItemColor: AppColors.secondaryTextLight,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accentLightColor,
        unselectedLabelColor: AppColors.secondaryTextLight,
        indicatorColor: AppColors.accentLightColor,
        labelStyle:
            GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 14),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentLightColor,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.primaryTextLight,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.surfaceLight,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Dark Theme ──────────────────────────────────────────────────────────────

  static ThemeData get dark {
    final textTheme = _buildTextTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.accentDark,
        onPrimary: Colors.white,
        primaryContainer: AppColors.accentLightTintDark,
        onPrimaryContainer: AppColors.accentDark,
        secondary: AppColors.accentDark,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.accentLightTintDark,
        onSecondaryContainer: AppColors.accentDark,
        surface: AppColors.surfaceDark,
        onSurface: AppColors.primaryTextDark,
        surfaceContainerHighest: AppColors.backgroundDark,
        onSurfaceVariant: AppColors.secondaryTextDark,
        error: AppColors.errorDark,
        onError: Colors.white,
        errorContainer: Color(0xFF7F1D1D),
        onErrorContainer: AppColors.errorDark,
        outline: AppColors.borderDark,
        outlineVariant: AppColors.borderDark,
        scrim: Color(0x52000000),
        inverseSurface: AppColors.primaryTextDark,
        onInverseSurface: AppColors.surfaceDark,
        inversePrimary: AppColors.accentLightTintDark,
      ),
      scaffoldBackgroundColor: AppColors.backgroundDark,
      cardColor: AppColors.surfaceDark,
      dividerColor: AppColors.borderDark,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.primaryTextDark,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: GoogleFonts.playfairDisplay(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryTextDark,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentDark,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accentDark,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: AppColors.accentDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentDark,
          minimumSize: const Size(0, 48),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accentDark, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.errorDark, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.errorDark, width: 2),
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.secondaryTextDark,
        ),
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.secondaryTextDark,
        ),
        errorStyle: GoogleFonts.inter(
          fontSize: 12,
          color: AppColors.errorDark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderDark),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.accentLightTintDark,
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.accentDark,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentDark,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        selectedItemColor: AppColors.accentDark,
        unselectedItemColor: AppColors.secondaryTextDark,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accentDark,
        unselectedLabelColor: AppColors.secondaryTextDark,
        indicatorColor: AppColors.accentDark,
        labelStyle:
            GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 14),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentDark,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.primaryTextDark,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.surfaceDark,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Convenience Helpers ─────────────────────────────────────────────────────

  /// JetBrains Mono style for ATS scores, dates, counters.
  /// Usage: style: AppTheme.monoStyle(context)
  static TextStyle monoStyle(BuildContext context) {
    return GoogleFonts.jetBrainsMono(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  /// Returns the correct AI indicator color for current brightness.
  static Color aiIndicatorColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.aiIndicatorDark
        : AppColors.aiIndicator;
  }

  /// Returns the correct success color for current brightness.
  static Color successColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.successDark
        : AppColors.successLight;
  }

  /// Returns the correct warning color for current brightness.
  static Color warningColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.warningDark
        : AppColors.warningLight;
  }

  /// Returns the correct error color for current brightness.
  static Color errorColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.errorDark
        : AppColors.errorLight;
  }
}
