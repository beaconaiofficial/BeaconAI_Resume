import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/user_settings_provider.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AccessibilitySettingsScreen
//
// Spec §4 / §12 (Settings: Accessibility):
//   In-app accessibility overrides, all optional. Each defaults to "Follow
//   Device Setting" until changed.
//   (1) Text Size — slider 80%-200%, overrides device font scale in-app only.
//   (2) High Contrast Mode — toggle; forces high-contrast palette app-wide.
//   (3) Reduce Motion — toggle; disables non-essential animations.
//   (4) Screen Reader Hints — toggle (on by default); extended Semantics
//       labels on complex widgets (ATS ring, skill rows, etc.).
//   Device-level screen reader, font scale, contrast, and motion settings
//   are always respected automatically regardless of these overrides.
//
// All four fields applied via the top-level MediaQuery.copyWith() wrapper
// in main.dart — this screen only reads/writes UserSettings through
// userSettingsProvider; it does not apply the overrides itself.
// ─────────────────────────────────────────────────────────────────────────────

class AccessibilitySettingsScreen extends ConsumerWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);
    final notifier = ref.read(userSettingsProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Accessibility',
            style: GoogleFonts.playfairDisplay(
                fontSize: 20, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _IntroBanner(isDark: isDark),
          const SizedBox(height: 20),

          // ── Text Size ────────────────────────────────────────────────────
          _AccessibilityCard(
            isDark: isDark,
            icon: Icons.text_fields,
            title: 'Text Size',
            description:
                'Overrides your device\'s font scale within this app only.',
            child: _TextSizeSlider(
              currentScale: settings.fontScaleOverride,
              onChanged: (value) => notifier.setFontScaleOverride(value),
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 12),

          // ── High Contrast Mode ──────────────────────────────────────────
          _AccessibilityCard(
            isDark: isDark,
            icon: Icons.contrast,
            title: 'High Contrast Mode',
            description:
                'Forces dark text on light backgrounds and removes low-opacity elements app-wide.',
            child: _OverrideToggle(
              value: settings.highContrastOverride,
              isDark: isDark,
              onChanged: (value) => notifier.setHighContrastOverride(value),
            ),
          ),
          const SizedBox(height: 12),

          // ── Reduce Motion ────────────────────────────────────────────────
          _AccessibilityCard(
            isDark: isDark,
            icon: Icons.motion_photos_off_outlined,
            title: 'Reduce Motion',
            description:
                'Disables transitions and replaces loading spinners with static indicators.',
            child: _OverrideToggle(
              value: settings.reduceMotionOverride,
              isDark: isDark,
              onChanged: (value) => notifier.setReduceMotionOverride(value),
            ),
          ),
          const SizedBox(height: 12),

          // ── Screen Reader Hints ──────────────────────────────────────────
          _AccessibilityCard(
            isDark: isDark,
            icon: Icons.record_voice_over_outlined,
            title: 'Screen Reader Hints',
            description:
                'Adds extended descriptions to complex elements like the ATS score ring and skill rows for VoiceOver and TalkBack. On by default.',
            child: Align(
              alignment: Alignment.centerLeft,
              child: Switch(
                value: settings.screenReaderHintsEnabled,
                onChanged: (value) => notifier.setScreenReaderHints(value),
              ),
            ),
          ),

          const SizedBox(height: 24),
          _DeviceSettingsNote(isDark: isDark),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Intro Banner
// ─────────────────────────────────────────────────────────────────────────────

class _IntroBanner extends StatelessWidget {
  const _IntroBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Each setting below defaults to "Follow Device Setting" until you change it.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Accessibility Card — shared container for each of the four settings
// ─────────────────────────────────────────────────────────────────────────────

class _AccessibilityCard extends StatelessWidget {
  const _AccessibilityCard({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final bool isDark;
  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 10),
              Text(title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          Text(description,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text Size Slider — 80% to 200%, null = follow device
// ─────────────────────────────────────────────────────────────────────────────

class _TextSizeSlider extends StatelessWidget {
  const _TextSizeSlider({
    required this.currentScale,
    required this.onChanged,
    required this.isDark,
  });

  final double? currentScale;
  final ValueChanged<double?> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final isFollowingDevice = currentScale == null;
    final sliderValue = currentScale ?? 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isFollowingDevice
                    ? 'Following device setting'
                    : '${(sliderValue * 100).round()}%',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isFollowingDevice
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : accent,
                ),
              ),
            ),
            if (!isFollowingDevice)
              TextButton(
                onPressed: () => onChanged(null),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Reset', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        Semantics(
          label: 'Text size',
          value: '${(sliderValue * 100).round()} percent',
          slider: true,
          child: Slider(
            value: sliderValue.clamp(0.8, 2.0),
            min: 0.8,
            max: 2.0,
            divisions: 24,
            activeColor: accent,
            onChanged: onChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('80%',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              Text('200%',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Override Toggle — tri-state (Follow Device / On / Off) for High Contrast
// and Reduce Motion, both of which are nullable bool overrides.
// ─────────────────────────────────────────────────────────────────────────────

class _OverrideToggle extends StatelessWidget {
  const _OverrideToggle({
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  final bool? value;
  final bool isDark;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    Widget segment(String label, bool? segmentValue) {
      final isSelected = value == segmentValue;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(segmentValue),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          segment('Device', null),
          segment('On', true),
          segment('Off', false),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Device Settings Note
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceSettingsNote extends StatelessWidget {
  const _DeviceSettingsNote({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'Your device-level screen reader, font scale, contrast, and motion '
        'settings are always respected automatically, regardless of the '
        'overrides above.',
        style: GoogleFonts.inter(
          fontSize: 11.5,
          height: 1.5,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
