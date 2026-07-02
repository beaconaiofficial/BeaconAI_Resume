import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';
import '../constants/sample_resume_data.dart';
import '../models/resume.dart';
import '../theme/app_colors.dart';
import '../widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FirstResumeSetupScreen
//
// Spec:
//  - Shown after onboarding for new users with no master resume.
//  - Step 1: choose a template — thumbnail grid of all 12 with sample data.
//  - Step 2: choose a path — (A) Upload Existing Resume or (B) Build From Scratch.
//  - Both paths lead into the Resume Builder Wizard.
//  - Template can be changed at any time — selection here is non-destructive.
//
// All 12 templates are available at first setup — no phase gating in user-facing UI.
// ─────────────────────────────────────────────────────────────────────────────

class FirstResumeSetupScreen extends StatefulWidget {
  const FirstResumeSetupScreen({super.key});

  @override
  State<FirstResumeSetupScreen> createState() => _FirstResumeSetupScreenState();
}

class _FirstResumeSetupScreenState extends State<FirstResumeSetupScreen> {
  // Step 1 = template selection, Step 2 = path selection
  int _step = 1;
  String _selectedTemplateId = AppConstants.defaultTemplateId;

  void _onTemplateSelected(String templateId) {
    setState(() => _selectedTemplateId = templateId);
  }

  void _onContinueFromTemplates() {
    setState(() => _step = 2);
  }

  void _onBackToTemplates() {
    setState(() => _step = 1);
  }

  Future<void> _onUploadPath() async {
    // Open document upload in first-setup mode: DocumentUploadScreen returns
    // the prefill map when the user taps Apply All; null if they back out.
    final result = await Navigator.pushNamed(
      context,
      AppConstants.routeDocumentUpload,
      arguments: {'firstSetupMode': true},
    );

    if (!mounted) return;

    if (result is Map<String, dynamic>) {
      // Upload completed — open wizard with extracted data pre-populated
      Navigator.pushReplacementNamed(
        context,
        AppConstants.routeResumeBuilderWizard,
        arguments: {
          'path': 'upload',
          'templateId': _selectedTemplateId,
          'prefillData': result,
        },
      );
    }
    // If null, user cancelled — stay on FirstResumeSetupScreen
  }

  void _onScratchPath() {
    Navigator.pushReplacementNamed(
      context,
      AppConstants.routeResumeBuilderWizard,
      arguments: {
        'path': 'scratch',
        'templateId': _selectedTemplateId,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: _step == 1
              ? _TemplatePickerStep(
                  key: const ValueKey('step1'),
                  selectedTemplateId: _selectedTemplateId,
                  onSelected: _onTemplateSelected,
                  onContinue: _onContinueFromTemplates,
                  isDark: isDark,
                )
              : _PathSelectionStep(
                  key: const ValueKey('step2'),
                  selectedTemplateId: _selectedTemplateId,
                  onBack: _onBackToTemplates,
                  onUpload: _onUploadPath,
                  onScratch: _onScratchPath,
                  isDark: isDark,
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 — Template Picker
// ─────────────────────────────────────────────────────────────────────────────

class _TemplatePickerStep extends StatelessWidget {
  const _TemplatePickerStep({
    super.key,
    required this.selectedTemplateId,
    required this.onSelected,
    required this.onContinue,
    required this.isDark,
  });

  final String selectedTemplateId;
  final ValueChanged<String> onSelected;
  final VoidCallback onContinue;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a template',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'All 12 templates are free — switch any time without losing your content.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Template grid ─────────────────────────────────────────────────────
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.72, // portrait resume proportion
            ),
            itemCount: _allTemplates.length,
            itemBuilder: (context, i) {
              final template = _allTemplates[i];
              final isSelected = template.id == selectedTemplateId;
              final isAvailable = template.phase == 1;

              return _TemplateThumbnail(
                template: template,
                isSelected: isSelected,
                isAvailable: isAvailable,
                isDark: isDark,
                onTap: isAvailable ? () => onSelected(template.id) : null,
              );
            },
          ),
        ),

        // ── Footer ────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onContinue,
              child: const Text('Continue'),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template Thumbnail
// ─────────────────────────────────────────────────────────────────────────────

class _TemplateThumbnail extends StatelessWidget {
  const _TemplateThumbnail({
    required this.template,
    required this.isSelected,
    required this.isAvailable,
    required this.isDark,
    required this.onTap,
  });

  final _TemplateInfo template;
  final bool isSelected;
  final bool isAvailable;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    return Semantics(
      label:
          '${template.name} template${isSelected ? ', selected' : ''}${!isAvailable ? ', coming soon' : ''}',
      button: isAvailable,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isAvailable ? surface : surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? accent : border,
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Real template preview ────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: _ScaledSamplePreview(templateId: template.id),
              ),

              // ── Template name bar ────────────────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(9),
                      bottomRight: Radius.circular(9),
                    ),
                    border: Border(
                      top: BorderSide(color: border),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          template.name,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isAvailable ? onSurface : onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: border,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'Ph.${template.phase}',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Selected checkmark ───────────────────────────────────────
              if (isSelected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),

              // ── Coming soon overlay ──────────────────────────────────────
              if (!isAvailable)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: (isDark
                              ? AppColors.backgroundDark
                              : AppColors.backgroundLight)
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scaled sample preview — renders the real template at thumbnail scale
// using a static persona. Never touches the user's Hive data.
// ─────────────────────────────────────────────────────────────────────────────

class _ScaledSamplePreview extends StatelessWidget {
  const _ScaledSamplePreview({required this.templateId});

  final String templateId;

  // Each template previews with a sample persona matching its actual target
  // audience — a civilian software engineer for the Technical template, a
  // recent grad for Entry, and so on. Jane Rivera (Army-jargon persona) is
  // reserved for the Veteran template only; she should never be the preview
  // persona for a template aimed at a general, non-military audience.
  static final Map<String, ResumeRenderData> _personaByTemplate = {
    AppConstants.templateTechnical: SampleResumeData.marcusChen,
    AppConstants.templateSharp: SampleResumeData.elenaVasquez,
    AppConstants.templateSidebar: SampleResumeData.priyaNair,
    AppConstants.templatePillar: SampleResumeData.owenBennett,
    AppConstants.templateEntry: SampleResumeData.mayaThompson,
    AppConstants.templateVeteran: SampleResumeData.janeRivera,
  };

  @override
  Widget build(BuildContext context) {
    final data =
        _personaByTemplate[templateId] ?? SampleResumeData.johnCarter;
    final resume = Resume(
      id: 'sample_$templateId',
      title: 'Sample',
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      isMaster: false,
      templateId: templateId,
    );
    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: kResumePageWidth,
        height: kResumePageHeight,
        child: ResumeTemplateRenderer(
          resume: resume,
          data: data,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 — Path Selection (Upload vs Scratch)
// ─────────────────────────────────────────────────────────────────────────────

class _PathSelectionStep extends StatelessWidget {
  const _PathSelectionStep({
    super.key,
    required this.selectedTemplateId,
    required this.onBack,
    required this.onUpload,
    required this.onScratch,
    required this.isDark,
  });

  final String selectedTemplateId;
  final VoidCallback onBack;
  final VoidCallback onUpload;
  final VoidCallback onScratch;
  final bool isDark;

  String get _selectedTemplateName {
    return _allTemplates
        .firstWhere((t) => t.id == selectedTemplateId,
            orElse: () => _allTemplates.first)
        .name;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Back ──────────────────────────────────────────────────────────
          GestureDetector(
            onTap: onBack,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_ios,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Templates',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── Heading ───────────────────────────────────────────────────────
          Text(
            'How do you want to start?',
            style: GoogleFonts.playfairDisplay(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.2,
            ),
          ),

          const SizedBox(height: 8),

          // Template selection confirmation chip
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 14,
                color: isDark ? AppColors.successDark : AppColors.successLight,
              ),
              const SizedBox(width: 6),
              Text(
                '$_selectedTemplateName template selected',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color:
                      isDark ? AppColors.successDark : AppColors.successLight,
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),

          // ── Path A — Upload ───────────────────────────────────────────────
          _PathCard(
            icon: Icons.upload_file_outlined,
            title: 'Upload Existing Resume',
            description:
                'Have a resume already? Upload a PDF, Word doc, or image and AI extracts your info automatically.',
            ctaLabel: 'Upload & Build',
            onTap: onUpload,
            isProminent: true,
            isDark: isDark,
          ),

          const SizedBox(height: 16),

          // ── Path B — Scratch ──────────────────────────────────────────────
          _PathCard(
            icon: Icons.edit_outlined,
            title: 'Build From Scratch',
            description:
                'Start with a blank slate. Guided prompts walk you through each section with tips for every field.',
            ctaLabel: 'Start Fresh',
            onTap: onScratch,
            isProminent: false,
            isDark: isDark,
          ),

          const Spacer(),

          // ── Reassurance note ──────────────────────────────────────────────
          Center(
            child: Text(
              'You can upload documents at any point during editing.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Path Card
// ─────────────────────────────────────────────────────────────────────────────

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.ctaLabel,
    required this.onTap,
    required this.isProminent,
    required this.isDark,
  });

  final IconData icon;
  final String title;
  final String description;
  final String ctaLabel;
  final VoidCallback onTap;
  final bool isProminent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Semantics(
      label: '$title — $description',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isProminent
                ? (isDark
                    ? AppColors.accentLightTintDark
                    : AppColors.accentLightTint)
                : surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isProminent ? accent : border,
              width: isProminent ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isProminent
                      ? accent.withValues(alpha: 0.12)
                      : (isDark
                          ? AppColors.backgroundDark
                          : AppColors.backgroundLight),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: accent),
              ),

              const SizedBox(width: 16),

              // Text + CTA
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Inline CTA
                    Row(
                      children: [
                        Text(
                          ctaLabel,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward, size: 14, color: accent),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template Data
// ─────────────────────────────────────────────────────────────────────────────

class _TemplateInfo {
  const _TemplateInfo({
    required this.id,
    required this.name,
    required this.phase,
    this.hasAccentHeader = false,
  });

  final String id;
  final String name;
  final int phase; // 1, 2, or 3
  final bool hasAccentHeader; // drives mockup rendering style
}

/// All 12 templates in display order — all available, no phase gating.
const List<_TemplateInfo> _allTemplates = [
  _TemplateInfo(id: AppConstants.templateClean, name: 'Clean', phase: 1),
  _TemplateInfo(id: AppConstants.templateClassic, name: 'Classic', phase: 1),
  _TemplateInfo(id: AppConstants.templateSharp, name: 'Sharp', phase: 1),
  _TemplateInfo(id: AppConstants.templateEntry, name: 'Entry', phase: 1),
  _TemplateInfo(id: AppConstants.templateElevated, name: 'Elevated', phase: 1),
  _TemplateInfo(id: AppConstants.templateFederal, name: 'Federal', phase: 1),
  _TemplateInfo(id: AppConstants.templateAcademic, name: 'Academic', phase: 1),
  _TemplateInfo(id: AppConstants.templateVeteran, name: 'Veteran', phase: 1),
  _TemplateInfo(id: AppConstants.templateTechnical, name: 'Technical', phase: 1),
  _TemplateInfo(
      id: AppConstants.templateHorizon,
      name: 'Horizon',
      phase: 1,
      hasAccentHeader: true),
  _TemplateInfo(id: AppConstants.templateSidebar, name: 'Sidebar', phase: 1),
  _TemplateInfo(id: AppConstants.templatePillar, name: 'Pillar', phase: 1),
];
