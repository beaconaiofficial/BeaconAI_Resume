import 'package:flutter/material.dart';

/// BeaconAI Resume — Color Palette
/// All colors sourced from BeaconAI_Resume_Instructions.md §15
/// Rule: aiIndicator (#7C3AED purple) is used EXCLUSIVELY for Claude-prefilled content.
/// No other UI element may use this color.
class AppColors {
  AppColors._();

  // ── Light Mode ──────────────────────────────────────────────────────────────

  /// Warm off-white — base app background. Evokes high-quality paper.
  static const Color backgroundLight = Color(0xFFFAFAF8);

  /// Pure white — cards, editors, modals, input fields.
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// Deep navy-charcoal — primary text. Professional without pure-black harshness.
  static const Color primaryTextLight = Color(0xFF1A1A2E);

  /// Mid-gray — labels, hints, placeholder text, metadata.
  static const Color secondaryTextLight = Color(0xFF6B7280);

  /// Medium navy — CTAs, buttons, active states, progress bars, links.
  static const Color accentLightColor = Color(0xFF2C4A7C);

  /// Very light navy tint — selected states, highlighted rows, tier badges, focused fields.
  static const Color accentLightTint = Color(0xFFEEF2FF);

  /// Clean green — ATS score good states, completion checkmarks, valid field indicators.
  static const Color successLight = Color(0xFF16A34A);

  /// Amber — ATS score mid-range, expiring certifications, soft warnings.
  static const Color warningLight = Color(0xFFD97706);

  /// Red — validation errors, blocked save states, failed extractions.
  static const Color errorLight = Color(0xFFDC2626);

  /// Purple — AI prefill badge ONLY. Visually distinct from all other UI states.
  /// RULE: Never use this color for any purpose other than Claude-populated field indicators.
  static const Color aiIndicator = Color(0xFF7C3AED);

  /// Light gray — section dividers, input field borders, card outlines.
  static const Color borderLight = Color(0xFFE5E7EB);

  // ── Dark Mode ───────────────────────────────────────────────────────────────

  /// Deep navy-black — dark mode base background.
  static const Color backgroundDark = Color(0xFF111118);

  /// Slightly lighter navy — dark mode cards and editors.
  static const Color surfaceDark = Color(0xFF1C1C27);

  /// Near-white — dark mode primary text.
  static const Color primaryTextDark = Color(0xFFF1F1F3);

  /// Lighter gray — dark mode secondary text.
  static const Color secondaryTextDark = Color(0xFF9CA3AF);

  /// Lighter navy — dark mode accent, maintains contrast on dark backgrounds.
  static const Color accentDark = Color(0xFF4F7AC7);

  /// Dark mode accent light tint.
  static const Color accentLightTintDark = Color(0xFF1E2A3D);

  /// Dark mode success — slightly lightened for dark background contrast.
  static const Color successDark = Color(0xFF22C55E);

  /// Dark mode warning — slightly lightened for dark background contrast.
  static const Color warningDark = Color(0xFFFBBF24);

  /// Dark mode error — slightly lightened for dark background contrast.
  static const Color errorDark = Color(0xFFF87171);

  /// AI indicator is the same in both modes — purple is sufficiently distinct.
  static const Color aiIndicatorDark = Color(0xFF9F67FF);

  /// Dark mode border.
  static const Color borderDark = Color(0xFF374151);

  // ── App Icon Brand Colors (reference only — not used in UI) ─────────────────

  /// Parchment scroll foreground color.
  static const Color iconParchment = Color(0xFFF5E6C8);

  /// Quill deep navy.
  static const Color iconNavy = Color(0xFF1A1A2E);

  /// Gold nib accent.
  static const Color iconGold = Color(0xFFB8860B);

  // ── High Contrast Palette ───────────────────────────────────────────────────
  // Used when MediaQuery.highContrast is true OR highContrastOverride is true.
  // Targets WCAG AAA (7:1 contrast ratio).

  static const Color backgroundHighContrast = Color(0xFFFFFFFF);
  static const Color surfaceHighContrast = Color(0xFFFFFFFF);
  static const Color primaryTextHighContrast = Color(0xFF000000);
  static const Color secondaryTextHighContrast = Color(0xFF1A1A1A);
  static const Color accentHighContrast = Color(0xFF00008B);
  static const Color successHighContrast = Color(0xFF006400);
  static const Color warningHighContrast = Color(0xFF8B4500);
  static const Color errorHighContrast = Color(0xFF8B0000);
  static const Color aiIndicatorHighContrast = Color(0xFF4B0082);
  static const Color borderHighContrast = Color(0xFF000000);
}
