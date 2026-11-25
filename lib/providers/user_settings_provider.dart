import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_enums.dart';
import '../models/user_settings.dart';
import '../services/age_signal_service.dart';
import '../services/hive_service.dart';
import '../services/revenue_cat_service.dart';
import '../utils/app_logger.dart';

/// Provides and mutates the single UserSettings object stored in Hive.
/// All accessibility overrides, tier, and preference reads go through this provider.
class UserSettingsNotifier extends Notifier<UserSettings> {
  @override
  UserSettings build() => HiveService.settings;

  // UserSettings is a mutable HiveObject — cascade mutations (state = state..x = y)
  // reassign the same reference, so the default identical() check would suppress
  // every rebuild. Always notify so any intentional state assignment reaches listeners.
  @override
  bool updateShouldNotify(UserSettings previous, UserSettings next) => true;

  Future<void> acceptPrivacyPolicy() async {
    state = state
      ..privacyAccepted = true
      ..privacyAcceptedAt = DateTime.now();
    await HiveService.saveSettings(state);
  }

  Future<void> completeOnboarding() async {
    state = state..onboardingComplete = true;
    await HiveService.saveSettings(state);
  }

  Future<void> markRatingPromptShown() async {
    state = state..ratingPromptShown = true;
    await HiveService.saveSettings(state);
  }

  Future<void> acceptAiDataSharing() async {
    state = state..aiDataSharingAccepted = true;
    await HiveService.saveSettings(state);
  }

  // ── Age Assurance ─────────────────────────────────────────────────────────

  /// Guards the store/OS request to once per app process (each launch).
  static bool _ageSignalRequestedThisLaunch = false;

  /// Test-only: allow another refresh in the same process.
  static void debugResetAgeSignalLaunchGuard() =>
      _ageSignalRequestedThisLaunch = false;

  /// Fire-and-forget entry point. Requests the age signal at most once per
  /// launch and only after the privacy policy is accepted (the request may
  /// show a store/OS prompt). Never throws — a failure leaves the stored
  /// bracket untouched and the app working normally.
  Future<void> refreshAgeSignal({AgeSignalService? service}) async {
    if (_ageSignalRequestedThisLaunch) return;
    if (!state.privacyAccepted) return;
    _ageSignalRequestedThisLaunch = true;
    try {
      final result = await (service ?? AgeSignalService()).fetch();
      await applyAgeSignal(result);
    } catch (e) {
      devLog('[AGE SIGNAL] refresh failed: ${e.runtimeType}');
    }
  }

  /// Stores the outcome of a fetch per the approved rules (see
  /// resolveStoredBracket). Returns true when the stored bracket changed.
  Future<bool> applyAgeSignal(AgeSignalResult result) async {
    final current = state.ageBracket;
    final next = resolveStoredBracket(result, current);
    final definitive = isDefinitiveAgeSignal(result);
    if (next == null && !definitive) return false;

    final resolved = next ?? current;
    // Leaving restricted mode (e.g. turned 18): exit silently and re-arm the
    // notice in case a future signal ever restricts again.
    final leavingRestricted = current.isRestricted && !resolved.isRestricted;
    state = state
      ..ageBracket = resolved
      ..ageSignalCheckedAt =
          definitive ? DateTime.now() : state.ageSignalCheckedAt
      ..ageRestrictionNoticeShown =
          leavingRestricted ? false : state.ageRestrictionNoticeShown;
    await HiveService.saveSettings(state);
    if (resolved != current) {
      devLog('[AGE SIGNAL] bracket changed (restricted='
          '${resolved.isRestricted})');
    }
    return resolved != current;
  }

  Future<void> markAgeRestrictionNoticeShown() async {
    state = state..ageRestrictionNoticeShown = true;
    await HiveService.saveSettings(state);
  }

  Future<void> setTheme(AppThemeEnum theme) async {
    state = state..theme = theme;
    await HiveService.saveSettings(state);
  }

  Future<void> setDefaultExportFormat(ExportFormatEnum format) async {
    state = state..defaultExportFormat = format;
    await HiveService.saveSettings(state);
  }

  Future<void> setFontScaleOverride(double? scale) async {
    state = state..fontScaleOverride = scale;
    await HiveService.saveSettings(state);
  }

  Future<void> setHighContrastOverride(bool? value) async {
    state = state..highContrastOverride = value;
    await HiveService.saveSettings(state);
  }

  Future<void> setReduceMotionOverride(bool? value) async {
    state = state..reduceMotionOverride = value;
    await HiveService.saveSettings(state);
  }

  Future<void> setScreenReaderHints(bool value) async {
    state = state..screenReaderHintsEnabled = value;
    await HiveService.saveSettings(state);
  }

  /// Reads the authoritative tier from RevenueCat and syncs UserSettings.tier.
  /// Also registers a listener so external entitlement changes (renewal,
  /// cancellation, refund) are reflected immediately without re-launch.
  /// Call once after RevenueCatService.configure() at app launch.
  Future<void> syncTierFromRevenueCat() async {
    final liveTier = await RevenueCatService.getCurrentTier();
    if (liveTier != state.tier) {
      await updateTier(liveTier);
    }
    RevenueCatService.addTierChangeListener((tier) async {
      if (tier != state.tier) {
        await updateTier(tier);
      }
    });
  }

  /// Called by RevenueCat integration when tier changes.
  Future<void> updateTier(TierEnum tier) async {
    state = state..tier = tier;
    await HiveService.saveSettings(state);
  }

  Future<void> incrementTailoredResumeCount() async {
    if (state.isBillingCycleExpired) {
      state.resetBillingCycle();
    }
    state = state
      ..tailoredResumesCreatedThisCycle =
          state.tailoredResumesCreatedThisCycle + 1;
    await HiveService.saveSettings(state);
  }

  /// Checks and resets the billing cycle if expired. Call on app launch.
  Future<void> checkAndResetBillingCycleIfNeeded() async {
    if (state.isBillingCycleExpired) {
      state.resetBillingCycle();
      state = HiveService.settings; // re-read after reset
    }
  }
}

final userSettingsProvider =
    NotifierProvider<UserSettingsNotifier, UserSettings>(
  UserSettingsNotifier.new,
);

/// Convenience provider — true if ads should be suppressed.
/// Rule §6: check tier before every AdMob request, not just at launch.
/// Age assurance: a signaled minor (restricted mode) gets NO ads at all —
/// suppression is the only ad effect of the age signal; nothing age-related
/// is ever passed to AdMob.
final adSuppressedProvider = Provider<bool>((ref) {
  final s = ref.watch(userSettingsProvider);
  return s.tier.isPaid || s.ageBracket.isRestricted;
});

/// True while the stored age bracket puts the app in restricted mode.
final ageRestrictedProvider = Provider<bool>((ref) {
  return ref.watch(userSettingsProvider).ageBracket.isRestricted;
});

/// True while AI upload/generation is blocked for the stored age bracket.
final aiBlockedByAgeProvider = Provider<bool>((ref) {
  return ref.watch(userSettingsProvider).ageBracket.isAiBlocked;
});

/// Convenience provider for the current tier.
final currentTierProvider = Provider<TierEnum>((ref) {
  return ref.watch(userSettingsProvider).tier;
});
