import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';
import '../models/app_enums.dart';
import '../providers/user_settings_provider.dart';
import '../services/bug_report_service.dart';
import '../services/dev_extraction_cache.dart';
import '../services/external_link_service.dart';
import '../services/hive_service.dart';
import '../theme/app_colors.dart';

const String _websiteUrl = 'https://getbeaconai.dev';
const String _websiteDisplay = 'getbeaconai.dev';

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen
//
// Spec §4 (Settings):
//   Divided into sections: (1) Account — manage subscription, privacy policy
//   link. (2) Preferences — default export format, app theme (light/dark/
//   system). (3) Accessibility — in-app overrides. (4) Storage — upload
//   usage per resume, total local storage used, link to Backup & Restore.
//   No internet required for most settings.
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);
    final notifier = ref.read(userSettingsProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Settings',
            style: GoogleFonts.playfairDisplay(
                fontSize: 20, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => Navigator.pushNamedAndRemoveUntil(
              context,
              AppConstants.routeDashboard,
              (route) => false,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _SettingsSection(
            title: 'Account',
            isDark: isDark,
            children: [
              _TierRow(tier: settings.tier, isDark: isDark),
              _SettingsTile(
                icon: Icons.workspace_premium_outlined,
                label: settings.tier.isFree
                    ? 'Upgrade Subscription'
                    : 'Manage Subscription',
                isDark: isDark,
                onTap: () =>
                    Navigator.pushNamed(context, AppConstants.routePaywall),
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                isDark: isDark,
                onTap: () => Navigator.pushNamed(
                    context, AppConstants.routePrivacyPolicy,
                    arguments: {'isReview': true}),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SettingsSection(
            title: 'Preferences',
            isDark: isDark,
            children: [
              _ThemeSelector(
                currentTheme: settings.theme,
                isDark: isDark,
                onChanged: notifier.setTheme,
              ),
              _ExportFormatSelector(
                currentFormat: settings.defaultExportFormat,
                tier: settings.tier,
                isDark: isDark,
                onChanged: notifier.setDefaultExportFormat,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SettingsSection(
            title: 'Accessibility',
            isDark: isDark,
            children: [
              _SettingsTile(
                icon: Icons.accessibility_new_outlined,
                label: 'Accessibility Settings',
                isDark: isDark,
                onTap: () => Navigator.pushNamed(
                    context, AppConstants.routeSettingsAccessibility),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SettingsSection(
            title: 'Storage',
            isDark: isDark,
            children: [
              _StorageSummary(isDark: isDark),
              _SettingsTile(
                icon: Icons.cloud_upload_outlined,
                label: 'Backup & Restore',
                isDark: isDark,
                onTap: () => Navigator.pushNamed(
                    context, AppConstants.routeBackupRestore),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SettingsSection(
            title: 'Support',
            isDark: isDark,
            children: [
              _SettingsTile(
                icon: Icons.bug_report_outlined,
                label: 'Report a Bug',
                isDark: isDark,
                onTap: () => _reportBug(context),
              ),
            ],
          ),
          // Only ever visible when DevExtractionCache._enabled has been
          // manually flipped to true in a local debug build — invisible in
          // every normal debug run and every release build. See FIX 8.
          if (DevExtractionCache.isActive) ...[
            const SizedBox(height: 20),
            _SettingsSection(
              title: 'Developer',
              isDark: isDark,
              children: [
                _SettingsTile(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Clear extraction cache',
                  isDark: isDark,
                  onTap: () async {
                    await DevExtractionCache.clear();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Dev extraction cache cleared')),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          _WebsiteFooterLink(isDark: isDark),
        ],
      ),
    );
  }
}

// Launches the bug-report mailto link; falls back to a copyable-email
// dialog if no mail handler is available (common on web/desktop).
Future<void> _reportBug(BuildContext context) async {
  final launched = await BugReportService.sendBugReport();
  if (launched || !context.mounted) return;

  await _showCopyableFallbackDialog(
    context,
    title: 'Report a Bug',
    message:
        "We couldn't open a mail app on this device. Please email us directly at:",
    displayText: BugReportService.supportEmail,
    copyLabel: 'Copy Email',
    copiedMessage: 'Email address copied',
  );
}

// Opens the website footer link; falls back to a copyable-URL dialog if no
// browser handler is available (more common on web/desktop than mobile).
Future<void> _openWebsite(BuildContext context) async {
  final launched = await ExternalLinkService.open(_websiteUrl);
  if (launched || !context.mounted) return;

  await _showCopyableFallbackDialog(
    context,
    title: 'Visit Our Website',
    message: "We couldn't open a browser on this device. Please visit:",
    displayText: _websiteDisplay,
    copyLabel: 'Copy Link',
    copiedMessage: 'Website address copied',
  );
}

// Shared fallback for every external-link action in Settings (bug report,
// website): a dialog showing the destination as selectable text plus a
// one-tap copy, for the common no-handler-configured case on web/desktop.
Future<void> _showCopyableFallbackDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String displayText,
  required String copyLabel,
  required String copiedMessage,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title,
          style: GoogleFonts.playfairDisplay(
              fontSize: 18, fontWeight: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: GoogleFonts.inter(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 10),
          SelectableText(
            displayText,
            style: GoogleFonts.inter(
                fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: displayText));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(copiedMessage)),
            );
          },
          child: Text(copyLabel),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Container
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.isDark,
    required this.children,
  });

  final String title;
  final bool isDark;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(height: 1, color: border, indent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple Navigation Tile
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tier Row — current subscription status
// ─────────────────────────────────────────────────────────────────────────────

class _TierRow extends StatelessWidget {
  const _TierRow({required this.tier, required this.isDark});
  final TierEnum tier;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 18, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Current Plan',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              tier.displayName,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme Selector
// ─────────────────────────────────────────────────────────────────────────────

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({
    required this.currentTheme,
    required this.isDark,
    required this.onChanged,
  });

  final AppThemeEnum currentTheme;
  final bool isDark;
  final ValueChanged<AppThemeEnum> onChanged;

  String _label(AppThemeEnum t) => switch (t) {
        AppThemeEnum.system => 'System',
        AppThemeEnum.light => 'Light',
        AppThemeEnum.dark => 'Dark',
      };

  IconData _icon(AppThemeEnum t) => switch (t) {
        AppThemeEnum.system => Icons.brightness_auto_outlined,
        AppThemeEnum.light => Icons.light_mode_outlined,
        AppThemeEnum.dark => Icons.dark_mode_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon(currentTheme), size: 18, color: accent),
              const SizedBox(width: 12),
              Text(
                'App Theme',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: AppThemeEnum.values.map((t) {
              final isSelected = t == currentTheme;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => onChanged(t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent
                            : (isDark
                                ? AppColors.backgroundDark
                                : AppColors.backgroundLight),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? accent
                              : (isDark
                                  ? AppColors.borderDark
                                  : AppColors.borderLight),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _label(t),
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
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Default Export Format Selector — gated to tier-available formats
// ─────────────────────────────────────────────────────────────────────────────

class _ExportFormatSelector extends StatelessWidget {
  const _ExportFormatSelector({
    required this.currentFormat,
    required this.tier,
    required this.isDark,
    required this.onChanged,
  });

  final ExportFormatEnum currentFormat;
  final TierEnum tier;
  final bool isDark;
  final ValueChanged<ExportFormatEnum> onChanged;

  String _label(ExportFormatEnum f) => switch (f) {
        ExportFormatEnum.pdf => 'PDF',
        ExportFormatEnum.docx => 'DOCX',
        ExportFormatEnum.plainText => 'TXT',
      };

  bool _isAvailable(ExportFormatEnum f) => switch (f) {
        ExportFormatEnum.pdf => true,
        ExportFormatEnum.docx => tier.isPaid,
        ExportFormatEnum.plainText => tier.isPro,
      };

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, size: 18, color: accent),
              const SizedBox(width: 12),
              Text(
                'Default Export Format',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: ExportFormatEnum.values.map((f) {
              final isSelected = f == currentFormat;
              final available = _isAvailable(f);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: available ? () => onChanged(f) : null,
                    child: Opacity(
                      opacity: available ? 1.0 : 0.4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? accent
                              : (isDark
                                  ? AppColors.backgroundDark
                                  : AppColors.backgroundLight),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? accent
                                : (isDark
                                    ? AppColors.borderDark
                                    : AppColors.borderLight),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _label(f),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (!tier.isPaid) ...[
            const SizedBox(height: 6),
            Text(
              'DOCX requires Basic+, TXT requires Pro.',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Storage Summary
// ─────────────────────────────────────────────────────────────────────────────

class _StorageSummary extends StatelessWidget {
  const _StorageSummary({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final settings = HiveService.settings;
    final resumes = HiveService.resumeBox.values.toList();
    final activeResumes = resumes.where((r) => !r.isArchived).length;
    final archivedResumes = resumes.where((r) => r.isArchived).length;
    final coverLetters = HiveService.coverLetterBox.length;
    final studyGuides = HiveService.studyGuideBox.length;

    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: GoogleFonts.inter(fontSize: 12.5, color: secondary)),
              Text(value,
                  style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: onSurface)),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Local Storage',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 8),
          row('Active resumes', '$activeResumes'),
          row('Archived resumes', '$archivedResumes'),
          row('Cover letters', '$coverLetters'),
          row('Interview study guides', '$studyGuides'),
          row(
            'Total document uploads',
            settings.tier.isPro
                ? '${settings.totalUploadCount}'
                : '${settings.totalUploadCount} / ${settings.tier.uploadLimit == -1 ? "∞" : settings.tier.uploadLimit}',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Website Footer Link — quiet, centered, below every real settings section.
// Not styled as a settings option: no icon, no chevron, muted secondary
// color rather than the accent used for every tappable row above.
// ─────────────────────────────────────────────────────────────────────────────

class _WebsiteFooterLink extends StatelessWidget {
  const _WebsiteFooterLink({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final secondary =
        isDark ? AppColors.secondaryTextDark : AppColors.secondaryTextLight;
    return Center(
      child: Semantics(
        label:
            'For more information or to see our other apps, visit $_websiteDisplay',
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _openWebsite(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              'For more information or to see our other apps, please visit '
              '$_websiteDisplay',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11.5, color: secondary),
            ),
          ),
        ),
      ),
    );
  }
}
