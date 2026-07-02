import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'constants/app_constants.dart';
import 'models/app_enums.dart';
import 'providers/user_settings_provider.dart';
import 'providers/connectivity_provider.dart';
import 'services/hive_service.dart';
import 'services/resume_migration_service.dart';
import 'services/revenue_cat_service.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'screens/onboarding_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/first_resume_setup_screen.dart';
import 'screens/resume_builder_wizard_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/my_documents_screen.dart';
import 'screens/resume_editor_screen.dart';
import 'screens/interview_tips_free_screen.dart';
import 'screens/export_screen.dart';
import 'screens/document_upload_screen.dart';
import 'screens/upload_manager_screen.dart';
import 'screens/template_picker_screen.dart';
import 'screens/create_tailored_resume_screen.dart';
import 'screens/ats_analyzer_screen.dart';
import 'screens/interview_prep_basic_screen.dart';
import 'screens/interview_prep_pro_screen.dart';
import 'screens/cover_letter_builder_screen.dart';
import 'screens/backup_restore_screen.dart';
import 'screens/accessibility_settings_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/settings_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry Point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Hive and open all boxes before the app renders.
  await HiveService.init();

  // 1b. One-time, idempotent retroactive sanitization of resumes stored
  //     before the entry-classification pass existed. No-ops instantly on
  //     every launch after the first successful run (version-gated).
  try {
    await ResumeMigrationService.runIfNeeded();
  } catch (_) {
    // Never block app launch on a migration failure — the app still works
    // with unsanitized data, and the version flag stays behind so the next
    // launch retries.
  }

  // 2. Initialize AdMob SDK on native only — google_mobile_ads has no web
  //    platform channel, so calling initialize() on web throws MissingPluginException
  //    before runApp() is ever reached.
  if (!kIsWeb) {
    await MobileAds.instance.initialize();
  }

  // 3. Configure RevenueCat SDK. Non-fatal if API key is missing — the app
  //    operates normally and syncTierFromRevenueCat() will fail closed to free.
  try {
    await RevenueCatService.configure();
  } catch (_) {
    // Missing API key or SDK init failure — don't block app launch.
  }

  runApp(
    // Wrap in ProviderScope at the very top — no Riverpod usage above this.
    const ProviderScope(
      child: BeaconAIResumeApp(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Root App Widget
// ─────────────────────────────────────────────────────────────────────────────

class BeaconAIResumeApp extends ConsumerWidget {
  const BeaconAIResumeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Scoped to exactly the fields this widget uses — userSettingsProvider's
    // updateShouldNotify is unconditionally true (UserSettings is a mutable
    // HiveObject mutated in place via cascades, so by the time Riverpod
    // could compare previous/next they're already the same mutated object;
    // there's no way to tell what changed at that point). select()'s own
    // downstream equality check on this record is what actually prevents an
    // unrelated settings change (e.g. markRatingPromptShown) from rebuilding
    // the whole app shell.
    final settings = ref.watch(userSettingsProvider.select((s) => (
          theme: s.theme,
          fontScaleOverride: s.fontScaleOverride,
          reduceMotionOverride: s.reduceMotionOverride,
          highContrastOverride: s.highContrastOverride,
          privacyAccepted: s.privacyAccepted,
          onboardingComplete: s.onboardingComplete,
        )));

    // Resolve theme mode from UserSettings preference.
    final themeMode = switch (settings.theme) {
      AppThemeEnum.light => ThemeMode.light,
      AppThemeEnum.dark => ThemeMode.dark,
      AppThemeEnum.system => ThemeMode.system,
    };

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,

      // ── Themes ─────────────────────────────────────────────────────────────
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,

      // ── Accessibility MediaQuery Wrapper ───────────────────────────────────
      // Rule §8 / Section 12: Top-level Builder applies UserSettings
      // accessibility overrides via MediaQuery.copyWith(). This is the single
      // source of truth for font scaling, motion, and contrast across the app.
      // Never use hardcoded pixel font sizes anywhere in the widget tree.
      builder: (context, child) {
        final mq = MediaQuery.of(context);

        // Determine effective values: override beats device setting.
        final effectiveTextScale =
            settings.fontScaleOverride ?? mq.textScaler.scale(1.0);
        final effectiveDisableAnimations =
            settings.reduceMotionOverride ?? mq.disableAnimations;
        final effectiveHighContrast =
            settings.highContrastOverride ?? mq.highContrast;

        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(effectiveTextScale.clamp(0.8, 2.0)),
            disableAnimations: effectiveDisableAnimations,
            highContrast: effectiveHighContrast,
          ),
          child: Stack(
            children: [
              if (child != null) child,
              // ── Global Offline Banner ───────────────────────────────────────
              // Non-blocking, dismissible. Shown app-wide when offline.
              // NOTE: _OfflineBanner lives outside the Navigator's Overlay in
              // this Stack — it is a sibling of child (the Navigator), not a
              // descendant. Avoid adding Tooltips, dialogs, or anything else
              // that requires an Overlay ancestor inside _OfflineBanner.
              const _OfflineBanner(),
            ],
          ),
        );
      },

      // ── Initial Route Logic ────────────────────────────────────────────────
      // Determine start screen based on UserSettings state:
      //   1. Privacy not accepted → PrivacyPolicyScreen (hard gate)
      //   2. Privacy accepted, onboarding incomplete → OnboardingScreen
      //   3. Fully onboarded → DashboardScreen
      initialRoute: _resolveInitialRoute(
        privacyAccepted: settings.privacyAccepted,
        onboardingComplete: settings.onboardingComplete,
      ),

      // ── Route Map ─────────────────────────────────────────────────────────
      routes: {
        AppConstants.routePrivacyPolicy: (_) => const PrivacyPolicyScreen(),
        AppConstants.routeOnboarding: (_) => const OnboardingScreen(),
        AppConstants.routeFirstResumeSetup: (_) =>
            const FirstResumeSetupScreen(),
        AppConstants.routeDashboard: (_) => const DashboardScreen(),
        AppConstants.routeResumeBuilderWizard: (_) =>
            const ResumeBuilderWizardScreen(),
        AppConstants.routeMyDocuments: (_) => const MyDocumentsScreen(),
        AppConstants.routePreviewEdit: (_) => const ResumeEditorScreen(),
        AppConstants.routeInterviewTipsFree: (_) =>
            const InterviewTipsFreeScreen(),
        AppConstants.routeExport: (_) => const ExportScreen(),
        AppConstants.routeDocumentUpload: (_) => const DocumentUploadScreen(),
        AppConstants.routeUploadManager: (_) => const UploadManagerScreen(),
        AppConstants.routeTemplatePicker: (_) => const TemplatePickerScreen(),
        AppConstants.routeCreateTailoredResume: (_) =>
            const CreateTailoredResumeScreen(),
        AppConstants.routeAtsAnalyzer: (_) => const AtsAnalyzerScreen(),
        AppConstants.routeInterviewPrepBasic: (_) =>
            const InterviewPrepBasicScreen(),
        AppConstants.routeInterviewPrepPro: (_) =>
            const InterviewPrepProScreen(),
        AppConstants.routeCoverLetterBuilder: (_) =>
            const CoverLetterBuilderScreen(),
        AppConstants.routeBackupRestore: (_) => const BackupRestoreScreen(),
        AppConstants.routeSettings: (_) => const SettingsScreen(),
        AppConstants.routeSettingsAccessibility: (_) =>
            const AccessibilitySettingsScreen(),
        AppConstants.routePaywall: (_) => const PaywallScreen(),
      },

      // ── Page Transitions ───────────────────────────────────────────────────
      // Reduce motion: instant cuts instead of slide/fade transitions.
      // When disableAnimations is true, use a zero-duration custom transition.
      onGenerateRoute: (settingsRoute) {
        final builder = _routeBuilderFor(settingsRoute.name);
        if (builder == null) return null;

        final mq = MediaQueryData.fromView(
          WidgetsBinding.instance.platformDispatcher.views.first,
        );
        final reduceMotion =
            settings.reduceMotionOverride ?? mq.disableAnimations;

        if (reduceMotion) {
          return PageRouteBuilder(
            settings: settingsRoute,
            pageBuilder: (context, _, __) => builder(context),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          );
        }
        return MaterialPageRoute(
          settings: settingsRoute,
          builder: builder,
        );
      },
    );
  }

  /// Resolves the first route to show based on UserSettings state.
  static String _resolveInitialRoute({
    required bool privacyAccepted,
    required bool onboardingComplete,
  }) {
    if (!privacyAccepted) {
      return AppConstants.routePrivacyPolicy;
    }
    if (!onboardingComplete) {
      return AppConstants.routeOnboarding;
    }
    return AppConstants.routeDashboard;
  }

  /// Maps route names to builder functions for onGenerateRoute (reduce motion support).
  static WidgetBuilder? _routeBuilderFor(String? name) {
    return switch (name) {
      AppConstants.routePrivacyPolicy => (_) => const PrivacyPolicyScreen(),
      AppConstants.routeOnboarding => (_) => const OnboardingScreen(),
      AppConstants.routeFirstResumeSetup => (_) =>
          const FirstResumeSetupScreen(),
      AppConstants.routeDashboard => (_) => const DashboardScreen(),
      AppConstants.routeResumeBuilderWizard => (_) =>
          const ResumeBuilderWizardScreen(),
      AppConstants.routeMyDocuments => (_) => const MyDocumentsScreen(),
      AppConstants.routePreviewEdit => (_) => const ResumeEditorScreen(),
      AppConstants.routeInterviewTipsFree => (_) =>
          const InterviewTipsFreeScreen(),
      AppConstants.routeExport => (_) => const ExportScreen(),
      AppConstants.routeDocumentUpload => (_) => const DocumentUploadScreen(),
      AppConstants.routeUploadManager => (_) => const UploadManagerScreen(),
      AppConstants.routeTemplatePicker => (_) => const TemplatePickerScreen(),
      AppConstants.routeCreateTailoredResume => (_) =>
          const CreateTailoredResumeScreen(),
      AppConstants.routeAtsAnalyzer => (_) => const AtsAnalyzerScreen(),
      AppConstants.routeInterviewPrepBasic => (_) =>
          const InterviewPrepBasicScreen(),
      AppConstants.routeInterviewPrepPro => (_) =>
          const InterviewPrepProScreen(),
      AppConstants.routeCoverLetterBuilder => (_) =>
          const CoverLetterBuilderScreen(),
      AppConstants.routeBackupRestore => (_) => const BackupRestoreScreen(),
      AppConstants.routeSettings => (_) => const SettingsScreen(),
      AppConstants.routeSettingsAccessibility => (_) =>
          const AccessibilitySettingsScreen(),
      AppConstants.routePaywall => (_) => const PaywallScreen(),
      _ => null,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offline Banner Widget
// ─────────────────────────────────────────────────────────────────────────────

/// Non-blocking banner shown app-wide when the device has no internet.
/// Sits in the global Stack above all screens.
/// Per Section 16: never blocks access to previously created documents.
class _OfflineBanner extends ConsumerStatefulWidget {
  const _OfflineBanner();

  @override
  ConsumerState<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<_OfflineBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(isOnlineProvider);

    // Reset dismissed state when connectivity is restored
    if (isOnline && _dismissed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _dismissed = false);
      });
    }

    if (isOnline || _dismissed) return const SizedBox.shrink();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Semantics(
        label: AppConstants.offlineBannerMessage,
        liveRegion: true,
        child: Material(
          color: Colors.transparent,
          child: Container(
            color: AppColors.warningLight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppConstants.offlineBannerMessage,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                          ),
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => setState(() => _dismissed = true),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
