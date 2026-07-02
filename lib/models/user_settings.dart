import 'package:hive_ce/hive.dart';
import '../constants/app_constants.dart';
import 'app_enums.dart';

part 'user_settings.g.dart';

/// UserSettings — persisted in Hive as a single object under key 'settings'.
/// Rule §7: tier and billing fields are included in backup export but NEVER
///          restored on import — prevents IAP bypass on a new device.
/// Rule §8: fontScaleOverride drives the top-level MediaQuery override.
@HiveType(typeId: AppConstants.userSettingsTypeId)
class UserSettings extends HiveObject {
  // ── Privacy & Onboarding ────────────────────────────────────────────────────

  /// App is fully blocked until this is true (user tapped 'I Agree').
  @HiveField(0)
  bool privacyAccepted;

  /// Timestamp when the user accepted the privacy policy.
  @HiveField(1)
  DateTime? privacyAcceptedAt;

  /// True once the first-resume setup wizard is complete.
  @HiveField(2)
  bool onboardingComplete;

  /// True once the native rating dialog has been shown — never shown again.
  @HiveField(3)
  bool ratingPromptShown;

  // ── Tier & Billing ──────────────────────────────────────────────────────────

  /// Current subscription tier. Sourced from RevenueCat at runtime.
  /// Rule §7: reset to free on fresh install — never restored from backup.
  @HiveField(4)
  TierEnum tier;

  /// Start of the current 30-day billing cycle.
  @HiveField(5)
  DateTime billingCycleStart;

  /// Number of tailored resumes created in the current billing cycle (Basic tier).
  /// Resets to 0 when billingCycleStart + 30 days is reached.
  @HiveField(6)
  int tailoredResumesCreatedThisCycle;

  /// Date the soft-reset prompt should appear for the Free tier master resume.
  @HiveField(7)
  DateTime? masterResumeResetDate;

  // ── Preferences ─────────────────────────────────────────────────────────────

  /// Default export format selected by user in Settings.
  @HiveField(8)
  ExportFormatEnum defaultExportFormat;

  /// App theme preference (system / light / dark).
  @HiveField(9)
  AppThemeEnum theme;

  /// Whether to surface ATS completion nudges and notifications.
  @HiveField(10)
  bool atsNotificationsEnabled;

  /// Total upload count across all resumes (used for tier enforcement).
  @HiveField(11)
  int totalUploadCount;

  // ── Accessibility Overrides ─────────────────────────────────────────────────
  // null = follow device setting. Non-null overrides device setting app-wide.
  // Applied via top-level MediaQuery.copyWith() wrapper in main.dart.

  /// Font scale multiplier (0.8–2.0). null = use device textScaleFactor.
  /// Rule §8: never use pixel font sizes — this multiplier is the only way
  ///          to override scale within the app.
  @HiveField(12)
  double? fontScaleOverride;

  /// High contrast palette override. null = follow MediaQuery.highContrast.
  @HiveField(13)
  bool? highContrastOverride;

  /// Reduce motion override. null = follow MediaQuery.disableAnimations.
  @HiveField(14)
  bool? reduceMotionOverride;

  /// Extended Semantics labels on complex widgets (ATS ring, skill rows, etc.).
  /// Defaults to true — users can disable if VoiceOver verbosity is too high.
  @HiveField(15)
  bool screenReaderHintsEnabled;

  /// Version of the retroactive data-sanitization migration
  /// (ResumeMigrationService) last applied to this device's stored resumes.
  /// 0 = never run. Compared against ResumeSanitizer.currentSanitizationVersion
  /// on app launch — the migration runs once and only advances this forward.
  @HiveField(16, defaultValue: 0)
  int experienceSanitizedVersion;

  UserSettings({
    this.privacyAccepted = false,
    this.privacyAcceptedAt,
    this.onboardingComplete = false,
    this.ratingPromptShown = false,
    this.tier = TierEnum.free,
    DateTime? billingCycleStart,
    this.tailoredResumesCreatedThisCycle = 0,
    this.masterResumeResetDate,
    this.defaultExportFormat = ExportFormatEnum.pdf,
    this.theme = AppThemeEnum.system,
    this.atsNotificationsEnabled = true,
    this.totalUploadCount = 0,
    this.fontScaleOverride,
    this.highContrastOverride,
    this.reduceMotionOverride,
    this.screenReaderHintsEnabled = true,
    this.experienceSanitizedVersion = 0,
  }) : billingCycleStart = billingCycleStart ?? DateTime.now();

  // ── Computed Properties ─────────────────────────────────────────────────────

  /// True if the current billing cycle has expired and needs a reset.
  bool get isBillingCycleExpired {
    final cycleEnd = billingCycleStart
        .add(const Duration(days: AppConstants.billingCycleDays));
    return DateTime.now().isAfter(cycleEnd);
  }

  /// True if the Free tier master resume reset date has been reached.
  bool get isMasterResumeResetDue {
    if (masterResumeResetDate == null) return false;
    return DateTime.now().isAfter(masterResumeResetDate!);
  }

  /// True if the Basic tier tailored resume monthly slot is still available.
  bool get hasTailoredResumeSlotAvailable {
    if (tier.isPro) return true;
    if (!tier.isBasic) return false;
    return tailoredResumesCreatedThisCycle <
        AppConstants.tailoredResumeMonthlyLimitBasic;
  }

  /// Remaining tailored resume slots this cycle (Basic only; -1 = unlimited for Pro).
  int get remainingTailoredSlots {
    if (tier.isPro) return -1;
    if (!tier.isBasic) return 0;
    return (AppConstants.tailoredResumeMonthlyLimitBasic -
            tailoredResumesCreatedThisCycle)
        .clamp(0, AppConstants.tailoredResumeMonthlyLimitBasic);
  }

  /// Resets the billing cycle. Called when isBillingCycleExpired is true.
  void resetBillingCycle() {
    billingCycleStart = DateTime.now();
    tailoredResumesCreatedThisCycle = 0;
    save();
  }

  /// Returns a default UserSettings instance for first launch.
  static UserSettings defaults() => UserSettings(
        privacyAccepted: false,
        onboardingComplete: false,
        ratingPromptShown: false,
        tier: TierEnum.free,
        billingCycleStart: DateTime.now(),
        tailoredResumesCreatedThisCycle: 0,
        defaultExportFormat: ExportFormatEnum.pdf,
        theme: AppThemeEnum.system,
        atsNotificationsEnabled: true,
        totalUploadCount: 0,
        screenReaderHintsEnabled: true,
      );

  /// Returns a sanitized Map for backup JSON export.
  /// Rule §7: tier and billing fields are exported but must NOT be restored.
  Map<String, dynamic> toBackupJson() => {
        'privacyAccepted': privacyAccepted,
        'onboardingComplete': onboardingComplete,
        'ratingPromptShown': ratingPromptShown,
        'tier': tier.name, // exported for reference only — not restored
        'billingCycleStart':
            billingCycleStart.toIso8601String(), // exported — not restored
        'defaultExportFormat': defaultExportFormat.name,
        'theme': theme.name,
        'atsNotificationsEnabled': atsNotificationsEnabled,
        'screenReaderHintsEnabled': screenReaderHintsEnabled,
      };
}
