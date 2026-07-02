import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// InterviewTipsFreeScreen
//
// Spec §4 / §12 (Free Tier — Static Interview Tips Guide):
//  - Hardcoded at build time — no API call, no personalization.
//  - Q&A layout: question + tips on how to think about and prepare an answer.
//  - Section 1: 12 Universal Behavioral Questions.
//  - Section 2: How to Prepare for Job-Specific Questions.
//  - Section 3: 3 Example Job Categories with sample Q&A.
//  - Works offline — no internet required.
// ─────────────────────────────────────────────────────────────────────────────

class InterviewTipsFreeScreen extends StatelessWidget {
  const InterviewTipsFreeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'Interview Tips',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // Intro card
          _IntroCard(isDark: isDark),
          const SizedBox(height: 24),

          // ── Section 1: Universal Behavioral Questions ─────────────────────
          _SectionHeader(
            number: '01',
            title: 'Universal Behavioral Questions',
            subtitle: 'These 12 questions appear in almost every interview. '
                'Prepare a specific example for each using the STAR method.',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          ..._behavioralQuestions
              .map((q) => _QuestionCard(item: q, isDark: isDark)),

          const SizedBox(height: 28),

          // ── Section 2: How to Prepare for Job-Specific Questions ──────────
          _SectionHeader(
            number: '02',
            title: 'Preparing for Job-Specific Questions',
            subtitle:
                'Every role has unique requirements. Use these strategies '
                'to anticipate questions before you walk in.',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _PrepTipsCard(isDark: isDark),

          const SizedBox(height: 28),

          // ── Section 3: Example Job Categories ────────────────────────────
          _SectionHeader(
            number: '03',
            title: 'Questions by Job Category',
            subtitle: 'Sample questions tailored to common job types. '
                'Use these to practice role-specific answers.',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          ..._jobCategories
              .map((cat) => _JobCategoryCard(category: cat, isDark: isDark)),

          // Upgrade nudge for Basic/Pro prep
          const SizedBox(height: 28),
          _UpgradeNudge(isDark: isDark),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Static content data
// ─────────────────────────────────────────────────────────────────────────────

class _QA {
  const _QA({required this.question, required this.tips});
  final String question;
  final String tips;
}

class _JobCategory {
  const _JobCategory(
      {required this.name, required this.icon, required this.questions});
  final String name;
  final IconData icon;
  final List<_QA> questions;
}

const List<_QA> _behavioralQuestions = [
  _QA(
    question: 'Tell me about yourself.',
    tips:
        'Keep it to 2 minutes. Lead with your current role and key experience, '
        'highlight 1–2 relevant accomplishments, then connect to why you\'re '
        'excited about this specific role. Avoid personal history — stay professional.',
  ),
  _QA(
    question: 'What is your greatest strength?',
    tips: 'Pick one strength that\'s directly relevant to the job description. '
        'Back it up with a specific, quantified example from your work history. '
        '"I\'m a fast learner" is weak — "I reduced onboarding time by 30% by '
        'building a training guide" is strong.',
  ),
  _QA(
    question: 'What is your greatest weakness?',
    tips:
        'Choose a real weakness, not a disguised strength. Show self-awareness '
        'and — critically — describe the concrete steps you\'ve taken to improve. '
        'Hiring managers are evaluating whether you can identify and address gaps.',
  ),
  _QA(
    question: 'Describe a challenge you overcame.',
    tips:
        'Use the STAR method: Situation (brief context), Task (your responsibility), '
        'Action (what YOU specifically did — not "we"), Result (measurable outcome). '
        'Pick a challenge where your individual contribution made a clear difference.',
  ),
  _QA(
    question: 'Tell me about a time you worked in a team.',
    tips:
        'Highlight collaboration, communication, and your specific role in the team\'s '
        'success. Address any conflict that arose and how it was resolved. '
        'Interviewers want to know you can work with others without drama.',
  ),
  _QA(
    question: 'Why do you want to leave your current job?',
    tips:
        'Stay positive — never criticize your current employer. Frame your answer '
        'around growth: you\'re seeking new challenges, expanded scope, or skills '
        'this role offers. Tie it back to why THIS company specifically appeals to you.',
  ),
  _QA(
    question: 'Where do you see yourself in 5 years?',
    tips:
        'Show ambition balanced with realism. Align your answer with what the role '
        'can realistically offer — hiring managers want to see that you\'ll grow '
        'with the company, not jump ship in 12 months. Ask what growth looks like '
        'here if you\'re unsure.',
  ),
  _QA(
    question: 'Describe a time you showed leadership.',
    tips:
        'Leadership doesn\'t require a title. Think of a time you drove a project, '
        'mentored a colleague, or stepped up during a crisis. Use STAR, quantify the '
        'impact, and make your individual contribution unmistakably clear.',
  ),
  _QA(
    question: 'How do you handle stress or pressure?',
    tips: 'Give a concrete example of a high-pressure situation you navigated '
        'successfully. Mention specific coping strategies (prioritization, '
        'breaking tasks into pieces, communication). Avoid "I thrive under pressure" '
        'without proof — show, don\'t tell.',
  ),
  _QA(
    question: 'What motivates you?',
    tips:
        'Be honest and specific. Connect your motivations to what this role actually '
        'offers — problem-solving, impact, learning, building things. Vague answers '
        'like "I\'m motivated by success" say nothing. Tell them what gets you out '
        'of bed in the morning.',
  ),
  _QA(
    question: 'Why should we hire you?',
    tips: 'Summarize your top 3 qualifications that match the job description. '
        'Be direct and confident — this is your closing argument. Connect your '
        'specific experience to their specific needs. End with genuine enthusiasm '
        'for the role.',
  ),
  _QA(
    question: 'Do you have any questions for us?',
    tips:
        'Always have 3–4 prepared. Strong questions: What does success look like '
        'in the first 90 days? What\'s the biggest challenge the team is facing? '
        'How would you describe the team culture? Avoid asking about salary or '
        'benefits in a first interview — wait until they bring it up.',
  ),
];

const List<_JobCategory> _jobCategories = [
  _JobCategory(
    name: 'Customer Service',
    icon: Icons.support_agent_outlined,
    questions: [
      _QA(
        question: 'What would you do if a customer was angry or upset?',
        tips:
            'Lead with empathy: acknowledge their frustration before explaining '
            'or problem-solving. Describe your de-escalation process step by step. '
            'End with a real example where you turned a difficult situation around.',
      ),
      _QA(
        question: 'How do you handle multiple customers with competing needs?',
        tips:
            'Triage by urgency and impact. Explain how you communicate wait times '
            'honestly. Interviewers want to see you can stay calm, set expectations, '
            'and resolve issues without letting anyone feel ignored.',
      ),
      _QA(
        question: 'Describe a time you went above and beyond for a customer.',
        tips:
            'Pick an example where you did more than the minimum — then quantify '
            'the result (customer retention, positive review, repeat business). '
            'This shows initiative beyond just following the script.',
      ),
      _QA(
        question:
            'How do you handle a situation where company policy conflicts with what the customer wants?',
        tips:
            'Show that you can enforce policy while still making the customer feel '
            'heard and respected. Describe how you explain the "why" behind a policy '
            'and offer alternative solutions within your authority.',
      ),
    ],
  ),
  _JobCategory(
    name: 'Administrative / Office',
    icon: Icons.business_center_outlined,
    questions: [
      _QA(
        question: 'How do you prioritize competing deadlines?',
        tips:
            'Walk them through your actual system: how you assess urgency vs. '
            'importance, how you communicate when you\'re overloaded, and how '
            'you handle last-minute requests. Give a specific example.',
      ),
      _QA(
        question: 'What tools and software are you proficient in?',
        tips:
            'Match your answer to the job description\'s requirements. Go beyond '
            'just listing tools — briefly describe how you use them and any '
            'efficiencies you\'ve created. Specific versions or certifications add weight.',
      ),
      _QA(
        question: 'How do you handle confidential information?',
        tips: 'Show you understand the gravity of data privacy. Describe your '
            'protocols: secure storage, need-to-know access, never discussing '
            'sensitive matters in open areas. Reference any relevant experience '
            'with compliance or secure systems.',
      ),
      _QA(
        question: 'Describe a time you improved an administrative process.',
        tips:
            'Quantify the improvement — time saved, error rate reduced, cost cut. '
            'Show that you proactively identified the problem, proposed the solution, '
            'and measured the result. Initiative stands out in administrative roles.',
      ),
    ],
  ),
  _JobCategory(
    name: 'Warehouse / Logistics',
    icon: Icons.local_shipping_outlined,
    questions: [
      _QA(
        question:
            'Describe your experience with inventory or shipping systems.',
        tips:
            'Name the specific software or systems you\'ve used (WMS, SAP, Oracle, '
            'RF scanners, etc.). Describe what you did with them and any accuracy '
            'or efficiency improvements you contributed to.',
      ),
      _QA(
        question:
            'How do you ensure accuracy when picking, packing, or shipping orders?',
        tips:
            'Walk through your verification process step by step. Mention any '
            'double-check habits, scan verification, or quality control steps you '
            'use consistently. Error rates and accuracy percentages are gold here.',
      ),
      _QA(
        question:
            'How do you handle physical demands of the job over a full shift?',
        tips:
            'Be honest about your physical capacity and mention any safety practices '
            'you follow (proper lifting technique, using equipment, taking required '
            'breaks). Emphasize reliability and attendance.',
      ),
      _QA(
        question:
            'Tell me about a time there was a problem with an order or shipment.',
        tips:
            'Use STAR. Focus on how quickly you identified the issue, who you '
            'communicated with, and how the problem was resolved with minimal impact '
            'to the customer or operation. Own any mistakes and show what you learned.',
      ),
    ],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            isDark ? AppColors.accentLightTintDark : AppColors.accentLightTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.quiz_outlined, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                'Interview Preparation Guide',
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
            'Prepare your answers using the STAR method: '
            'Situation → Task → Action → Result. '
            'Specific examples with measurable outcomes always outperform generic answers.',
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.55,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          // STAR legend
          Row(
            children: [
              _StarChip(letter: 'S', label: 'Situation', isDark: isDark),
              const SizedBox(width: 6),
              _StarChip(letter: 'T', label: 'Task', isDark: isDark),
              const SizedBox(width: 6),
              _StarChip(letter: 'A', label: 'Action', isDark: isDark),
              const SizedBox(width: 6),
              _StarChip(letter: 'R', label: 'Result', isDark: isDark),
            ],
          ),
        ],
      ),
    );
  }
}

class _StarChip extends StatelessWidget {
  const _StarChip({
    required this.letter,
    required this.label,
    required this.isDark,
  });
  final String letter;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              letter,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
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
        // Number badge
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({required this.item, required this.isDark});
  final _QA item;
  final bool isDark;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
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
      hint: _expanded ? 'Tap to collapse' : 'Tap to expand answer tips',
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
              // Question row
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: accent),
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
                    const SizedBox(width: 8),
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

              // Answer tips — expandable
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
                          Text(
                            'How to answer',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
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

class _PrepTipsCard extends StatelessWidget {
  const _PrepTipsCard({required this.isDark});
  final bool isDark;

  static const List<_PrepTip> _tips = [
    _PrepTip(
      title: 'Read the job description three times',
      body:
          'First for the big picture, second to identify every required skill '
          'and qualification, third to note the exact language used. Mirror that '
          'language in your answers — ATS parsers aren\'t the only ones listening.',
    ),
    _PrepTip(
      title: 'Research the company before you walk in',
      body: 'Know their mission, recent news, key products or services, and '
          'competitors. Reference this knowledge in your answers and questions. '
          'Interviewers notice when candidates have done their homework.',
    ),
    _PrepTip(
      title: 'Prepare 5–6 STAR stories you can adapt',
      body:
          'Pick versatile stories from your experience that demonstrate different '
          'skills: leadership, problem-solving, collaboration, communication, '
          'technical skill. Most behavioral questions can be answered with the '
          'same 5–6 stories reframed for the question.',
    ),
    _PrepTip(
      title: 'Practice out loud, not just in your head',
      body:
          'Rehearsing mentally feels complete but leaves gaps. Say your answers '
          'out loud — record yourself or practice with someone. Timing, filler words, '
          'and clarity issues only show up when you hear yourself speak.',
    ),
    _PrepTip(
      title: 'Quantify everything you can',
      body:
          '"I improved the process" is forgettable. "I reduced processing time '
          'by 40%, saving the team 6 hours a week" is remembered. Go back through '
          'your STAR stories and add numbers, percentages, dollar amounts, or '
          'headcounts wherever possible.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children:
            _tips.map((tip) => _PrepTipRow(tip: tip, isDark: isDark)).toList(),
      ),
    );
  }
}

class _PrepTip {
  const _PrepTip({required this.title, required this.body});
  final String title;
  final String body;
}

class _PrepTipRow extends StatelessWidget {
  const _PrepTipRow({required this.tip, required this.isDark});
  final _PrepTip tip;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check, size: 12, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tip.body,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.55,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (tip != _PrepTipsCard._tips.last) ...[
                  const SizedBox(height: 14),
                  Divider(height: 1, color: border),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JobCategoryCard extends StatefulWidget {
  const _JobCategoryCard({required this.category, required this.isDark});
  final _JobCategory category;
  final bool isDark;

  @override
  State<_JobCategoryCard> createState() => _JobCategoryCardState();
}

class _JobCategoryCardState extends State<_JobCategoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final surface =
        widget.isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = widget.isDark ? AppColors.borderDark : AppColors.borderLight;
    final accent =
        widget.isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          // Category header — tap to expand
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.category.icon, size: 18, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.category.name,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '${widget.category.questions.length} sample questions',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Questions list
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: [
                  Divider(height: 1, color: border),
                  const SizedBox(height: 8),
                  ...widget.category.questions.map(
                    (q) => _QuestionCard(item: q, isDark: widget.isDark),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _UpgradeNudge extends StatelessWidget {
  const _UpgradeNudge({required this.isDark});
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
              Text(
                'Want personalized interview prep?',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Upgrade to Basic for role-specific questions drawn from your '
            'actual job posting. Upgrade to Pro for a full personalized study '
            'guide with company research and tailored answer guides.',
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.55,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
