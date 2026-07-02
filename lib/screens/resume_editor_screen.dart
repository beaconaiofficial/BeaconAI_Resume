import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../models/app_enums.dart';
import '../models/resume.dart';
import '../models/resume_sections.dart';
import '../models/supporting_models.dart';
import '../providers/resume_provider.dart';
import '../providers/user_settings_provider.dart';
import '../services/hive_service.dart';
import '../services/pdf_export_service.dart';
import '../theme/app_colors.dart';
import '../widgets/pending_decision_card.dart';
import '../widgets/resume_template_renderer.dart';
import '../widgets/wizard_step_contact_summary.dart';
import '../widgets/wizard_step_experience_education.dart';
import '../widgets/wizard_step_skills_certs.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// ResumeEditorScreen
// Two-pane editor (wide) or tabbed Preview/Edit (narrow).
// Replaces the tap-to-edit flow in PreviewEditScreen.
// ─────────────────────────────────────────────────────────────────────────────

class ResumeEditorScreen extends ConsumerStatefulWidget {
  const ResumeEditorScreen({super.key});

  @override
  ConsumerState<ResumeEditorScreen> createState() => _ResumeEditorScreenState();
}

class _ResumeEditorScreenState extends ConsumerState<ResumeEditorScreen> {
  String? _resumeId;
  Resume? _resume;
  bool _isLoading = true;
  bool _isSaving = false;

  // In-memory section state — live preview derives from these
  ContactInfo _contact = ContactInfo();
  String _summary = '';
  bool _summaryAIPrefilled = false;
  List<ExperienceEntry> _experience = [];
  List<EducationEntry> _education = [];
  List<SkillEntry> _skills = [];
  List<CertificationEntry> _certifications = [];
  List<SourceDocument> _sourceDocuments = [];

  // One GlobalKey<FormState> per section (stable across rebuilds)
  final _contactFormKey = GlobalKey<FormState>();
  final _summaryFormKey = GlobalKey<FormState>();
  final _experienceFormKey = GlobalKey<FormState>();
  final _educationFormKey = GlobalKey<FormState>();
  final _skillsFormKey = GlobalKey<FormState>();
  final _certsFormKey = GlobalKey<FormState>();

  // Dirty flags — set on any onChanged, cleared after successful Hive write
  bool _contactDirty = false;
  bool _summaryDirty = false;
  bool _experienceDirty = false;
  bool _educationDirty = false;
  bool _skillsDirty = false;
  bool _certsDirty = false;

  final _editorScrollController = ScrollController();

  @override
  void dispose() {
    _editorScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resumeId == null) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _resumeId = args?['resumeId'] as String?;
      _loadResume();
    }
  }

  void _loadResume() {
    if (_resumeId == null) {
      setState(() => _isLoading = false);
      return;
    }
    _resume = HiveService.resumeBox.get(_resumeId);
    debugPrint('[EDITOR] uploadCount on load: ${_resume?.uploadCount}');
    final data = ResumeRenderData.fromHive(_resumeId!);
    _contact = data.contact;
    _summary = data.summary;
    _experience = data.experience;
    _education = data.education;
    _skills = data.skills;
    _certifications = data.certifications;

    final summarySection =
        HiveService.resumeSectionBox.get('${_resumeId}_summary');
    _summaryAIPrefilled = summarySection?.hasUnreviewedAIContent ?? false;

    _loadSourceDocuments();
    setState(() => _isLoading = false);
  }

  void _loadSourceDocuments() {
    if (_resumeId == null) return;
    _sourceDocuments = HiveService.sourceDocumentBox.values
        .where((d) => d.resumeId == _resumeId)
        .toList()
      ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
  }

  void _reloadFromHive() {
    if (_resumeId == null || !mounted) return;
    _resume = HiveService.resumeBox.get(_resumeId);
    final data = ResumeRenderData.fromHive(_resumeId!);
    final summarySection =
        HiveService.resumeSectionBox.get('${_resumeId}_summary');
    _loadSourceDocuments();
    setState(() {
      _contact = data.contact;
      _summary = data.summary;
      _experience = data.experience;
      _education = data.education;
      _skills = data.skills;
      _certifications = data.certifications;
      _summaryAIPrefilled =
          summarySection?.hasUnreviewedAIContent ?? false;
    });
  }

  ResumeRenderData get _liveRenderData => ResumeRenderData(
        contact: _contact,
        summary: _summary,
        experience: _experience,
        education: _education,
        skills: _skills,
        certifications: _certifications,
      );

  // ── Per-section save helpers ───────────────────────────────────────────────

  Future<void> _saveSection(SectionTypeEnum type, String data) async {
    if (_resumeId == null) return;
    final key = '${_resumeId}_${type.name}';
    final existing = HiveService.resumeSectionBox.get(key);
    if (existing != null) {
      existing.data = data;
      await existing.save();
    } else {
      await HiveService.resumeSectionBox.put(
        key,
        ResumeSection(
          id: _uuid.v4(),
          resumeId: _resumeId!,
          type: type,
          data: data,
        ),
      );
    }
  }

  Future<void> _saveContact() async {
    if (_isSaving || _resumeId == null) return;
    setState(() => _isSaving = true);
    try {
      await _saveSection(
          SectionTypeEnum.contact, jsonEncode(_contact.toJson()));
      _contactDirty = false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveSummary() async {
    if (_isSaving || _resumeId == null) return;
    setState(() => _isSaving = true);
    try {
      final key = '${_resumeId}_summary';
      final jsonData = jsonEncode({'text': _summary});
      final existing = HiveService.resumeSectionBox.get(key);
      if (existing != null) {
        existing.data = jsonData;
        existing.hasUnreviewedAIContent = false;
        await existing.save();
      } else {
        await HiveService.resumeSectionBox.put(
          key,
          ResumeSection(
            id: _uuid.v4(),
            resumeId: _resumeId!,
            type: SectionTypeEnum.summary,
            data: jsonData,
          ),
        );
      }
      _summaryDirty = false;
      if (mounted) setState(() => _summaryAIPrefilled = false);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveExperience() async {
    if (_isSaving || _resumeId == null) return;
    setState(() => _isSaving = true);
    try {
      await _saveSection(SectionTypeEnum.experience,
          jsonEncode(_experience.map((e) => e.toJson()).toList()));
      _experienceDirty = false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveEducation() async {
    if (_isSaving || _resumeId == null) return;
    setState(() => _isSaving = true);
    try {
      await _saveSection(SectionTypeEnum.education,
          jsonEncode(_education.map((e) => e.toJson()).toList()));
      _educationDirty = false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveSkills() async {
    if (_isSaving || _resumeId == null) return;
    setState(() => _isSaving = true);
    try {
      await _saveSection(SectionTypeEnum.skills,
          jsonEncode(_skills.map((e) => e.toJson()).toList()));
      _skillsDirty = false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveCertifications() async {
    if (_isSaving || _resumeId == null) return;
    setState(() => _isSaving = true);
    try {
      await _saveSection(SectionTypeEnum.certifications,
          jsonEncode(_certifications.map((e) => e.toJson()).toList()));
      _certsDirty = false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Compliance-review pending decisions ────────────────────────────────
  // Surfaces certifications ResumeMigrationService flagged as *possibly*
  // compliance/administrative training rather than a real credential — the
  // migration never deletes on this basis, so the final call happens here,
  // the next time the user opens this resume's Certifications section.

  PendingEntryDecision _pendingDecisionForCert(CertificationEntry cert) {
    return PendingEntryDecision(
      id: cert.id,
      rawTitle: cert.name,
      rawCompany: cert.issuer,
      rawBullets: const [],
      uncertaintyReason: cert.complianceReviewReason?.isNotEmpty == true
          ? cert.complianceReviewReason!
          : 'This looks like it might be routine compliance/administrative '
              'training rather than a credential.',
      kind: PendingDecisionKind.credentialVsCompliance,
      rawEntry: cert.toJson(),
    );
  }

  void _resolveComplianceReview(String certId, EntryDecision decision) {
    final index = _certifications.indexWhere((c) => c.id == certId);
    if (index == -1) return;

    setState(() {
      if (decision == EntryDecision.exclude) {
        _certifications.removeAt(index);
      } else {
        // "Keep as Certification" — clear the flag, entry stays as-is.
        _certifications[index].needsComplianceReview = false;
        _certifications[index].complianceReviewReason = null;
      }
      _certsDirty = true;
    });
    _saveCertifications();
  }

  // Flush all dirty sections directly to Hive — bypasses the _isSaving guard
  // so it's safe to call even if a collapse-triggered save is in flight.
  // Called by PopScope before allowing back navigation.
  Future<void> _saveAllDirty() async {
    if (_resumeId == null) return;
    final saves = <Future<void>>[];

    if (_contactDirty) {
      saves.add(_saveSection(
          SectionTypeEnum.contact, jsonEncode(_contact.toJson())));
      _contactDirty = false;
    }
    if (_summaryDirty) {
      final key = '${_resumeId}_summary';
      final jsonData = jsonEncode({'text': _summary});
      final existing = HiveService.resumeSectionBox.get(key);
      if (existing != null) {
        existing.data = jsonData;
        existing.hasUnreviewedAIContent = false;
        saves.add(existing.save());
      } else {
        saves.add(HiveService.resumeSectionBox.put(
          key,
          ResumeSection(
            id: _uuid.v4(),
            resumeId: _resumeId!,
            type: SectionTypeEnum.summary,
            data: jsonData,
          ),
        ));
      }
      _summaryDirty = false;
    }
    if (_experienceDirty) {
      saves.add(_saveSection(SectionTypeEnum.experience,
          jsonEncode(_experience.map((e) => e.toJson()).toList())));
      _experienceDirty = false;
    }
    if (_educationDirty) {
      saves.add(_saveSection(SectionTypeEnum.education,
          jsonEncode(_education.map((e) => e.toJson()).toList())));
      _educationDirty = false;
    }
    if (_skillsDirty) {
      saves.add(_saveSection(SectionTypeEnum.skills,
          jsonEncode(_skills.map((e) => e.toJson()).toList())));
      _skillsDirty = false;
    }
    if (_certsDirty) {
      saves.add(_saveSection(SectionTypeEnum.certifications,
          jsonEncode(_certifications.map((e) => e.toJson()).toList())));
      _certsDirty = false;
    }

    if (saves.isNotEmpty) await Future.wait(saves);
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop) return;
    await _saveAllDirty();
    if (mounted) Navigator.pop(context);
  }

  void _onChangeTemplate() {
    Navigator.pushNamed(
      context,
      AppConstants.routeTemplatePicker,
      arguments: {'resumeId': _resumeId},
    );
  }

  void _onExport() {
    Navigator.pushNamed(
      context,
      AppConstants.routeExport,
      arguments: {'resumeId': _resumeId},
    );
  }

  Future<void> _onPrint() async {
    final resume = _resume;
    if (resume == null) return;
    try {
      final bytes = await PdfExportService.generateResumePdf(
        resume: resume,
        data: _liveRenderData,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: resume.displayTitle,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e')),
        );
      }
    }
  }

  Future<void> _onUploadDocument() async {
    if (_resumeId == null || _resume == null) return;
    final tier = ref.read(userSettingsProvider).tier;
    // Read fresh from Hive so the limit check is never stale.
    final freshResume = HiveService.resumeBox.get(_resumeId!);
    if (tier.uploadLimit != -1 &&
        (freshResume?.uploadCount ?? 0) >= tier.uploadLimit) {
      _showEditorUploadLimitDialog(tier);
      return;
    }
    final result = await Navigator.pushNamed(
      context,
      AppConstants.routeDocumentUpload,
      arguments: {'resumeId': _resumeId},
    );
    if (result == true && mounted) {
      _reloadFromHive();
    }
  }

  void _showEditorUploadLimitDialog(TierEnum tier) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Upload limit reached',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'You have used all ${tier.uploadLimit} document slots on the '
          '${tier.displayName} plan. Upgrade to upload more documents.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, AppConstants.routePaywall);
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteDocument(SourceDocument doc) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove document?',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w600),
        ),
        content: Text(
          '${doc.fileName} will be removed from this resume\'s upload '
          'history. Fields already applied from this document will remain.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteSourceDocument(doc);
            },
            child: Text(
              'Remove',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSourceDocument(SourceDocument doc) async {
    await doc.delete();
    final resume = _resume;
    if (resume != null && resume.uploadCount > 0) {
      resume.uploadCount -= 1;
      await resume.save();
    }
    if (mounted) _reloadFromHive();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Resume')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_resume == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Resume')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text('Resume not found',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final atsScore = ref.watch(atsScoreProvider(_resumeId ?? ''));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          return isWide
              ? _buildWideLayout(isDark, atsScore)
              : _buildNarrowLayout(isDark, atsScore);
        },
      ),
    );
  }

  // ── Wide layout: two-pane ──────────────────────────────────────────────────

  Widget _buildWideLayout(bool isDark, int atsScore) {
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFE8E8E8),
      appBar: _buildAppBar(isDark, atsScore, showToolbarActions: true),
      body: Column(
        children: [
          if (_isSaving)
            LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              color: isDark ? AppColors.accentDark : AppColors.accentLightColor,
              minHeight: 2,
            ),
          Expanded(
            child: Row(
              children: [
                // Preview pane — 45%
                Flexible(
                  flex: 45,
                  child: EditorPreviewPane(
                    resume: _resume!,
                    renderData: _liveRenderData,
                    isDark: isDark,
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                ),
                // Form editor pane — 55%
                Flexible(
                  flex: 55,
                  child: _buildEditorContent(isDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Narrow layout: tabbed Preview / Edit ───────────────────────────────────

  Widget _buildNarrowLayout(bool isDark, int atsScore) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : const Color(0xFFE8E8E8),
        appBar: _buildAppBar(
          isDark,
          atsScore,
          showToolbarActions: false,
          bottom: TabBar(
            tabs: const [Tab(text: 'Preview'), Tab(text: 'Edit')],
            labelStyle:
                GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 14),
          ),
        ),
        body: Column(
          children: [
            if (_isSaving)
              LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color:
                    isDark ? AppColors.accentDark : AppColors.accentLightColor,
                minHeight: 2,
              ),
            Expanded(
              child: TabBarView(
                children: [
                  EditorPreviewPane(
                    resume: _resume!,
                    renderData: _liveRenderData,
                    isDark: isDark,
                  ),
                  _buildEditorContent(isDark),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildNarrowBottomBar(isDark),
      ),
    );
  }

  // ── Shared editor content (used in both layouts) ───────────────────────────

  Widget _buildEditorContent(bool isDark) {
    return RawScrollbar(
      thumbVisibility: true,
      controller: _editorScrollController,
      thumbColor: isDark ? Colors.white38 : Colors.black38,
      thickness: 6,
      radius: const Radius.circular(3),
      child: SingleChildScrollView(
        controller: _editorScrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        child: Column(
          children: [
          _sectionCard(
            key: const ValueKey('contact'),
            title: 'Contact',
            icon: Icons.person_outline,
            isDark: isDark,
            onCollapsed: _saveContact,
            child: WizardStepContact(
              data: _contact,
              isUploadPath: false,
              formKey: _contactFormKey,
              onChanged: (c) => setState(() { _contact = c; _contactDirty = true; }),
            ),
          ),
          const SizedBox(height: 8),
          _sectionCard(
            key: const ValueKey('summary'),
            title: 'Summary',
            icon: Icons.notes_outlined,
            isDark: isDark,
            hasAIContent: _summaryAIPrefilled,
            onCollapsed: _saveSummary,
            child: WizardStepSummary(
              initialText: _summary,
              isAIPrefilled: _summaryAIPrefilled,
              formKey: _summaryFormKey,
              onChanged: (s) => setState(() { _summary = s; _summaryDirty = true; }),
              onAIEdited: () => setState(() => _summaryAIPrefilled = false),
            ),
          ),
          const SizedBox(height: 8),
          _sectionCard(
            key: const ValueKey('experience'),
            title: 'Experience',
            icon: Icons.work_outline,
            isDark: isDark,
            onCollapsed: _saveExperience,
            child: WizardStepExperience(
              entries: _experience,
              isUploadPath: false,
              formKey: _experienceFormKey,
              onChanged: (e) {
                final deleted = e.length < _experience.length;
                setState(() { _experience = e; _experienceDirty = true; });
                if (deleted) _saveExperience();
              },
            ),
          ),
          const SizedBox(height: 8),
          _sectionCard(
            key: const ValueKey('education'),
            title: 'Education',
            icon: Icons.school_outlined,
            isDark: isDark,
            onCollapsed: _saveEducation,
            child: WizardStepEducation(
              entries: _education,
              isUploadPath: false,
              formKey: _educationFormKey,
              onChanged: (e) {
                final deleted = e.length < _education.length;
                setState(() { _education = e; _educationDirty = true; });
                if (deleted) _saveEducation();
              },
            ),
          ),
          const SizedBox(height: 8),
          _sectionCard(
            key: const ValueKey('skills'),
            title: 'Skills',
            icon: Icons.bolt_outlined,
            isDark: isDark,
            onCollapsed: _saveSkills,
            child: WizardStepSkills(
              entries: _skills,
              isUploadPath: false,
              formKey: _skillsFormKey,
              onChanged: (s) => setState(() { _skills = s; _skillsDirty = true; }),
            ),
          ),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final flaggedCerts =
                _certifications.where((c) => c.needsComplianceReview).toList();
            return _sectionCard(
              key: const ValueKey('certifications'),
              title: 'Certifications',
              icon: Icons.verified_outlined,
              isDark: isDark,
              subtitle: flaggedCerts.isNotEmpty
                  ? '${flaggedCerts.length} need${flaggedCerts.length == 1 ? 's' : ''} review'
                  : null,
              onCollapsed: _saveCertifications,
              childHeight: flaggedCerts.isEmpty
                  ? 480
                  : 480 + (flaggedCerts.length * 140.0).clamp(0, 420).toDouble(),
              child: Column(
                children: [
                  if (flaggedCerts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Flagged during a data-quality update — '
                            'resolve these before they\'re treated as final:',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppColors.warningDark
                                  : AppColors.warningLight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final cert in flaggedCerts)
                            PendingDecisionCard(
                              key: ValueKey('compliance_review_${cert.id}'),
                              decision: _pendingDecisionForCert(cert),
                              isDark: isDark,
                              onResolve: (choice) =>
                                  _resolveComplianceReview(cert.id, choice),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: WizardStepCertifications(
                      entries: _certifications,
                      isUploadPath: false,
                      formKey: _certsFormKey,
                      onChanged: (c) {
                        final deleted = c.length < _certifications.length;
                        setState(() {
                          _certifications = c;
                          _certsDirty = true;
                        });
                        if (deleted) _saveCertifications();
                      },
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          _buildSourceDocumentsSection(isDark),
        ],
      ),
      ),
    );
  }

  Widget _sectionCard({
    required Key key,
    required String title,
    required IconData icon,
    required bool isDark,
    required VoidCallback onCollapsed,
    required Widget child,
    bool hasAIContent = false,
    double? childHeight = 480,
    String? subtitle,
  }) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final aiColor = isDark ? AppColors.aiIndicatorDark : AppColors.aiIndicator;

    return Container(
      key: key,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Remove ExpansionTile's default divider lines
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          maintainState: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: EdgeInsets.zero,
          leading: Icon(icon, size: 20, color: accent),
          title: Row(
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 6),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (hasAIContent) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: aiColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'AI',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: aiColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          onExpansionChanged: (isExpanded) {
            if (!isExpanded) onCollapsed();
          },
          children: [
            childHeight != null
                ? SizedBox(height: childHeight, child: child)
                : child,
          ],
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(
    bool isDark,
    int atsScore, {
    required bool showToolbarActions,
    PreferredSizeWidget? bottom,
  }) {
    final atsC = _atsColor(atsScore, isDark);
    return AppBar(
      bottom: bottom,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _resume!.displayTitle,
            style: GoogleFonts.playfairDisplay(
                fontSize: 16, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _resume!.isMaster ? 'Master Resume' : 'Tailored Resume',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: 'Home',
          onPressed: () async {
            await _saveAllDirty();
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppConstants.routeDashboard,
                (route) => false,
              );
            }
          },
        ),
        if (!_resume!.isMaster)
          IconButton(
            icon: const Icon(Icons.mail_outline),
            tooltip: 'Cover Letter',
            onPressed: () => Navigator.pushNamed(
              context,
              AppConstants.routeCoverLetterBuilder,
              arguments: {
                'resumeId': _resumeId,
                if (_resume!.linkedJobDescription != null)
                  'jobPostingText': _resume!.linkedJobDescription!,
                if (_resume!.companyName != null)
                  'companyName': _resume!.companyName!,
              },
            ),
          ),
        // ATS score chip
        Semantics(
          label: 'ATS Score: $atsScore out of 100',
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: atsC.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: atsC.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_outlined, size: 12, color: atsC),
                const SizedBox(width: 4),
                Text(
                  'ATS $atsScore',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: atsC,
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.upload_file_outlined),
          tooltip: 'Add Document',
          onPressed: _onUploadDocument,
        ),
        if (showToolbarActions) ...[
          IconButton(
            icon: const Icon(Icons.style_outlined),
            tooltip: 'Template',
            onPressed: _onChangeTemplate,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print',
            onPressed: _onPrint,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Export',
            onPressed: _onExport,
          ),
        ],
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Narrow bottom bar ──────────────────────────────────────────────────────

  Widget _buildNarrowBottomBar(bool isDark) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: border)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: _BarButton(
              icon: Icons.style_outlined,
              label: 'Template',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              onTap: _onChangeTemplate,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _BarButton(
              icon: Icons.print_outlined,
              label: 'Print',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              onTap: _onPrint,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              label: 'Export',
              button: true,
              child: InkWell(
                onTap: _onExport,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.ios_share_outlined,
                          size: 18, color: Colors.white),
                      const SizedBox(height: 2),
                      Text(
                        'Export',
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Source Documents section ───────────────────────────────────────────────

  Widget _buildSourceDocumentsSection(bool isDark) {
    final tier = ref.watch(currentTierProvider);
    final count = _resume?.uploadCount ?? 0;
    debugPrint('[SOURCE DOCS SECTION] Displaying count: $count');
    final subtitle = tier.uploadLimit == -1
        ? '($count uploaded)'
        : '($count / ${tier.uploadLimit})';

    return _sectionCard(
      key: const ValueKey('source_documents'),
      title: 'Source Documents',
      icon: Icons.folder_outlined,
      isDark: isDark,
      onCollapsed: () {},
      childHeight: null,
      subtitle: subtitle,
      child: _SourceDocumentsContent(
        documents: _sourceDocuments,
        isDark: isDark,
        tier: tier,
        uploadCount: count,
        onDelete: _confirmDeleteDocument,
        onUpload: _onUploadDocument,
      ),
    );
  }

  Color _atsColor(int score, bool isDark) {
    if (score >= 70) return isDark ? AppColors.successDark : AppColors.successLight;
    if (score >= 40) return isDark ? AppColors.warningDark : AppColors.warningLight;
    return isDark ? AppColors.errorDark : AppColors.errorLight;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Source Documents section content
// ─────────────────────────────────────────────────────────────────────────────

class _SourceDocumentsContent extends StatelessWidget {
  const _SourceDocumentsContent({
    required this.documents,
    required this.isDark,
    required this.tier,
    required this.uploadCount,
    required this.onDelete,
    required this.onUpload,
  });

  final List<SourceDocument> documents;
  final bool isDark;
  final TierEnum tier;
  final int uploadCount;
  final ValueChanged<SourceDocument> onDelete;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final maxPages = tier.maxPagesPerDocument;
    final slotsText = tier.uploadLimit == -1
        ? 'Unlimited uploads  ·  ${tier.displayName}'
        : '$uploadCount of ${tier.uploadLimit} documents used  ·  '
          '${maxPages != null ? '$maxPages pages max per file' : 'Unlimited pages'}  ·  '
          '${tier.displayName}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slotsText,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (documents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No documents uploaded yet. Add a document to auto-fill your resume.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ...documents.map(
              (doc) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Icon(
                      _fileTypeIcon(doc.fileType),
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.fileName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(doc.uploadedAt),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Remove document',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      onPressed: () => onDelete(doc),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: onUpload,
            icon: const Icon(Icons.upload_file_outlined, size: 16),
            label: const Text('Upload Another Document'),
            style: OutlinedButton.styleFrom(
              textStyle: GoogleFonts.inter(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _fileTypeIcon(FileTypeEnum type) => switch (type) {
        FileTypeEnum.pdf => Icons.picture_as_pdf_outlined,
        FileTypeEnum.docx => Icons.description_outlined,
        FileTypeEnum.txt => Icons.article_outlined,
        FileTypeEnum.image => Icons.image_outlined,
      };

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview pane — pinch-to-zoom, pan, double-tap/pill to reset.
//
// No inline tap-to-edit here (that only ever existed in the old, unrouted
// PreviewEditScreen — ResumeTemplateRenderer's onTapField is never passed
// in this pane, so there's nothing for InteractiveViewer's gestures to
// conflict with). Editing happens in the separate form pane/tab.
// ─────────────────────────────────────────────────────────────────────────────

// Zoom is expressed as a multiplier on top of the fit-to-width baseline
// (the FittedBox below already renders at "fit" when the transform is
// identity) — 1.0 = can't zoom out past fit-to-width, 3.0 = 3x that.
const double _kMinZoomScale = 1.0;
const double _kMaxZoomScale = 3.0;
// Tolerance above baseline before the reset pill appears / zoom counts as
// "on" — avoids flicker from floating-point noise at rest.
const double _kZoomedThreshold = 1.01;

class EditorPreviewPane extends StatefulWidget {
  const EditorPreviewPane({
    super.key,
    required this.resume,
    required this.renderData,
    required this.isDark,
  });

  final Resume resume;
  final ResumeRenderData renderData;
  final bool isDark;

  @override
  State<EditorPreviewPane> createState() => EditorPreviewPaneState();
}

class EditorPreviewPaneState extends State<EditorPreviewPane>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  late final AnimationController _resetAnimController;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_handleTransformChanged);
    _resetAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _transformController.removeListener(_handleTransformChanged);
    _transformController.dispose();
    _resetAnimController.dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    final zoomed =
        _transformController.value.getMaxScaleOnAxis() > _kZoomedThreshold;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  // Resets to fit-to-width. Snaps instantly under reduce-motion (device
  // setting or UserSettings.reduceMotionOverride, already resolved into
  // MediaQuery by the app-wide wrapper in main.dart) — otherwise animates,
  // matching every other transition in the app under that setting.
  void _resetZoom() {
    if (_transformController.value == Matrix4.identity()) return;

    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _transformController.value = Matrix4.identity();
      return;
    }

    final animation = Matrix4Tween(
      begin: _transformController.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _resetAnimController, curve: Curves.easeOut));
    void tick() => _transformController.value = animation.value;
    animation.addListener(tick);
    _resetAnimController.forward(from: 0).whenComplete(() {
      animation.removeListener(tick);
    });
  }

  // Desktop convenience for mouse-only users (no pinch/trackpad available):
  // Ctrl+scroll zooms toward the cursor, the same convention as maps/canvas
  // apps. Trackpad/touch users already get pinch-to-zoom for free via
  // InteractiveViewer itself, so this only needs to cover the mouse-wheel case.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!HardwareKeyboard.instance.isControlPressed) return;

    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final zoomingIn = event.scrollDelta.dy < 0;
    final targetScale = (currentScale * (zoomingIn ? 1.1 : 0.9))
        .clamp(_kMinZoomScale, _kMaxZoomScale);
    if (targetScale == currentScale) return;
    final scaleDelta = targetScale / currentScale;

    // Zoom toward the cursor: convert the pointer's viewport position into
    // the untransformed child's coordinate space, then scale around it.
    final inverse = Matrix4.inverted(_transformController.value);
    final focalPoint = MatrixUtils.transformPoint(inverse, event.localPosition);

    _transformController.value = _transformController.value.clone()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(scaleDelta, scaleDelta, scaleDelta, 1)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
  }

  // Heuristic page count: 1 base + 1 per 3 experience entries
  // + 1 per 10 certifications. Capped at 8 to bound render cost.
  static int _pageCount(ResumeRenderData data) {
    final fromExp = (data.experience.length / 3).ceil();
    final fromCerts = (data.certifications.length / 10).ceil();
    return (1 + fromExp + fromCerts).clamp(1, 8);
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = _pageCount(widget.renderData);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 32;

        // Each page card is a fixed kResumePageWidth × kResumePageHeight window
        // into the full-height renderer, shifted up by i pages using Positioned.
        // Container.clipBehavior clips overflow so only page i's slice shows.
        final pageCards = List.generate(pageCount, (i) {
          return Container(
            margin: EdgeInsets.only(bottom: i < pageCount - 1 ? 12 : 0),
            width: kResumePageWidth,
            height: kResumePageHeight,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -(i * kResumePageHeight),
                  left: 0,
                  child: SizedBox(
                    width: kResumePageWidth,
                    child: ResumeTemplateRenderer(
                      resume: widget.resume,
                      data: widget.renderData,
                    ),
                  ),
                ),
              ],
            ),
          );
        });

        return Stack(
          children: [
            Semantics(
              container: true,
              label: 'Resume preview. Pinch to zoom, double-tap to reset.',
              child: Listener(
                onPointerSignal: _handlePointerSignal,
                child: GestureDetector(
                  onDoubleTap: _resetZoom,
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    // Content (the page-card Column) is taller than the
                    // viewport for multi-page resumes even at baseline zoom,
                    // so it needs its own natural size rather than being
                    // squeezed into the viewport's bounds.
                    constrained: false,
                    minScale: _kMinZoomScale,
                    maxScale: _kMaxZoomScale,
                    boundaryMargin: const EdgeInsets.all(40),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: availableWidth,
                        child: FittedBox(
                          fit: BoxFit.fitWidth,
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: pageCards,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_isZoomed)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: _ZoomResetPill(onTap: _resetZoom, isDark: widget.isDark),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Zoom reset pill — floating chip shown when scale != 1×
// ─────────────────────────────────────────────────────────────────────────────

class _ZoomResetPill extends StatelessWidget {
  const _ZoomResetPill({required this.onTap, required this.isDark});
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Semantics(
      label: 'Reset zoom',
      button: true,
      // Without this, the descendant Icon/Text also contribute their own
      // semantics nodes, and screen readers get a redundant/duplicated
      // announcement instead of one clean "Reset zoom, button".
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          // Keeps the existing, already-on-brand visual pill exactly as
          // designed while guaranteeing the tappable area meets the app's
          // 48dp minimum tap target — the extra hit area is invisible.
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_out_map, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    'Reset zoom',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accent,
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

// ─────────────────────────────────────────────────────────────────────────────
// Bottom bar button
// ─────────────────────────────────────────────────────────────────────────────

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
