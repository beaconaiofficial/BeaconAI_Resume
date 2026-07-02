import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';
import '../providers/connectivity_provider.dart';
import '../services/hive_service.dart';
import '../services/cloudflare_worker_service.dart';
import '../services/phase2_api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AtsAnalyzerScreen
//
// Spec §4 (ATS Analyzer):
//   - Paste job description field.
//   - Keyword match grid.
//   - Score breakdown.
//   - Missing keyword suggestions.
//   - Requires internet. Basic+.
// ─────────────────────────────────────────────────────────────────────────────

class AtsAnalyzerScreen extends ConsumerStatefulWidget {
  const AtsAnalyzerScreen({super.key});

  @override
  ConsumerState<AtsAnalyzerScreen> createState() => _AtsAnalyzerScreenState();
}

class _AtsAnalyzerScreenState extends ConsumerState<AtsAnalyzerScreen> {
  String? _resumeId;
  final _jdController = TextEditingController();
  bool _isAnalyzing = false;
  AtsAnalysis? _analysis;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _resumeId = args['resumeId'] as String?;
    }
  }

  @override
  void dispose() {
    _jdController.dispose();
    super.dispose();
  }

  Future<void> _onAnalyze() async {
    final jd = _jdController.text.trim();
    if (jd.isEmpty) {
      setState(
          () => _errorMessage = 'Please paste a job description to analyze.');
      return;
    }

    final isOnline = ref.read(isOnlineProvider);
    if (!isOnline) {
      setState(() => _errorMessage = AppConstants.offlineBannerMessage);
      return;
    }

    final effectiveResumeId = _resumeId ??
        HiveService.resumeBox.values
            .where((r) => r.isMaster && !r.isArchived)
            .firstOrNull
            ?.id;

    if (effectiveResumeId == null) {
      setState(() => _errorMessage =
          'No resume found. Complete your master resume first.');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _analysis = null;
    });

    try {
      final resumeData = ResumeRenderData.fromHive(effectiveResumeId);
      final analysis = await Phase2ApiService.analyzeKeywords(
        resumeData: resumeData,
        jobDescription: jd,
      );
      setState(() {
        _analysis = analysis;
        _isAnalyzing = false;
      });
    } on CloudflareApiException catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _errorMessage = 'Analysis failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('ATS Keyword Scanner',
            style: GoogleFonts.playfairDisplay(
                fontSize: 20, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Input section
          _InputCard(
            controller: _jdController,
            isAnalyzing: _isAnalyzing,
            errorMessage: _errorMessage,
            isDark: isDark,
            onAnalyze: _onAnalyze,
          ),

          // Results section
          if (_analysis != null) ...[
            const SizedBox(height: 20),
            _ScoreCard(analysis: _analysis!, isDark: isDark),
            const SizedBox(height: 16),
            if (_analysis!.matchedKeywords.isNotEmpty) ...[
              _KeywordSection(
                title: 'Matched Keywords',
                keywords: _analysis!.matchedKeywords,
                color: isDark ? AppColors.successDark : AppColors.successLight,
                icon: Icons.check_circle_outline,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
            ],
            if (_analysis!.partialMatches.isNotEmpty) ...[
              _KeywordSection(
                title: 'Partial Matches',
                keywords: _analysis!.partialMatches,
                color: isDark ? AppColors.warningDark : AppColors.warningLight,
                icon: Icons.remove_circle_outline,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
            ],
            if (_analysis!.missingKeywords.isNotEmpty) ...[
              _KeywordSection(
                title: 'Missing Keywords',
                keywords: _analysis!.missingKeywords,
                color: isDark ? AppColors.errorDark : AppColors.errorLight,
                icon: Icons.cancel_outlined,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
            ],
            if (_analysis!.suggestions.isNotEmpty) ...[
              _SuggestionsCard(
                  suggestions: _analysis!.suggestions, isDark: isDark),
            ],
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.controller,
    required this.isAnalyzing,
    required this.errorMessage,
    required this.isDark,
    required this.onAnalyze,
  });

  final TextEditingController controller;
  final bool isAnalyzing;
  final String? errorMessage;
  final bool isDark;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paste the job description',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText:
                'Paste the full job description here to compare against your resume…',
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(errorMessage!,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark ? AppColors.errorDark : AppColors.errorLight)),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isAnalyzing ? null : onAnalyze,
            icon: isAnalyzing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search, size: 18),
            label: Text(isAnalyzing ? 'Analyzing…' : 'Scan for Keywords'),
          ),
        ),
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.analysis, required this.isDark});
  final AtsAnalysis analysis;
  final bool isDark;

  Color get _scoreColor {
    if (analysis.score >= 70) {
      return isDark ? AppColors.successDark : AppColors.successLight;
    }
    if (analysis.score >= 40) {
      return isDark ? AppColors.warningDark : AppColors.warningLight;
    }
    return isDark ? AppColors.errorDark : AppColors.errorLight;
  }

  String get _scoreLabel {
    if (analysis.score >= 70) return 'Strong Match';
    if (analysis.score >= 40) return 'Partial Match';
    return 'Needs Work';
  }

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _scoreColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Score ring
          Semantics(
            label:
                'ATS keyword match score: ${analysis.score} out of 100, $_scoreLabel',
            child: SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: analysis.score / 100,
                    strokeWidth: 6,
                    backgroundColor:
                        Theme.of(context).colorScheme.outlineVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(_scoreColor),
                  ),
                  Text(
                    '${analysis.score}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _scoreColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _scoreLabel,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _scoreColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${analysis.matchedKeywords.length} keywords matched · '
                  '${analysis.missingKeywords.length} missing',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: analysis.score / 100,
                    minHeight: 6,
                    backgroundColor:
                        Theme.of(context).colorScheme.outlineVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(_scoreColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeywordSection extends StatelessWidget {
  const _KeywordSection({
    required this.title,
    required this.keywords,
    required this.color,
    required this.icon,
    required this.isDark,
  });

  final String title;
  final List<String> keywords;
  final Color color;
  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  )),
              const SizedBox(width: 6),
              Text('(${keywords.length})',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: keywords
                .map((kw) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Text(kw,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface,
                          )),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SuggestionsCard extends StatelessWidget {
  const _SuggestionsCard({required this.suggestions, required this.isDark});
  final List<String> suggestions;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 14, color: accent),
              const SizedBox(width: 6),
              Text('Improvement Suggestions',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          ...suggestions.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.only(top: 1, right: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${entry.key + 1}',
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accent),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.5,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
