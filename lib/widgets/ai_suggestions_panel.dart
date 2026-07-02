import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/connectivity_provider.dart';
import '../services/cloudflare_worker_service.dart';
import '../services/phase3_api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AiSuggestionsPanel
//
// Spec §4 (AI Suggestions):
//   Per-section AI panel. Current text shown, 2-3 rewrite options offered
//   via Claude API. User taps to accept. Requires internet. (Pro)
//
// Rule §3: User always reviews before applying — no auto-overwrite.
// This is a modal bottom sheet, opened from Preview & Edit when a Pro user
// taps the "AI Suggest" affordance on an editable field.
// ─────────────────────────────────────────────────────────────────────────────

enum AiSuggestionMode { bulletRewrite, summaryGenerate, skillGap }

/// Shows the AI Suggestions panel as a modal bottom sheet.
/// Returns the accepted replacement text, or null if dismissed without accepting.
Future<String?> showAiSuggestionsPanel({
  required BuildContext context,
  required AiSuggestionMode mode,
  required String currentText,
  String? jobTitle,
  String? jobDescription,
  List<String>? topSkills,
  ResumeRenderData? resumeData,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _AiSuggestionsSheet(
      mode: mode,
      currentText: currentText,
      jobTitle: jobTitle,
      jobDescription: jobDescription,
      topSkills: topSkills,
      resumeData: resumeData,
    ),
  );
}

class _AiSuggestionsSheet extends ConsumerStatefulWidget {
  const _AiSuggestionsSheet({
    required this.mode,
    required this.currentText,
    this.jobTitle,
    this.jobDescription,
    this.topSkills,
    this.resumeData,
  });

  final AiSuggestionMode mode;
  final String currentText;
  final String? jobTitle;
  final String? jobDescription;
  final List<String>? topSkills;
  final ResumeRenderData? resumeData;

  @override
  ConsumerState<_AiSuggestionsSheet> createState() =>
      _AiSuggestionsSheetState();
}

class _AiSuggestionsSheetState extends ConsumerState<_AiSuggestionsSheet> {
  bool _isLoading = false;
  bool _hasGenerated = false;
  String? _errorMessage;
  List<String> _alternatives = [];
  SkillGapResult? _skillGapResult;
  int? _selectedIndex;

  final _jdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.jobDescription != null) {
      _jdController.text = widget.jobDescription!;
    }
  }

  @override
  void dispose() {
    _jdController.dispose();
    super.dispose();
  }

  Future<void> _onGenerate() async {
    final isOnline = ref.read(isOnlineProvider);
    if (!isOnline) {
      setState(() => _errorMessage =
          'Internet connection required to generate AI suggestions.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      switch (widget.mode) {
        case AiSuggestionMode.bulletRewrite:
          final results = await Phase3ApiService.rewriteBullet(
            currentBullet: widget.currentText,
            jobTitle: widget.jobTitle ?? '',
            targetJobDescription: widget.jobDescription,
          );
          setState(() {
            _alternatives = results;
            _hasGenerated = true;
            _isLoading = false;
          });

        case AiSuggestionMode.summaryGenerate:
          final results = await Phase3ApiService.generateSummaryOptions(
            targetRole: widget.jobTitle ?? '',
            topSkills: widget.topSkills ?? [],
            keyAchievement: widget.currentText,
          );
          setState(() {
            _alternatives = results;
            _hasGenerated = true;
            _isLoading = false;
          });

        case AiSuggestionMode.skillGap:
          final jd = _jdController.text.trim();
          if (jd.isEmpty) {
            setState(() {
              _isLoading = false;
              _errorMessage =
                  'Please provide a job description to compare against.';
            });
            return;
          }
          if (widget.resumeData == null) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Resume data not available.';
            });
            return;
          }
          final result = await Phase3ApiService.analyzeSkillGap(
            resumeData: widget.resumeData!,
            jobDescription: jd,
          );
          setState(() {
            _skillGapResult = result;
            _hasGenerated = true;
            _isLoading = false;
          });
      }
    } on CloudflareApiException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Generation failed. Please try again.';
      });
    }
  }

  void _onAccept() {
    if (_selectedIndex == null || _selectedIndex! >= _alternatives.length) {
      return;
    }
    Navigator.pop(context, _alternatives[_selectedIndex!]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
            child: Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 18,
                    color: isDark
                        ? AppColors.aiIndicatorDark
                        : AppColors.aiIndicator),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _headerTitle,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                if (widget.mode != AiSuggestionMode.skillGap) ...[
                  Text('Current',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      )),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.backgroundDark
                          : AppColors.backgroundLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.borderLight),
                    ),
                    child: Text(
                      widget.currentText.isNotEmpty
                          ? widget.currentText
                          : '(empty)',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (widget.mode == AiSuggestionMode.skillGap &&
                    !_hasGenerated) ...[
                  Text('Job description',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      )),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _jdController,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText:
                          'Paste the job description to compare your skills against…',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!_hasGenerated) ...[
                  if (_errorMessage != null) ...[
                    Text(_errorMessage!,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.errorDark
                                : AppColors.errorLight)),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _onGenerate,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome, size: 16),
                      label: Text(
                          _isLoading ? 'Generating…' : _generateButtonLabel),
                    ),
                  ),
                ],
                if (_hasGenerated &&
                    widget.mode != AiSuggestionMode.skillGap) ...[
                  if (_alternatives.isEmpty)
                    Text(
                      'No alternatives could be generated. Please try again.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else ...[
                    Text('Choose a version',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          letterSpacing: 0.4,
                        )),
                    const SizedBox(height: 8),
                    ..._alternatives.asMap().entries.map(
                          (entry) => _AlternativeCard(
                            text: entry.value,
                            index: entry.key,
                            isSelected: _selectedIndex == entry.key,
                            isDark: isDark,
                            onTap: () =>
                                setState(() => _selectedIndex = entry.key),
                          ),
                        ),
                  ],
                ],
                if (_hasGenerated &&
                    widget.mode == AiSuggestionMode.skillGap &&
                    _skillGapResult != null)
                  _SkillGapResults(result: _skillGapResult!, isDark: isDark),
              ],
            ),
          ),
          if (_hasGenerated && widget.mode != AiSuggestionMode.skillGap)
            Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                border: Border(
                    top: BorderSide(
                        color: isDark
                            ? AppColors.borderDark
                            : AppColors.borderLight)),
              ),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(() {
                              _hasGenerated = false;
                              _alternatives = [];
                              _selectedIndex = null;
                            }),
                    child: const Text('Regenerate'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedIndex != null ? _onAccept : null,
                      child: const Text('Use This Version'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String get _headerTitle {
    return switch (widget.mode) {
      AiSuggestionMode.bulletRewrite => 'Rewrite Bullet',
      AiSuggestionMode.summaryGenerate => 'Generate Summary',
      AiSuggestionMode.skillGap => 'Skill Gap Analysis',
    };
  }

  String get _generateButtonLabel {
    return switch (widget.mode) {
      AiSuggestionMode.bulletRewrite => 'Generate 3 Alternatives',
      AiSuggestionMode.summaryGenerate => 'Generate 3 Summaries',
      AiSuggestionMode.skillGap => 'Analyze Skills',
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Alternative Card
// ─────────────────────────────────────────────────────────────────────────────

class _AlternativeCard extends StatelessWidget {
  const _AlternativeCard({
    required this.text,
    required this.index,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final String text;
  final int index;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Semantics(
      label: 'Option ${index + 1}: $text${isSelected ? ', selected' : ''}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? accent.withValues(alpha: 0.08) : surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? accent : border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? accent : Colors.transparent,
                  border: Border.all(
                      color: isSelected
                          ? accent
                          : Theme.of(context).colorScheme.outlineVariant),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skill Gap Results
// ─────────────────────────────────────────────────────────────────────────────

class _SkillGapResults extends StatelessWidget {
  const _SkillGapResults({required this.result, required this.isDark});
  final SkillGapResult result;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result.matchedSkills.isNotEmpty)
          _GapSection(
            title: 'Already Matched',
            items: result.matchedSkills,
            icon: Icons.check_circle_outline,
            color: isDark ? AppColors.successDark : AppColors.successLight,
            isDark: isDark,
          ),
        if (result.missingSkills.isNotEmpty) ...[
          const SizedBox(height: 12),
          _GapSection(
            title: 'Likely Have, Not Listed',
            subtitle:
                'Evidence found in your experience — consider adding these',
            items: result.missingSkills,
            icon: Icons.add_circle_outline,
            color: isDark ? AppColors.warningDark : AppColors.warningLight,
            isDark: isDark,
          ),
        ],
        if (result.suggestedAdditions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _GapSection(
            title: 'Skill Gaps',
            subtitle: 'Required by the job, not found in your resume',
            items: result.suggestedAdditions,
            icon: Icons.error_outline,
            color: isDark ? AppColors.errorDark : AppColors.errorLight,
            isDark: isDark,
          ),
        ],
        if (result.transferableSkills.isNotEmpty) ...[
          const SizedBox(height: 12),
          _GapSection(
            title: 'Worth Highlighting',
            subtitle: 'Relevant skills you have that aren\'t in the JD',
            items: result.transferableSkills,
            icon: Icons.star_outline,
            color: isDark ? AppColors.accentDark : AppColors.accentLightColor,
            isDark: isDark,
          ),
        ],
      ],
    );
  }
}

class _GapSection extends StatelessWidget {
  const _GapSection({
    required this.title,
    this.subtitle,
    required this.items,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  final String title;
  final String? subtitle;
  final List<String> items;
  final IconData icon;
  final Color color;
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
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items
                .map((item) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Text(item,
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
