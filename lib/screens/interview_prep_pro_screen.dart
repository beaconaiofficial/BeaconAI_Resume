import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../models/app_enums.dart';
import '../models/supporting_models.dart';
import '../providers/connectivity_provider.dart';
import '../services/cloudflare_worker_service.dart';
import '../services/hive_service.dart';
import '../services/phase3_api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/resume_template_renderer.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// InterviewPrepProScreen
//
// Spec §4 (Interview Prep — Pro):
//   - Full personalized study guide. 10-15 questions: behavioral +
//     role-specific + company-specific (web search).
//   - Personalized answer guides from resume.
//   - Tap-to-expand. Exportable and printable as PDF.
//   - Requires internet to generate; offline once saved.
//
// Rule §2: never delete user data — generating a new guide for the same
//          resume creates a fresh InterviewStudyGuide record rather than
//          overwriting; prior guides remain in studyGuideBox.
// ─────────────────────────────────────────────────────────────────────────────

class InterviewPrepProScreen extends ConsumerStatefulWidget {
  const InterviewPrepProScreen({super.key});

  @override
  ConsumerState<InterviewPrepProScreen> createState() =>
      _InterviewPrepProScreenState();
}

class _InterviewPrepProScreenState
    extends ConsumerState<InterviewPrepProScreen> {
  String? _resumeId;
  ResumeRenderData? _renderData;

  final _jdController = TextEditingController();
  bool _isGenerating = false;
  String? _errorMessage;

  InterviewStudyGuide? _activeGuide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _resumeId = args['resumeId'] as String?;
      final jobText = args['jobPostingText'] as String?;
      if (jobText != null && jobText.isNotEmpty) {
        _jdController.text = jobText;
      }
    }

    if (_resumeId != null && _renderData == null) {
      _renderData = ResumeRenderData.fromHive(_resumeId!);
      _loadMostRecentGuide();
    }
  }

  @override
  void dispose() {
    _jdController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Loading an existing guide (offline-available once generated)
  // ─────────────────────────────────────────────────────────────────────────

  void _loadMostRecentGuide() {
    if (_resumeId == null) return;
    final guides = HiveService.studyGuideBox.values
        .where((g) => g.resumeId == _resumeId)
        .toList()
      ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));

    if (guides.isNotEmpty && mounted) {
      setState(() => _activeGuide = guides.first);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Generation
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onGenerate() async {
    final jd = _jdController.text.trim();
    if (jd.isEmpty) {
      setState(() => _errorMessage =
          'Please paste the job posting to generate your study guide.');
      return;
    }

    final isOnline = ref.read(isOnlineProvider);
    if (!isOnline) {
      setState(() => _errorMessage = AppConstants.offlineBannerMessage);
      return;
    }

    if (_renderData == null) {
      setState(() => _errorMessage = 'Resume data not available.');
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      // Company/role extraction and question generation can run in parallel —
      // both only need the job posting text / resume data, independently.
      final results = await Future.wait([
        Phase3ApiService.extractCompanyAndRole(jobPostingText: jd),
        Phase3ApiService.generateProInterviewGuide(
          jobDescription: jd,
          resumeSummary: _renderData!.summary,
          resumeSkills: _renderData!.skills.map((s) => s.name).toList(),
          resumeExperience: _renderData!.experience
              .map((e) => '${e.title} at ${e.company}: ${e.bullets.join(' ')}')
              .join('\n'),
        ),
      ]);

      final companyRole = results[0] as Map<String, String>;
      final rawQuestions = results[1] as List<RawInterviewQuestion>;

      if (rawQuestions.isEmpty) {
        setState(() {
          _isGenerating = false;
          _errorMessage = 'Could not generate questions. Please try again.';
        });
        return;
      }

      final questions = rawQuestions
          .map((q) => InterviewQuestion(
                id: _uuid.v4(),
                category: _parseCategory(q.category),
                questionText: q.questionText,
                answerGuide: q.answerGuide ?? '',
              ))
          .where((q) => q.questionText.isNotEmpty)
          .toList();

      final guide = InterviewStudyGuide(
        id: _uuid.v4(),
        resumeId: _resumeId!,
        companyName: companyRole['company'] ?? '',
        roleTitle: companyRole['role'] ?? '',
        generatedAt: DateTime.now(),
        questions: questions,
      );

      // Rule §2 — additive, never overwrites a prior guide for this resume.
      await HiveService.studyGuideBox.put(guide.id, guide);

      if (mounted) {
        setState(() {
          _activeGuide = guide;
          _isGenerating = false;
        });
      }
    } on CloudflareApiException catch (e) {
      setState(() {
        _isGenerating = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _errorMessage = 'Generation failed. Please try again.';
      });
    }
  }

  QuestionCategoryEnum _parseCategory(String raw) {
    return switch (raw) {
      'behavioral' => QuestionCategoryEnum.behavioral,
      'roleSpecific' => QuestionCategoryEnum.roleSpecific,
      'companySpecific' => QuestionCategoryEnum.companySpecific,
      _ => QuestionCategoryEnum.roleSpecific,
    };
  }

  void _onGenerateNew() {
    setState(() {
      _activeGuide = null;
      _jdController.clear();
      _errorMessage = null;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PDF Export
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onExportPdf() async {
    final guide = _activeGuide;
    if (guide == null) return;

    final bytes = await _buildStudyGuidePdf(guide);
    final fileName =
        'Interview_Prep_${guide.companyName.isNotEmpty ? guide.companyName.replaceAll(' ', '_') : 'Guide'}.pdf';

    await Printing.sharePdf(bytes: bytes, filename: fileName);

    guide.exportedAt = DateTime.now();
    await guide.save();
    if (mounted) setState(() {});
  }

  Future<Uint8List> _buildStudyGuidePdf(InterviewStudyGuide guide) async {
    final doc = pw.Document(
      title: 'Interview Prep — ${guide.roleTitle}',
    );

    final regularFont = await PdfGoogleFonts.interRegular();
    final boldFont = await PdfGoogleFonts.interBold();
    final semiBoldFont = await PdfGoogleFonts.interSemiBold();

    const navy = PdfColor.fromInt(0xFF1A1A2E);
    const accent = PdfColor.fromInt(0xFF2C4A7C);
    const gray = PdfColor.fromInt(0xFF6B7280);
    const lightGray = PdfColor.fromInt(0xFFE5E7EB);

    pw.Widget categoryBadge(QuestionCategoryEnum category) {
      final label = switch (category) {
        QuestionCategoryEnum.behavioral => 'BEHAVIORAL',
        QuestionCategoryEnum.roleSpecific => 'ROLE-SPECIFIC',
        QuestionCategoryEnum.companySpecific => 'COMPANY-SPECIFIC',
      };
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: pw.BoxDecoration(
          color: accent,
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Text(label,
            style: pw.TextStyle(
                font: boldFont, fontSize: 7, color: PdfColors.white)),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 48),
        build: (context) => [
          pw.Text('Interview Preparation Guide',
              style: pw.TextStyle(font: boldFont, fontSize: 22, color: navy)),
          pw.SizedBox(height: 4),
          pw.Text(
            [guide.roleTitle, guide.companyName]
                .where((s) => s.isNotEmpty)
                .join(' at '),
            style:
                pw.TextStyle(font: semiBoldFont, fontSize: 13, color: accent),
          ),
          pw.SizedBox(height: 12),
          pw.Divider(color: lightGray, thickness: 0.8),
          pw.SizedBox(height: 16),
          for (final q in guide.questions) ...[
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 16),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: lightGray, width: 0.8),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  categoryBadge(q.category),
                  pw.SizedBox(height: 6),
                  pw.Text(q.questionText,
                      style: pw.TextStyle(
                          font: semiBoldFont, fontSize: 12, color: navy)),
                  if (q.answerGuide.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text('How to answer:',
                        style: pw.TextStyle(
                            font: semiBoldFont, fontSize: 9, color: accent)),
                    pw.SizedBox(height: 3),
                    pw.Text(q.answerGuide,
                        style: pw.TextStyle(
                            font: regularFont,
                            fontSize: 10,
                            color: gray,
                            lineSpacing: 2)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return doc.save();
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
        title: Text('Interview Prep',
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
          if (_activeGuide != null)
            IconButton(
              icon: const Icon(Icons.ios_share_outlined),
              tooltip: 'Export as PDF',
              onPressed: _onExportPdf,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (_activeGuide == null) ...[
            _JobPostingInput(
              controller: _jdController,
              isGenerating: _isGenerating,
              errorMessage: _errorMessage,
              isDark: isDark,
              onGenerate: _onGenerate,
            ),
          ] else ...[
            _GuideHeader(
              guide: _activeGuide!,
              isDark: isDark,
              onGenerateNew: _onGenerateNew,
            ),
            const SizedBox(height: 20),
            ..._buildQuestionSections(_activeGuide!, isDark),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildQuestionSections(InterviewStudyGuide guide, bool isDark) {
    final behavioral = guide.questions
        .where((q) => q.category == QuestionCategoryEnum.behavioral)
        .toList();
    final roleSpecific = guide.questions
        .where((q) => q.category == QuestionCategoryEnum.roleSpecific)
        .toList();
    final companySpecific = guide.questions
        .where((q) => q.category == QuestionCategoryEnum.companySpecific)
        .toList();

    final widgets = <Widget>[];

    if (companySpecific.isNotEmpty) {
      widgets.add(_QASectionHeader(
        number: '01',
        title: 'Company-Specific Questions',
        subtitle:
            'Researched from current information about ${guide.companyName.isNotEmpty ? guide.companyName : "the company"}.',
        isDark: isDark,
      ));
      widgets.add(const SizedBox(height: 12));
      widgets.addAll(companySpecific
          .map((q) => _ExpandableQuestionCard(question: q, isDark: isDark)));
      widgets.add(const SizedBox(height: 24));
    }

    if (roleSpecific.isNotEmpty) {
      widgets.add(_QASectionHeader(
        number: companySpecific.isNotEmpty ? '02' : '01',
        title: 'Role-Specific Questions',
        subtitle: 'Tailored to the responsibilities in this job posting.',
        isDark: isDark,
      ));
      widgets.add(const SizedBox(height: 12));
      widgets.addAll(roleSpecific
          .map((q) => _ExpandableQuestionCard(question: q, isDark: isDark)));
      widgets.add(const SizedBox(height: 24));
    }

    if (behavioral.isNotEmpty) {
      final n = (companySpecific.isNotEmpty ? 1 : 0) +
          (roleSpecific.isNotEmpty ? 1 : 0) +
          1;
      widgets.add(_QASectionHeader(
        number: n.toString().padLeft(2, '0'),
        title: 'Behavioral Questions',
        subtitle: 'Personalized using your resume — answer with STAR.',
        isDark: isDark,
      ));
      widgets.add(const SizedBox(height: 12));
      widgets.addAll(behavioral
          .map((q) => _ExpandableQuestionCard(question: q, isDark: isDark)));
    }

    return widgets;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Job Posting Input
// ─────────────────────────────────────────────────────────────────────────────

class _JobPostingInput extends StatelessWidget {
  const _JobPostingInput({
    required this.controller,
    required this.isGenerating,
    required this.errorMessage,
    required this.isDark,
    required this.onGenerate,
  });

  final TextEditingController controller;
  final bool isGenerating;
  final String? errorMessage;
  final bool isDark;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: accent),
              const SizedBox(width: 8),
              Text('Personalized Study Guide',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Paste the job posting. We\'ll research the company, generate 10-15 questions, '
            'and write personalized answer guides drawn from your resume.',
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: controller,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Paste the full job posting here…',
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(errorMessage!,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color:
                        isDark ? AppColors.errorDark : AppColors.errorLight)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isGenerating ? null : onGenerate,
              icon: isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 16),
              label: Text(isGenerating
                  ? 'Researching & generating…'
                  : 'Generate Study Guide'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Guide Header
// ─────────────────────────────────────────────────────────────────────────────

class _GuideHeader extends StatelessWidget {
  const _GuideHeader({
    required this.guide,
    required this.isDark,
    required this.onGenerateNew,
  });

  final InterviewStudyGuide guide;
  final bool isDark;
  final VoidCallback onGenerateNew;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guide.roleTitle.isNotEmpty ? guide.roleTitle : 'Study Guide',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (guide.companyName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(guide.companyName,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: accent,
                          fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 4),
                Text(
                  '${guide.questions.length} questions  ·  ${guide.exportedAt != null ? "Exported" : "Not yet exported"}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onGenerateNew,
            child: const Text('New Guide'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _QASectionHeader extends StatelessWidget {
  const _QASectionHeader({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.isDark,
  });
  final String number;
  final String title;
  final String subtitle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              color: accent, borderRadius: BorderRadius.circular(6)),
          alignment: Alignment.center,
          child: Text(number,
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable Question Card — Hive-backed (vs Basic's local _QAItem)
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandableQuestionCard extends StatefulWidget {
  const _ExpandableQuestionCard({required this.question, required this.isDark});
  final InterviewQuestion question;
  final bool isDark;

  @override
  State<_ExpandableQuestionCard> createState() =>
      _ExpandableQuestionCardState();
}

class _ExpandableQuestionCardState extends State<_ExpandableQuestionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final surface =
        widget.isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = widget.isDark ? AppColors.borderDark : AppColors.borderLight;
    final accent =
        widget.isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Semantics(
      label: widget.question.questionText,
      hint: _expanded ? 'Tap to collapse' : 'Tap to show the answer guide',
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 5, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.question.questionText,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(height: 1, color: border),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline,
                              size: 13, color: accent),
                          const SizedBox(width: 6),
                          Text('How to answer',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              )),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.question.answerGuide.isNotEmpty
                            ? widget.question.answerGuide
                            : 'No answer guide available for this question.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.6,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
