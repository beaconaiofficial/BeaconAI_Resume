import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../models/app_enums.dart';
import '../models/resume.dart';
import '../models/resume_sections.dart';
import '../models/supporting_models.dart';
import '../providers/user_settings_provider.dart';
import '../services/hive_service.dart';
import '../theme/app_colors.dart';
import '../widgets/wizard_widgets.dart';
import '../widgets/wizard_step_contact_summary.dart';
import '../widgets/wizard_step_experience_education.dart';
import '../widgets/wizard_step_skills_certs.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// ResumeBuilderWizardScreen
//
// Spec §7:
//  - 6-step guided flow, identical for both paths (upload / scratch).
//  - Persistent progress bar at top on every step.
//  - 'Save & Continue' and 'Back' on every step.
//  - 'Save & Exit' available at any time — wizard resumes where user left off.
//  - Live mini-preview button available throughout.
//  - Path A (upload): fields pre-populated, becomes review-and-improve flow.
//  - Path B (scratch): all fields empty, contextual tips inline.
//  - Every section appears even if Claude filled it — no skipping.
//  - AI prefill indicators (purple) clear on first edit (Rule §4).
//  - AdMob interstitial pre-loaded during editing (Rule §5 / §10).
// ─────────────────────────────────────────────────────────────────────────────

class ResumeBuilderWizardScreen extends ConsumerStatefulWidget {
  const ResumeBuilderWizardScreen({super.key});

  @override
  ConsumerState<ResumeBuilderWizardScreen> createState() =>
      _ResumeBuilderWizardScreenState();
}

class _ResumeBuilderWizardScreenState
    extends ConsumerState<ResumeBuilderWizardScreen> {
  // ── Wizard state ──────────────────────────────────────────────────────────
  static const int _totalSteps = 6;
  int _currentStep = 1;
  bool _isLoading = false;

  // ── Path & template ───────────────────────────────────────────────────────
  late String _path; // 'upload' | 'scratch'
  late String _templateId;

  // ── Form keys — one per step for independent validation ───────────────────
  final _formKeys = List.generate(6, (_) => GlobalKey<FormState>());

  // ── In-memory resume data ─────────────────────────────────────────────────
  // Hive ID assigned on first Save & Exit or Finish
  String? _resumeId;

  ContactInfo _contactInfo = ContactInfo();
  String _summary = '';
  List<ExperienceEntry> _experience = [];
  List<EducationEntry> _education = [];
  List<SkillEntry> _skills = [];
  List<CertificationEntry> _certifications = [];

  // Raw per-file metadata carried over from DocumentUploadScreen's
  // first-setup-mode prefill (path == 'upload'). Consumed exactly once, on
  // the first _persistToHive() call that actually creates the Resume
  // record — that's the earliest point a resumeId exists to attach
  // SourceDocument records to, and the only correct place to seed
  // Resume.uploadCount from the real founding-upload count.
  List<Map<String, dynamic>> _pendingSourceDocuments = [];

  // AI prefill tracking — set to true when path == 'upload' and data arrives
  bool _summaryAIPrefilled = false;

  // ── AdMob ─────────────────────────────────────────────────────────────────
  InterstitialAd? _interstitialAd;
  bool _adLoaded = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Route args resolved in didChangeDependencies (context available there)
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _path = args['path'] as String? ?? 'scratch';
      _templateId =
          args['templateId'] as String? ?? AppConstants.defaultTemplateId;

      // If upload path, pre-populated data may be passed in
      if (args.containsKey('prefillData')) {
        _applyPrefillData(args['prefillData'] as Map<String, dynamic>);
      }
    } else {
      _path = 'scratch';
      _templateId = AppConstants.defaultTemplateId;
    }

    // Pre-load AdMob interstitial in background (Rule §10)
    // Only if Free tier — but pre-load unconditionally; suppress on show.
    _preloadAd();
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AdMob pre-load
  // Rule §10: Pre-load during editing so it shows immediately at transition.
  //           If ad fails to load, skip silently — never block. (Rule §5)
  // ─────────────────────────────────────────────────────────────────────────

  void _preloadAd() {
    if (kIsWeb) return; // google_mobile_ads has no web platform channel
    InterstitialAd.load(
      adUnitId: Theme.of(context).platform == TargetPlatform.iOS
          ? AppConstants.admobInterstitialIdIos
          : AppConstants.admobInterstitialIdAndroid,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _adLoaded = true;
        },
        onAdFailedToLoad: (_) {
          // Fail silently — never block the user (Rule §5)
          _adLoaded = false;
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AI Prefill
  // ─────────────────────────────────────────────────────────────────────────

  void _applyPrefillData(Map<String, dynamic> data) {
    if (data.containsKey('contact')) {
      _contactInfo =
          ContactInfo.fromJson(data['contact'] as Map<String, dynamic>);
    }
    if (data.containsKey('summary')) {
      _summary = data['summary'] as String;
      _summaryAIPrefilled = true;
    }
    if (data.containsKey('experience')) {
      _experience = (data['experience'] as List)
          .map((e) => ExperienceEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data.containsKey('education')) {
      _education = (data['education'] as List)
          .map((e) => EducationEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data.containsKey('skills')) {
      _skills = (data['skills'] as List)
          .map((e) => SkillEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data.containsKey('certifications')) {
      _certifications = (data['certifications'] as List)
          .map((e) => CertificationEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data.containsKey('_sourceDocuments')) {
      _pendingSourceDocuments =
          (data['_sourceDocuments'] as List).cast<Map<String, dynamic>>();
    }
    setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Persistence — Save & Exit
  // Rule §2: never delete. Always write/overwrite resume and sections in Hive.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _persistToHive() async {
    _resumeId ??= _uuid.v4();
    final now = DateTime.now();

    // Upsert Resume object.
    //
    // uploadCount: on every save AFTER the first, always defer to whatever
    // is already stored (existing?.uploadCount) — DocumentUploadScreen's
    // normal (non-first-setup) upload path is the sole place that
    // increments it from then on, and re-deriving it here would either
    // reset or double-count. On the FIRST save (existing == null), seed it
    // from _pendingSourceDocuments — the founding upload count carried over
    // from DocumentUploadScreen's first-setup-mode prefill — instead of
    // hardcoding 0, which is what previously left "Source Documents"
    // stuck at 0/4 for every first-setup resume regardless of how many
    // documents were actually uploaded to build it.
    final existing = HiveService.resumeBox.get(_resumeId);
    final resume = Resume(
      id: _resumeId!,
      title: _contactInfo.fullName.isNotEmpty
          ? '${_contactInfo.fullName}\'s Resume'
          : 'My Resume',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      isMaster: true,
      templateId: _templateId,
      uploadCount: existing?.uploadCount ?? _pendingSourceDocuments.length,
      isArchived: false,
    );
    await HiveService.resumeBox.put(_resumeId, resume);

    // Create the SourceDocument records the founding upload never got to
    // write (no resumeId existed at that point). Only on first save, and
    // only once — cleared immediately after so a later Save & Exit in the
    // same session doesn't duplicate them.
    if (existing == null && _pendingSourceDocuments.isNotEmpty) {
      for (final file in _pendingSourceDocuments) {
        final docId = _uuid.v4();
        await HiveService.sourceDocumentBox.put(
          docId,
          SourceDocument(
            id: docId,
            resumeId: _resumeId!,
            fileName: file['fileName'] as String,
            fileType: FileTypeEnum.values.byName(file['fileType'] as String),
            documentRole: DocumentRoleEnum.sourceResume,
            uploadedAt: now,
            extractionStatus: ExtractionStatusEnum.complete,
            rawExtractedText: file['rawExtractedText'] as String? ?? '',
            appliedFields: (file['appliedFields'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
          ),
        );
      }
      _pendingSourceDocuments = [];
    }

    // Upsert each section — key = resumeId:sectionType
    Future<void> putSection(SectionTypeEnum type, String jsonData) async {
      final key = '${_resumeId}_${type.name}';
      final existing = HiveService.resumeSectionBox.get(key);
      final section = ResumeSection(
        id: existing?.id ?? _uuid.v4(),
        resumeId: _resumeId!,
        type: type,
        data: jsonData,
        hasUnreviewedAIContent: false,
      );
      await HiveService.resumeSectionBox.put(key, section);
    }

    await Future.wait([
      putSection(SectionTypeEnum.contact, jsonEncode(_contactInfo.toJson())),
      putSection(SectionTypeEnum.summary, jsonEncode({'text': _summary})),
      putSection(SectionTypeEnum.experience,
          jsonEncode(_experience.map((e) => e.toJson()).toList())),
      putSection(SectionTypeEnum.education,
          jsonEncode(_education.map((e) => e.toJson()).toList())),
      putSection(SectionTypeEnum.skills,
          jsonEncode(_skills.map((e) => e.toJson()).toList())),
      putSection(SectionTypeEnum.certifications,
          jsonEncode(_certifications.map((e) => e.toJson()).toList())),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onNext() async {
    // Validate current step
    final formKey = _formKeys[_currentStep - 1];
    final isValid = formKey.currentState?.validate() ?? true;
    if (!isValid) return;

    if (_currentStep < _totalSteps) {
      setState(() => _currentStep++);
      return;
    }

    // Step 6 — Finish
    await _finish();
  }

  void _onBack() {
    if (_currentStep > 1) setState(() => _currentStep--);
  }

  Future<void> _onSaveExit() async {
    setState(() => _isLoading = true);
    await _persistToHive();
    setState(() => _isLoading = false);
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
          context, AppConstants.routeDashboard, (r) => false);
    }
  }

  Future<void> _finish() async {
    setState(() => _isLoading = true);
    await _persistToHive();

    // App rating prompt — shown once after first master resume saved
    final settings = ref.read(userSettingsProvider);
    if (!settings.ratingPromptShown) {
      await ref.read(userSettingsProvider.notifier).markRatingPromptShown();
      // Native rating dialog triggered via store_review package in Phase 3
      // For now, mark as shown and continue
    }

    setState(() => _isLoading = false);

    if (!mounted) return;

    // Ad gate — Rule §6: check tier before every ad trigger
    final tier = ref.read(currentTierProvider);
    if (tier.isFree && _adLoaded && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (_) => _navigateToPreview(),
        onAdFailedToShowFullScreenContent: (_, __) => _navigateToPreview(),
      );
      await _interstitialAd!.show();
    } else {
      // Paid tier or ad failed — skip directly to Preview (Rule §5)
      _navigateToPreview();
    }
  }

  void _navigateToPreview() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      AppConstants.routePreviewEdit,
      arguments: {'resumeId': _resumeId},
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mini Preview Modal
  // ─────────────────────────────────────────────────────────────────────────

  void _showMiniPreview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MiniPreviewModal(
        contactInfo: _contactInfo,
        summary: _summary,
        experience: _experience,
        education: _education,
        skills: _skills,
        certifications: _certifications,
        templateId: _templateId,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step title / subtitle
  // ─────────────────────────────────────────────────────────────────────────

  String get _stepTitle {
    return switch (_currentStep) {
      1 => 'Contact Info',
      2 => 'Professional Summary',
      3 => 'Work Experience',
      4 => 'Education',
      5 => 'Skills',
      6 => 'Certifications',
      _ => '',
    };
  }

  String get _stepSubtitle {
    return switch (_currentStep) {
      1 => 'How employers will reach you',
      2 => 'Your elevator pitch — 3–4 sentences',
      3 => 'Your work history',
      4 => 'Degrees and institutions',
      5 => 'Skills that match the job',
      6 => 'Optional — add later if needed',
      _ => '',
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _stepTitle,
              style: GoogleFonts.playfairDisplay(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _stepSubtitle,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          // Live mini-preview button
          Semantics(
            label: 'Preview resume',
            child: IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Preview',
              onPressed: _showMiniPreview,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),

          // ── Progress bar — always visible ──────────────────────────────
          WizardProgressBar(
            currentStep: _currentStep,
            totalSteps: _totalSteps,
          ),

          const SizedBox(height: 16),

          // ── Step content ───────────────────────────────────────────────
          Expanded(child: _buildCurrentStep()),
        ],
      ),
      // bottomNavigationBar, not the last item in body's Column — same
      // placement PreviewEditScreen/ResumeEditorScreen use for their own
      // bottom bars, so it anchors to the true bottom edge rather than
      // being subject to the body Column's layout.
      bottomNavigationBar: WizardNavBar(
        currentStep: _currentStep,
        totalSteps: _totalSteps,
        onBack: _onBack,
        onNext: _onNext,
        onSaveExit: _onSaveExit,
        isNextLoading: _isLoading,
        nextLabel: _currentStep == _totalSteps ? 'Finish' : null,
      ),
    );
  }

  Widget _buildCurrentStep() {
    final isUpload = _path == 'upload';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: switch (_currentStep) {
        1 => WizardStepContact(
            key: const ValueKey(1),
            data: _contactInfo,
            isUploadPath: isUpload,
            formKey: _formKeys[0],
            onChanged: (v) => setState(() => _contactInfo = v),
          ),
        2 => WizardStepSummary(
            key: const ValueKey(2),
            initialText: _summary,
            isAIPrefilled: _summaryAIPrefilled,
            formKey: _formKeys[1],
            onChanged: (v) => setState(() => _summary = v),
            onAIEdited: () => setState(() => _summaryAIPrefilled = false),
          ),
        3 => WizardStepExperience(
            key: const ValueKey(3),
            entries: _experience,
            isUploadPath: isUpload,
            formKey: _formKeys[2],
            onChanged: (v) => setState(() => _experience = v),
          ),
        4 => WizardStepEducation(
            key: const ValueKey(4),
            entries: _education,
            isUploadPath: isUpload,
            formKey: _formKeys[3],
            onChanged: (v) => setState(() => _education = v),
          ),
        5 => WizardStepSkills(
            key: const ValueKey(5),
            entries: _skills,
            isUploadPath: isUpload,
            formKey: _formKeys[4],
            onChanged: (v) => setState(() => _skills = v),
          ),
        6 => WizardStepCertifications(
            key: const ValueKey(6),
            entries: _certifications,
            isUploadPath: isUpload,
            formKey: _formKeys[5],
            onChanged: (v) => setState(() => _certifications = v),
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini Preview Modal
// Shows the resume as it builds in the chosen template.
// Full Preview & Edit screen is built in a later phase.
// ─────────────────────────────────────────────────────────────────────────────

class _MiniPreviewModal extends StatelessWidget {
  const _MiniPreviewModal({
    required this.contactInfo,
    required this.summary,
    required this.experience,
    required this.education,
    required this.skills,
    required this.certifications,
    required this.templateId,
  });

  final ContactInfo contactInfo;
  final String summary;
  final List<ExperienceEntry> experience;
  final List<EducationEntry> education;
  final List<SkillEntry> skills;
  final List<CertificationEntry> certifications;
  final String templateId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Preview',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                // Template chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.accentLightTintDark
                        : AppColors.accentLightTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    templateId.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close preview',
                ),
              ],
            ),
          ),

          const Divider(),

          // Resume content preview
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: _ResumeTextPreview(
                contactInfo: contactInfo,
                summary: summary,
                experience: experience,
                education: education,
                skills: skills,
                certifications: certifications,
                isDark: isDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Resume Text Preview — lightweight text-based preview for the modal.
// Full template-rendered preview is in the Preview & Edit screen (later phase).
// ─────────────────────────────────────────────────────────────────────────────

class _ResumeTextPreview extends StatelessWidget {
  const _ResumeTextPreview({
    required this.contactInfo,
    required this.summary,
    required this.experience,
    required this.education,
    required this.skills,
    required this.certifications,
    required this.isDark,
  });

  final ContactInfo contactInfo;
  final String summary;
  final List<ExperienceEntry> experience;
  final List<EducationEntry> education;
  final List<SkillEntry> skills;
  final List<CertificationEntry> certifications;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final accent = Theme.of(context).colorScheme.primary;
    final divider = isDark ? AppColors.borderDark : AppColors.borderLight;

    Widget sectionHeader(String title) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: accent,
              ),
            ),
            const SizedBox(height: 4),
            Divider(height: 1, color: divider),
            const SizedBox(height: 8),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Contact ───────────────────────────────────────────────────────
        if (contactInfo.fullName.isNotEmpty)
          Text(
            contactInfo.fullName,
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
        if (contactInfo.professionalTitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            contactInfo.professionalTitle,
            style: GoogleFonts.inter(fontSize: 14, color: onSurfaceVariant),
          ),
        ],
        if (contactInfo.cityState.isNotEmpty ||
            contactInfo.phone.isNotEmpty ||
            contactInfo.email.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            [
              contactInfo.cityState,
              contactInfo.phone,
              contactInfo.email,
            ].where((s) => s.isNotEmpty).join('  ·  '),
            style: GoogleFonts.inter(fontSize: 12, color: onSurfaceVariant),
          ),
        ],

        // ── Summary ───────────────────────────────────────────────────────
        if (summary.isNotEmpty) ...[
          sectionHeader('Summary'),
          Text(
            summary,
            style:
                GoogleFonts.inter(fontSize: 13, height: 1.6, color: onSurface),
          ),
        ],

        // ── Experience ────────────────────────────────────────────────────
        if (experience.any((e) => e.title.isNotEmpty)) ...[
          sectionHeader('Experience'),
          for (final e in experience.where((e) => e.title.isNotEmpty)) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${e.title}  |  ${e.company}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                ),
                Text(
                  e.dateRange,
                  style:
                      GoogleFonts.inter(fontSize: 11, color: onSurfaceVariant),
                ),
              ],
            ),
            if (e.location.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(e.location,
                  style:
                      GoogleFonts.inter(fontSize: 12, color: onSurfaceVariant)),
            ],
            for (final b in e.bullets.where((b) => b.isNotEmpty)) ...[
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: onSurfaceVariant)),
                  Expanded(
                    child: Text(b,
                        style: GoogleFonts.inter(
                            fontSize: 12, height: 1.5, color: onSurface)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
          ],
        ],

        // ── Education ─────────────────────────────────────────────────────
        if (education.any((e) => e.institution.isNotEmpty)) ...[
          sectionHeader('Education'),
          for (final e in education.where((e) => e.institution.isNotEmpty)) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    e.institution,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                ),
                Text(
                  e.graduationYear,
                  style:
                      GoogleFonts.inter(fontSize: 11, color: onSurfaceVariant),
                ),
              ],
            ),
            Text(
              [e.degree, e.fieldOfStudy].where((s) => s.isNotEmpty).join(', '),
              style: GoogleFonts.inter(fontSize: 12, color: onSurfaceVariant),
            ),
            const SizedBox(height: 8),
          ],
        ],

        // ── Skills ────────────────────────────────────────────────────────
        if (skills.isNotEmpty) ...[
          sectionHeader('Skills'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: skills
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: divider),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(s.name,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: onSurface)),
                    ))
                .toList(),
          ),
        ],

        // ── Certifications ────────────────────────────────────────────────
        if (certifications.any((c) => c.name.isNotEmpty)) ...[
          sectionHeader('Certifications'),
          for (final c in certifications.where((c) => c.name.isNotEmpty)) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    c.name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                ),
                Text(
                  c.dateEarned,
                  style:
                      GoogleFonts.inter(fontSize: 11, color: onSurfaceVariant),
                ),
              ],
            ),
            Text(c.issuer,
                style:
                    GoogleFonts.inter(fontSize: 12, color: onSurfaceVariant)),
            const SizedBox(height: 8),
          ],
        ],

        const SizedBox(height: 40),
      ],
    );
  }
}
