// BeaconAI Resume — App Constants
// Central source of truth for type IDs, routes, limits, and config values.

class AppConstants {
  AppConstants._();

  // ── App Info ─────────────────────────────────────────────────────────────────
  static const String appName = 'BeaconAI Resume';
  static const String privacyPolicyUrl = 'https://getbeaconai.dev/privacy';
  static const String termsOfUseUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
  static const String backupFileName = 'BeaconAI_Resume_Backup';
  static const String backupDataFileName = 'beaconai_data.json';
  static const String backupVersion = '1.0';

  // ── Hive Box Names ────────────────────────────────────────────────────────────
  static const String resumeBox = 'resumes';
  static const String sourceDocumentBox = 'source_documents';
  static const String resumeSectionBox = 'resume_sections';
  static const String coverLetterBox = 'cover_letters';
  static const String interviewStudyGuideBox = 'interview_study_guides';
  static const String userSettingsBox = 'user_settings';
  static const String addOnPurchaseBox = 'add_on_purchases';
  static const String userSettingsKey = 'settings';

  // ── Hive Type IDs ─────────────────────────────────────────────────────────────
  // Each Hive TypeAdapter requires a unique integer typeId.
  // Reserve blocks to avoid collisions when adding future models.
  static const int resumeTypeId = 0;
  static const int sourceDocumentTypeId = 1;
  static const int resumeSectionTypeId = 2;
  static const int coverLetterTypeId = 3;
  static const int interviewStudyGuideTypeId = 4;
  static const int interviewQuestionTypeId = 5;
  static const int userSettingsTypeId = 6;
  static const int addOnPurchaseTypeId = 7;
  static const int skillEntryTypeId = 8;
  static const int experienceEntryTypeId = 9;
  static const int educationEntryTypeId = 10;
  static const int certificationEntryTypeId = 11;
  static const int contactInfoTypeId = 12;
  // Enum adapters
  static const int tierEnumTypeId = 20;
  static const int fileTypeEnumTypeId = 21;
  static const int documentRoleEnumTypeId = 22;
  static const int extractionStatusEnumTypeId = 23;
  static const int sectionTypeEnumTypeId = 24;
  static const int skillCategoryEnumTypeId = 25;
  static const int questionCategoryEnumTypeId = 26;
  static const int addOnTypeEnumTypeId = 27;
  static const int exportFormatEnumTypeId = 28;
  static const int appThemeEnumTypeId = 29;

  // ── Named Routes ──────────────────────────────────────────────────────────────
  static const String routePrivacyPolicy = '/privacy';
  static const String routeOnboarding = '/onboarding';
  static const String routeFirstResumeSetup = '/first-resume-setup';
  static const String routeDashboard = '/dashboard';
  static const String routeResumeBuilderWizard = '/wizard';
  static const String routeSectionDetail = '/section-detail';
  static const String routeDocumentUpload = '/document-upload';
  static const String routeUploadManager = '/upload-manager';
  static const String routeTemplatePicker = '/template-picker';
  static const String routePreviewEdit = '/preview-edit';
  static const String routeAdGate = '/ad-gate';
  static const String routeMyDocuments = '/my-documents';
  static const String routeBackupRestore = '/backup-restore';
  static const String routeAtsAnalyzer = '/ats-analyzer';
  static const String routeAiSuggestions = '/ai-suggestions';
  static const String routeCreateTailoredResume = '/create-tailored';
  static const String routeCoverLetterBuilder = '/cover-letter';
  static const String routeInterviewTipsFree = '/interview-tips';
  static const String routeInterviewPrepBasic = '/interview-prep-basic';
  static const String routeInterviewPrepPro = '/interview-prep-pro';
  static const String routeExport = '/export';
  static const String routeSettings = '/settings';
  static const String routeSettingsAccessibility = '/settings/accessibility';
  static const String routePaywall = '/paywall';

  // ── Tier Limits ───────────────────────────────────────────────────────────────
  static const int uploadLimitFree = 4;
  static const int uploadLimitBasic = 10;
  // Pro = unlimited (no cap enforced)

  static const int freeMaxPagesPerDocument = 8;
  static const int basicMaxPagesPerDocument = 50;
  // Pro = unlimited (null in the extension getter)

  static const int tailoredResumeMonthlyLimitBasic = 2;
  // Pro = unlimited

  static const int billingCycleDays = 30;
  static const int masterResumeResetDays = 30;

  // ── Template IDs ─────────────────────────────────────────────────────────────
  // Phase 1 templates
  static const String templateClassic = 'classic';
  static const String templateClean = 'clean';
  static const String templateSharp = 'sharp';
  static const String templateEntry = 'entry';
  // Phase 2 templates
  static const String templateElevated = 'elevated';
  static const String templateFederal = 'federal';
  static const String templateAcademic = 'academic';
  static const String templateVeteran = 'veteran';
  // Phase 3 templates
  static const String templateTechnical = 'technical';
  static const String templateHorizon = 'horizon';
  static const String templateSidebar = 'sidebar';
  static const String templatePillar = 'pillar';

  static const String defaultTemplateId = templateClean;

  /// Horizon template accent color options (hex strings)
  static const List<String> horizonAccentColors = [
    '#1A237E', // navy
    '#212121', // charcoal
    '#1B5E20', // forest
    '#455A64', // slate
    '#4A0000', // burgundy
    '#000000', // black
  ];

  // ── Skills ────────────────────────────────────────────────────────────────────
  static const int skillsMinRecommended = 8;
  static const int skillsMaxRecommended = 12;

  // ── Validation: Contact Fields (Strict) ──────────────────────────────────────
  // Blocked chars: " / \ [ ] ; : ( ) < >
  static const String contactBlockedChars = r'"\/\[\];:()<>';
  static final RegExp contactBlockedPattern = RegExp(r'["\\/\[\];:()<>]');

  static const int maxLengthName = 50;
  static const int maxLengthCity = 60;
  static const int maxLengthProfessionalTitle = 100;
  static const int maxLengthPhone = 20;
  static const int maxLengthUrl = 200;

  // Name fields: letters, hyphens, apostrophes, spaces only
  static final RegExp namePattern = RegExp(r"^[a-zA-Z\-' ]+$");
  // City/State: letters, hyphens, spaces, periods, commas
  static final RegExp cityStatePattern = RegExp(r"^[a-zA-Z\-., ]+$");
  // Phone: digits, spaces, hyphens, + only
  static final RegExp phonePattern = RegExp(r'^[\d\s\-+]+$');
  // URL: must start with http:// or https://
  static final RegExp urlPattern = RegExp(r'^https?://');
  // Email: standard format
  static final RegExp emailPattern =
      RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');

  // ── Validation: Content Fields (Light) ───────────────────────────────────────
  // Blocked chars: < > ; ` (backtick)
  static final RegExp contentBlockedPattern = RegExp(r'[<>;`]');

  static const int maxLengthSummary = 1500;
  static const int maxLengthExperienceBullet = 300;
  static const int maxLengthJobTitle = 100;
  static const int maxLengthCompany = 100;
  static const int maxLengthSkillTag = 60;
  static const int maxLengthCertName = 150;

  // ── Summary Writing Guidance ──────────────────────────────────────────────────
  static const int summaryTargetMinChars = 300;
  static const int summaryTargetMaxChars = 500;

  // ── AdMob ─────────────────────────────────────────────────────────────────────
  // Placeholder IDs — replace with real AdMob unit IDs before release.
  // Use test IDs during development:
  static const String admobAppIdAndroid =
      'ca-app-pub-3940256099942544~3347511713';
  static const String admobAppIdIos = 'ca-app-pub-3940256099942544~1458002511';
  static const String admobInterstitialIdAndroid =
      'ca-app-pub-3292773894584155/3868238601';
  static const String admobInterstitialIdIos =
      'ca-app-pub-3292773894584155/5314961881';

  // ── RevenueCat ────────────────────────────────────────────────────────────────
  /// RevenueCat public API key (Android). Replace with the real key from
  /// the RevenueCat dashboard (Project Settings → API Keys) before release.
  static const String revenueCatApiKeyAndroid = 'goog_GoEDAmIKkSjfcKkepCbJFdwarjH';

  /// RevenueCat public API key (iOS / macOS). Replace with the real key from
  /// the RevenueCat dashboard (Project Settings → API Keys) before release.
  static const String revenueCatApiKeyIos = 'appl_QpJJHsPKdFZlgnXFXUexPTnEHsS';

  /// RevenueCat public API key (Web / RevenueCat Billing). From the RevenueCat
  /// dashboard (Project Settings → API Keys → Web Billing).
  static const String revenueCatApiKeyWeb = 'rcb_vhuvDFDWJloyvknnhpJAUUZPxcNf';

  // ── Cloudflare Worker ─────────────────────────────────────────────────────────
  // Rule §1: Never call api.anthropic.com directly. Always use the Worker URL.
  // Replace with your deployed Cloudflare Worker URL before release.
  static const String cloudflareWorkerUrl =
      'https://beaconai-proxy.beaconai-official.workers.dev';

  // Sent as the `X-BeaconAI-Secret` header on every Worker request. The
  // Worker's only other protection is a wildcard CORS header, which stops
  // nothing — any script can still curl the URL directly. This value must
  // match the `APP_SHARED_SECRET` secret configured on the Worker (see
  // beaconai-proxy/src/index.js). It's compiled into the client binary and
  // recoverable by decompiling the APK, so treat it as a filter against
  // casual/scripted abuse of the endpoint, not as strong authentication.
  static const String cloudflareWorkerSharedSecret =
      '0d7086a7d953f5d4199353cc1e23e850acc92304e4055505d3698c1776faf500';

  // ── Connectivity ──────────────────────────────────────────────────────────────
  static const String offlineBannerMessage =
      'No internet connection. You can view and edit saved documents, but creating new content requires a connection.';

  // ── Debug / Test ──────────────────────────────────────────────────────────────
  /// Bypasses the $0.99 add-on combo purchase gate for testing.
  /// Set to false before production release — that is the ONLY change required.
  static const bool kComboTestMode = false;
}
