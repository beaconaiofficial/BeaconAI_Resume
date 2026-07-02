import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';
import '../providers/connectivity_provider.dart';
import '../services/cloudflare_worker_service.dart';
import '../services/phase2_api_service.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// InterviewPrepBasicScreen
//
// Spec §4 / §12 (Basic Tier — Semi-Dynamic Guide):
//   - Universal questions (same 12 as Free tier) +
//     5-8 role-specific questions extracted by Claude from the job posting.
//   - No web search. No resume content used.
//   - Q&A layout with expand/collapse.
//   - Not exportable at this tier.
//   - Requires internet to generate; viewable offline once generated.
// ─────────────────────────────────────────────────────────────────────────────

class InterviewPrepBasicScreen extends ConsumerStatefulWidget {
  const InterviewPrepBasicScreen({super.key});

  @override
  ConsumerState<InterviewPrepBasicScreen> createState() =>
      _InterviewPrepBasicScreenState();
}

class _InterviewPrepBasicScreenState
    extends ConsumerState<InterviewPrepBasicScreen> {
  final _jdController = TextEditingController();
  bool _isGenerating = false;
  bool _hasGenerated = false;
  List<_QAItem> _roleSpecificQA = [];
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      // If a job posting was pre-provided, auto-fill
      final jobText = args['jobPostingText'] as String?;
      if (jobText != null && jobText.isNotEmpty) {
        _jdController.text = jobText;
      }
    }
  }

  @override
  void dispose() {
    _jdController.dispose();
    super.dispose();
  }

  Future<void> _onGenerate() async {
    final jd = _jdController.text.trim();
    if (jd.isEmpty) {
      setState(() => _errorMessage =
          'Please paste the job posting to generate role-specific questions.');
      return;
    }

    final isOnline = ref.read(isOnlineProvider);
    if (!isOnline) {
      setState(() => _errorMessage = AppConstants.offlineBannerMessage);
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final questions = await Phase2ApiService.generateBasicInterviewPrep(jd);
      setState(() {
        _roleSpecificQA = questions
            .map((q) => _QAItem(question: q.question, tips: q.tips))
            .toList();
        _hasGenerated = true;
        _isGenerating = false;
      });
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
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // Job posting input (shown when not yet generated)
          if (!_hasGenerated) ...[
            _JobPostingInput(
              controller: _jdController,
              isGenerating: _isGenerating,
              errorMessage: _errorMessage,
              isDark: isDark,
              onGenerate: _onGenerate,
            ),
            const SizedBox(height: 24),
          ] else ...[
            // Role context chip
            _RoleContextChip(
              roleText: _jdController.text.length > 100
                  ? '${_jdController.text.substring(0, 100)}…'
                  : _jdController.text,
              isDark: isDark,
              onReset: () => setState(() {
                _hasGenerated = false;
                _roleSpecificQA = [];
              }),
            ),
            const SizedBox(height: 20),
          ],

          // Role-specific questions (when generated)
          if (_hasGenerated && _roleSpecificQA.isNotEmpty) ...[
            _QASectionHeader(
              number: '01',
              title: 'Role-Specific Questions',
              subtitle:
                  'Generated from the job posting. ${_roleSpecificQA.length} questions.',
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            ..._roleSpecificQA.map(
              (q) => _ExpandableQACard(item: q, isDark: isDark),
            ),
            const SizedBox(height: 24),
          ],

          // Universal behavioral questions (always shown)
          _QASectionHeader(
            number: _hasGenerated ? '02' : '01',
            title: 'Universal Behavioral Questions',
            subtitle: '12 questions that appear in almost every interview.',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          ..._universalQuestions.map(
            (q) => _ExpandableQACard(item: q, isDark: isDark),
          ),

          // Upgrade nudge for Pro
          const SizedBox(height: 24),
          _ProUpgradeNudge(isDark: isDark),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Universal questions (same content as Free tier)
// ─────────────────────────────────────────────────────────────────────────────

class _QAItem {
  const _QAItem({required this.question, required this.tips});
  final String question;
  final String tips;
}

const List<_QAItem> _universalQuestions = [
  _QAItem(
    question: 'Tell me about yourself.',
    tips:
        'Keep it to 2 minutes. Lead with your current role, highlight 1-2 relevant accomplishments, then connect to why you\'re excited about this specific role.',
  ),
  _QAItem(
    question: 'What is your greatest strength?',
    tips:
        'Pick one strength directly relevant to the job. Back it up with a specific, quantified example. "I reduced onboarding time by 30%" beats "I\'m a fast learner."',
  ),
  _QAItem(
    question: 'What is your greatest weakness?',
    tips:
        'Choose a real weakness. Show self-awareness and describe the concrete steps you\'ve taken to improve. Hiring managers are evaluating whether you can identify and address gaps.',
  ),
  _QAItem(
    question: 'Describe a challenge you overcame.',
    tips:
        'STAR method: Situation → Task → Action → Result. Pick a challenge where your individual contribution made a clear, measurable difference.',
  ),
  _QAItem(
    question: 'Tell me about a time you worked in a team.',
    tips:
        'Highlight collaboration, communication, and your specific role. Address any conflict that arose and how it was resolved professionally.',
  ),
  _QAItem(
    question: 'Why do you want to leave your current job?',
    tips:
        'Stay positive — never criticize your current employer. Frame around growth: seeking new challenges, expanded scope, or skills this role offers.',
  ),
  _QAItem(
    question: 'Where do you see yourself in 5 years?',
    tips:
        'Show ambition balanced with realism. Align your answer with what this role can realistically offer. Hiring managers want to see long-term fit.',
  ),
  _QAItem(
    question: 'Describe a time you showed leadership.',
    tips:
        'Leadership doesn\'t require a title. A time you drove a project, mentored a colleague, or stepped up during a crisis all qualify. Quantify the impact.',
  ),
  _QAItem(
    question: 'How do you handle stress or pressure?',
    tips:
        'Give a concrete example of a high-pressure situation you navigated successfully. Mention specific coping strategies and the outcome.',
  ),
  _QAItem(
    question: 'What motivates you?',
    tips:
        'Be honest and specific. Connect your motivations to what this role actually offers. Vague answers say nothing — show what gets you out of bed.',
  ),
  _QAItem(
    question: 'Why should we hire you?',
    tips:
        'Summarize your top 3 qualifications that match the job. Be direct and confident. Connect your specific experience to their specific needs.',
  ),
  _QAItem(
    question: 'Do you have any questions for us?',
    tips:
        'Always have 3-4 prepared. Strong questions: What does success look like in the first 90 days? What\'s the biggest challenge the team is facing? How would you describe the culture?',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: accent),
              const SizedBox(width: 8),
              Text(
                'Generate role-specific questions',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Paste the job posting and AI will generate 5-8 questions specific to this role.',
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: controller,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Paste job description here…',
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(errorMessage!,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color:
                        isDark ? AppColors.errorDark : AppColors.errorLight)),
          ],
          const SizedBox(height: 12),
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
                  ? 'Generating questions…'
                  : 'Generate Questions'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleContextChip extends StatelessWidget {
  const _RoleContextChip({
    required this.roleText,
    required this.isDark,
    required this.onReset,
  });
  final String roleText;
  final bool isDark;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Role-specific questions generated',
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w500, color: accent),
            ),
          ),
          TextButton(
            onPressed: onReset,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text('Change',
                style: GoogleFonts.inter(fontSize: 12, color: accent)),
          ),
        ],
      ),
    );
  }
}

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

class _ExpandableQACard extends StatefulWidget {
  const _ExpandableQACard({required this.item, required this.isDark});
  final _QAItem item;
  final bool isDark;

  @override
  State<_ExpandableQACard> createState() => _ExpandableQACardState();
}

class _ExpandableQACardState extends State<_ExpandableQACard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final surface =
        widget.isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = widget.isDark ? AppColors.borderDark : AppColors.borderLight;
    final accent =
        widget.isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Semantics(
      label: widget.item.question,
      hint: _expanded ? 'Tap to collapse' : 'Tap to show tips',
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
                        widget.item.question,
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
                        widget.item.tips,
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

class _ProUpgradeNudge extends StatelessWidget {
  const _ProUpgradeNudge({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined, size: 16, color: accent),
              const SizedBox(width: 8),
              Text('Want a personalized study guide?',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Upgrade to Pro for a full guide with company-specific questions, '
            'personalized answer guides drawn from your resume, and PDF export.',
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.55,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () =>
                Navigator.pushNamed(context, AppConstants.routePaywall),
            child: const Text('Upgrade to Pro'),
          ),
        ],
      ),
    );
  }
}
