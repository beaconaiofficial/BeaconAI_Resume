import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_enums.dart';
import '../models/user_settings.dart';
import '../services/hive_service.dart';
import '../services/revenue_cat_service.dart';

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
final adSuppressedProvider = Provider<bool>((ref) {
  return ref.watch(userSettingsProvider).tier.isPaid;
});

/// Convenience provider for the current tier.
final currentTierProvider = Provider<TierEnum>((ref) {
  return ref.watch(userSettingsProvider).tier;
});
