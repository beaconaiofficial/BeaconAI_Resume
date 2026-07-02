import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';

import '../constants/app_constants.dart';
import '../services/pdf_export_service.dart';
import '../models/resume.dart';
import '../models/resume_sections.dart';
import '../models/app_enums.dart';
import '../providers/resume_provider.dart';
import '../providers/user_settings_provider.dart';
import '../services/hive_service.dart';
import '../theme/app_colors.dart';
import '../widgets/ai_suggestions_panel.dart';
import '../widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PreviewEditScreen
//
// Spec §4 (Preview & Edit):
//  - Live resume preview in chosen template.
//  - Tap any text to edit inline.
//  - Changes sync to data model in real time.
//  - 'Export' and 'Print' buttons available.
//  - Auto-saves to local device on any edit.
//  - Reached after Ad Gate (Free) or directly after submission (Basic+).
// ─────────────────────────────────────────────────────────────────────────────

class PreviewEditScreen extends ConsumerStatefulWidget {
  const PreviewEditScreen({super.key});

  @override
  ConsumerState<PreviewEditScreen> createState() => _PreviewEditScreenState();
}

class _PreviewEditScreenState extends ConsumerState<PreviewEditScreen> {
  String? _resumeId;
  Resume? _resume;
  ResumeRenderData? _renderData;
  bool _isLoading = true;
  bool _isSaving = false;

  // Inline edit state
  bool _editMode = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _resumeId = args['resumeId'] as String?;
    }
    if (_resumeId != null && _isLoading) {
      _loadResume();
    }
  }

  Future<void> _loadResume() async {
    final resume = HiveService.resumeBox.get(_resumeId);
    final data =
        _resumeId != null ? ResumeRenderData.fromHive(_resumeId!) : null;

    if (mounted) {
      setState(() {
        _resume = resume;
        _renderData = data;
        _isLoading = false;
      });
    }
  }

  // ── Inline field editing ──────────────────────────────────────────────────

  void _onTapField(String fieldId, String currentValue) {
    if (!_editMode) return;
    final tier = ref.read(currentTierProvider);
    final isAiEligibleField =
        fieldId == 'summary' || fieldId.contains('bullet');

    if (tier.isPro && isAiEligibleField) {
      _showFieldActionSheet(fieldId, currentValue);
      return;
    }

    _showInlineEditDialog(fieldId, currentValue);
  }

  void _showInlineEditDialog(String fieldId, String currentValue) {
    final controller = TextEditingController(text: currentValue);
    final label = _fieldLabel(fieldId);
    final isMultiline = fieldId.contains('bullet') || fieldId == 'summary';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          label,
          style: GoogleFonts.playfairDisplay(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: isMultiline ? 4 : 1,
          decoration: InputDecoration(
            hintText: 'Enter $label',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _applyFieldEdit(fieldId, controller.text.trim());
              controller.dispose();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showFieldActionSheet(String fieldId, String currentValue) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit manually'),
              onTap: () {
                Navigator.pop(ctx);
                _showInlineEditDialog(fieldId, currentValue);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.auto_awesome,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.aiIndicatorDark
                    : AppColors.aiIndicator,
              ),
              title: const Text('AI Suggest'),
              onTap: () {
                Navigator.pop(ctx);
                _openAiSuggestions(fieldId, currentValue);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAiSuggestions(String fieldId, String currentValue) async {
    final mode = fieldId == 'summary'
        ? AiSuggestionMode.summaryGenerate
        : AiSuggestionMode.bulletRewrite;

    String? jobTitle;
    if (fieldId.contains('bullet')) {
      final indexMatch = RegExp(r'\[(\d+)\]').firstMatch(fieldId);
      if (indexMatch != null) {
        final idx = int.parse(indexMatch.group(1)!);
        if (_renderData != null && idx < _renderData!.experience.length) {
          jobTitle = _renderData!.experience[idx].title;
        }
      }
    }

    final result = await showAiSuggestionsPanel(
      context: context,
      mode: mode,
      currentText: currentValue,
      jobTitle: jobTitle,
      topSkills: _renderData?.skills.map((s) => s.name).toList(),
    );

    if (result != null && result.isNotEmpty) {
      await _applyFieldEdit(fieldId, result);
    }
  }

  // TODO(step5): Visual sparkle badge on AI-eligible fields (summary, bullets)
  // when editMode == true && tier.isPro. Deferred — requires changes to
  // resume_template_renderer.dart tappable() helper to accept an optional
  // trailing icon parameter.

  /// Applies an inline edit to the correct section in Hive and refreshes.
  Future<void> _applyFieldEdit(String fieldId, String newValue) async {
    if (_resumeId == null || _renderData == null) return;
    setState(() => _isSaving = true);

    try {
      final parts = fieldId.split('.');
      // Strip array index so 'experience[0]' → 'experience'
      final section = parts[0].replaceAll(RegExp(r'\[\d+\]'), '');
      final indexMatch = RegExp(r'\[(\d+)\]').firstMatch(fieldId);

      switch (section) {
        case 'contact':
          final field = parts.length > 1 ? parts[1] : '';
          final updated =
              _applyContactEdit(_renderData!.contact, field, newValue);
          await _saveSection(
              SectionTypeEnum.contact, jsonEncode(updated.toJson()));

        case 'summary':
          await _saveSection(
              SectionTypeEnum.summary, jsonEncode({'text': newValue}));

        case 'experience':
          final expList = List<ExperienceEntry>.from(_renderData!.experience);
          if (indexMatch != null) {
            final idx = int.parse(indexMatch.group(1)!);
            if (idx < expList.length) {
              expList[idx] = _applyExperienceEdit(
                  expList[idx], parts.sublist(1).join('.'), newValue);
            }
          }
          await _saveSection(SectionTypeEnum.experience,
              jsonEncode(expList.map((e) => e.toJson()).toList()));

        case 'education':
          final eduList = List<EducationEntry>.from(_renderData!.education);
          if (indexMatch != null) {
            final idx = int.parse(indexMatch.group(1)!);
            if (idx < eduList.length) {
              eduList[idx] = _applyEducationEdit(eduList[idx],
                  parts.length > 1 ? parts.sublist(1).join('.') : '', newValue);
            }
          }
          await _saveSection(SectionTypeEnum.education,
              jsonEncode(eduList.map((e) => e.toJson()).toList()));

        case 'skills':
          final skillList = List<SkillEntry>.from(_renderData!.skills);
          if (indexMatch != null) {
            final idx = int.parse(indexMatch.group(1)!);
            if (idx < skillList.length) {
              skillList[idx] = SkillEntry(
                id: skillList[idx].id,
                name: newValue,
                category: skillList[idx].category,
              );
            }
          }
          await _saveSection(SectionTypeEnum.skills,
              jsonEncode(skillList.map((s) => s.toJson()).toList()));

        case 'certifications':
          final certList =
              List<CertificationEntry>.from(_renderData!.certifications);
          if (indexMatch != null) {
            final idx = int.parse(indexMatch.group(1)!);
            if (idx < certList.length) {
              certList[idx] = _applyCertificationEdit(certList[idx],
                  parts.length > 1 ? parts.sublist(1).join('.') : '', newValue);
            }
          }
          await _saveSection(SectionTypeEnum.certifications,
              jsonEncode(certList.map((c) => c.toJson()).toList()));
      }

      // Reload render data
      final fresh = ResumeRenderData.fromHive(_resumeId!);
      if (mounted) setState(() => _renderData = fresh);

      // Touch the resume updatedAt
      _resume?.touch();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  ContactInfo _applyContactEdit(ContactInfo c, String field, String value) {
    if (field == 'fullName') {
      // Split on first space: "Jane Doe Smith" → firstName="Jane", lastName="Doe Smith"
      final spaceIdx = value.indexOf(' ');
      final first =
          spaceIdx >= 0 ? value.substring(0, spaceIdx).trim() : value.trim();
      final last = spaceIdx >= 0 ? value.substring(spaceIdx + 1).trim() : '';
      return ContactInfo(
          firstName: first,
          lastName: last,
          professionalTitle: c.professionalTitle,
          city: c.city,
          state: c.state,
          phone: c.phone,
          email: c.email,
          linkedInUrl: c.linkedInUrl,
          websiteUrl: c.websiteUrl,
          gitHubUrl: c.gitHubUrl);
    }
    if (field == 'cityState') {
      // Split on ", " — supports "City, ST" or "City, State"
      final p = value.split(', ');
      return ContactInfo(
          firstName: c.firstName,
          lastName: c.lastName,
          professionalTitle: c.professionalTitle,
          city: p.isNotEmpty ? p[0].trim() : c.city,
          state: p.length > 1 ? p.sublist(1).join(', ').trim() : c.state,
          phone: c.phone,
          email: c.email,
          linkedInUrl: c.linkedInUrl,
          websiteUrl: c.websiteUrl,
          gitHubUrl: c.gitHubUrl);
    }
    return ContactInfo(
      firstName: field == 'firstName' ? value : c.firstName,
      lastName: field == 'lastName' ? value : c.lastName,
      professionalTitle:
          field == 'professionalTitle' ? value : c.professionalTitle,
      city: field == 'city' ? value : c.city,
      state: field == 'state' ? value : c.state,
      phone: field == 'phone' ? value : c.phone,
      email: field == 'email' ? value : c.email,
      linkedInUrl: field == 'linkedInUrl' ? value : c.linkedInUrl,
      websiteUrl: field == 'websiteUrl' ? value : c.websiteUrl,
      gitHubUrl: field == 'gitHubUrl' ? value : c.gitHubUrl,
    );
  }

  ExperienceEntry _applyExperienceEdit(
      ExperienceEntry e, String field, String value) {
    if (field.startsWith('bullet.')) {
      final bulletIdx = int.tryParse(field.split('.').last) ?? 0;
      final bullets = List<String>.from(e.bullets);
      if (bulletIdx < bullets.length) bullets[bulletIdx] = value;
      return ExperienceEntry(
          id: e.id,
          title: e.title,
          company: e.company,
          location: e.location,
          startDate: e.startDate,
          endDate: e.endDate,
          isCurrent: e.isCurrent,
          bullets: bullets);
    }
    if (field == 'endDate') {
      final isCurrent = value.trim().toLowerCase() == 'present';
      return ExperienceEntry(
          id: e.id,
          title: e.title,
          company: e.company,
          location: e.location,
          startDate: e.startDate,
          endDate: isCurrent ? null : value,
          isCurrent: isCurrent,
          bullets: e.bullets);
    }
    return ExperienceEntry(
      id: e.id,
      title: field == 'title' ? value : e.title,
      company: field == 'company' ? value : e.company,
      location: field == 'location' ? value : e.location,
      startDate: field == 'startDate' ? value : e.startDate,
      endDate: e.endDate,
      isCurrent: e.isCurrent,
      bullets: e.bullets,
    );
  }

  EducationEntry _applyEducationEdit(
      EducationEntry e, String field, String value) {
    return EducationEntry(
      id: e.id,
      degree: field == 'degree' ? value : e.degree,
      institution: field == 'institution' ? value : e.institution,
      fieldOfStudy: field == 'fieldOfStudy' ? value : e.fieldOfStudy,
      graduationYear: field == 'graduationYear' ? value : e.graduationYear,
      gpa: field == 'gpa' ? (value.isEmpty ? null : value) : e.gpa,
    );
  }

  CertificationEntry _applyCertificationEdit(
      CertificationEntry c, String field, String value) {
    return CertificationEntry(
      id: c.id,
      name: field == 'name' ? value : c.name,
      issuer: field == 'issuer' ? value : c.issuer,
      dateEarned: field == 'dateEarned' ? value : c.dateEarned,
      expiresDate: c.expiresDate,
      credentialId: c.credentialId,
    );
  }

  Future<void> _saveSection(SectionTypeEnum type, String data) async {
    final key = '${_resumeId}_${type.name}';
    final existing = HiveService.resumeSectionBox.get(key);
    if (existing != null) {
      existing.data = data;
      await existing.save();
    }
  }

  String _fieldLabel(String fieldId) {
    if (fieldId == 'contact.fullName') return 'Full Name';
    if (fieldId == 'contact.professionalTitle') return 'Professional Title';
    if (fieldId == 'contact.cityState') return 'City, State';
    if (fieldId == 'contact.phone') return 'Phone';
    if (fieldId == 'contact.email') return 'Email';
    if (fieldId == 'contact.linkedInUrl') return 'LinkedIn URL';
    if (fieldId == 'contact.websiteUrl') return 'Website URL';
    if (fieldId == 'contact.gitHubUrl') return 'GitHub URL';
    if (fieldId == 'summary') return 'Professional Summary';
    if (fieldId.contains('bullet')) return 'Achievement Bullet';
    if (fieldId.contains('.title')) return 'Job Title';
    if (fieldId.contains('.company')) return 'Company';
    if (fieldId.contains('.location')) return 'Location';
    if (fieldId.contains('.startDate')) return 'Start Date';
    if (fieldId.contains('.endDate')) return 'End Date';
    if (fieldId.contains('.institution')) return 'Institution';
    if (fieldId.contains('.degree')) return 'Degree';
    if (fieldId.contains('.fieldOfStudy')) return 'Field of Study';
    if (fieldId.contains('.graduationYear')) return 'Graduation Year';
    if (fieldId.contains('.gpa')) return 'GPA';
    if (fieldId.startsWith('skills[')) return 'Skill';
    if (fieldId.contains('.issuer')) return 'Issuer';
    if (fieldId.contains('.dateEarned')) return 'Date Earned';
    if (fieldId.contains('.name') && fieldId.startsWith('certifications')) {
      return 'Certification Name';
    }
    return 'Field';
  }

  // ── Template switcher ──────────────────────────────────────────────────────

  void _onChangeTemplate() {
    Navigator.pushNamed(
      context,
      AppConstants.routeTemplatePicker,
      arguments: {'resumeId': _resumeId},
    ).then((_) => _loadResume());
  }

  // ── Export / Print ─────────────────────────────────────────────────────────

  void _onExport() {
    Navigator.pushNamed(
      context,
      AppConstants.routeExport,
      arguments: {'resumeId': _resumeId},
    );
  }

  Future<void> _onPrint() async {
    final resume = _resume;
    final data = _renderData;
    if (resume == null || data == null) return;

    try {
      final bytes = await PdfExportService.generateResumePdf(
        resume: resume,
        data: data,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: resume.displayTitle,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: ${e.toString()}')),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tier = ref.watch(currentTierProvider);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Preview')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_resume == null || _renderData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Preview')),
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

    final atsScore = ref.watch(atsScoreProvider(_resumeId ?? ''));

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFE8E8E8),
      appBar: _buildAppBar(context, isDark, atsScore, tier),
      body: Column(
        children: [
          // ── Edit mode banner ───────────────────────────────────────────────
          if (_editMode)
            _EditModeBanner(
              onDone: () => setState(() => _editMode = false),
              isDark: isDark,
            ),

          // ── Saving indicator ───────────────────────────────────────────────
          if (_isSaving)
            LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              color: isDark ? AppColors.accentDark : AppColors.accentLightColor,
              minHeight: 2,
            ),

          // ── Resume preview ─────────────────────────────────────────────────
          Expanded(
            child: _renderData!.isEmpty
                ? _EmptyResumeState(
                    isDark: isDark,
                    onEdit: () => Navigator.pushNamed(
                      context,
                      AppConstants.routeResumeBuilderWizard,
                    ),
                  )
                : _ResumePreviewScroller(
                    resume: _resume!,
                    renderData: _renderData!,
                    editMode: _editMode,
                    onTapField: _onTapField,
                    isDark: isDark,
                  ),
          ),
        ],
      ),

      // ── Bottom action bar ──────────────────────────────────────────────────
      bottomNavigationBar: _BottomActionBar(
        editMode: _editMode,
        isDark: isDark,
        onToggleEdit: () => setState(() => _editMode = !_editMode),
        onExport: _onExport,
        onPrint: _onPrint,
        onChangeTemplate: _onChangeTemplate,
      ),
    );
  }

  AppBar _buildAppBar(
      BuildContext context, bool isDark, int atsScore, TierEnum tier) {
    return AppBar(
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
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            AppConstants.routeDashboard,
            (route) => false,
          ),
        ),
        // Cover letter button — only for tailored resumes
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
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _atsColor(atsScore, isDark).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: _atsColor(atsScore, isDark).withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_outlined,
                    size: 12, color: _atsColor(atsScore, isDark)),
                const SizedBox(width: 4),
                Text(
                  'ATS $atsScore',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _atsColor(atsScore, isDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _atsColor(int score, bool isDark) {
    if (score >= 70) {
      return isDark ? AppColors.successDark : AppColors.successLight;
    }
    if (score >= 40) {
      return isDark ? AppColors.warningDark : AppColors.warningLight;
    }
    return isDark ? AppColors.errorDark : AppColors.errorLight;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Resume Preview Scroller
// Renders the resume in a scrollable, zoomable container.
// The resume renders at fixed print size (816px wide) and scales to fit screen.
// ─────────────────────────────────────────────────────────────────────────────

class _ResumePreviewScroller extends StatefulWidget {
  const _ResumePreviewScroller({
    required this.resume,
    required this.renderData,
    required this.editMode,
    required this.onTapField,
    required this.isDark,
  });

  final Resume resume;
  final ResumeRenderData renderData;
  final bool editMode;
  final void Function(String, String) onTapField;
  final bool isDark;

  @override
  State<_ResumePreviewScroller> createState() => _ResumePreviewScrollerState();
}

class _ResumePreviewScrollerState extends State<_ResumePreviewScroller> {
  final TransformationController _controller = TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _controller.value.getMaxScaleOnAxis();
    final zoomed = (scale - 1.0).abs() > 0.01;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _resetZoom() {
    _controller.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Scale the 816px-wide resume to fit the screen width with padding.
        final availableWidth = constraints.maxWidth - 32;
        final scale = availableWidth / kResumePageWidth;

        final previewContent = Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SizedBox(
              width: availableWidth,
              height: kResumePageHeight * scale,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.fill,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: kResumePageWidth,
                    height: kResumePageHeight,
                    child: Stack(
                      children: [
                        // Shadow underneath
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Template
                        ResumeTemplateRenderer(
                          resume: widget.resume,
                          data: widget.renderData,
                          onTapField: widget.editMode ? widget.onTapField : null,
                        ),
                        // Edit overlay — subtle tap indicators when in edit mode
                        if (widget.editMode)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.accentLightColor
                                        .withValues(alpha: 0.3),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        return Stack(
          children: [
            // Pinch-to-zoom viewer. GestureDetector catches double-tap to
            // reset without interfering with InteractiveViewer's pan/pinch
            // recognizers (they handle different gesture sequences).
            GestureDetector(
              onDoubleTap: _resetZoom,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 0.5,
                maxScale: 3.0,
                boundaryMargin: const EdgeInsets.all(20),
                child: previewContent,
              ),
            ),

            // Floating reset pill — visible only when zoom != 1×.
            if (_isZoomed)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: _ZoomResetPill(
                    onTap: _resetZoom,
                    isDark: widget.isDark,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Zoom Reset Pill — floating chip shown when InteractiveViewer scale != 1×
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

    return GestureDetector(
      onTap: onTap,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Mode Banner
// ─────────────────────────────────────────────────────────────────────────────

class _EditModeBanner extends StatelessWidget {
  const _EditModeBanner({required this.onDone, required this.isDark});
  final VoidCallback onDone;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Semantics(
      liveRegion: true,
      label: 'Edit mode active — tap any text on the resume to edit it',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: accent.withValues(alpha: 0.1),
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tap any text on the resume to edit it',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: onDone,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
              ),
              child: Text('Done',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accent)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Action Bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.editMode,
    required this.isDark,
    required this.onToggleEdit,
    required this.onExport,
    required this.onPrint,
    required this.onChangeTemplate,
  });

  final bool editMode;
  final bool isDark;
  final VoidCallback onToggleEdit;
  final VoidCallback onExport;
  final VoidCallback onPrint;
  final VoidCallback onChangeTemplate;

  @override
  Widget build(BuildContext context) {
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
          // Edit toggle
          Expanded(
            child: _BarButton(
              icon: editMode ? Icons.check_circle_outline : Icons.edit_outlined,
              label: editMode ? 'Done Editing' : 'Edit',
              color: editMode
                  ? (isDark ? AppColors.successDark : AppColors.successLight)
                  : accent,
              onTap: onToggleEdit,
            ),
          ),
          const SizedBox(width: 8),

          // Template
          Expanded(
            child: _BarButton(
              icon: Icons.style_outlined,
              label: 'Template',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              onTap: onChangeTemplate,
            ),
          ),
          const SizedBox(width: 8),

          // Print
          Expanded(
            child: _BarButton(
              icon: Icons.print_outlined,
              label: 'Print',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              onTap: onPrint,
            ),
          ),
          const SizedBox(width: 8),

          // Export — primary CTA
          Expanded(
            child: Semantics(
              label: 'Export',
              button: true,
              child: InkWell(
                onTap: onExport,
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
}

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
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w500, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty Resume State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyResumeState extends StatelessWidget {
  const _EmptyResumeState({required this.isDark, required this.onEdit});
  final bool isDark;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text(
              'Your resume is empty',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Add your experience, education, and skills to see the preview.',
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Fill in your resume'),
            ),
          ],
        ),
      ),
    );
  }
}
