// Marketing-capture entrypoint — NOT shipped. Run with:
//   flutter run -t marketing/seed/marketing_main.dart --dart-define=SEED_MODE=full
//   flutter run -t marketing/seed/marketing_main.dart --dart-define=SEED_MODE=fresh
//
// full  → wipes local Hive data and seeds a fictional Pro user (persona
//         "Marcus Chen" from SampleResumeData, plus tailored resumes, a cover
//         letter, and an interview study guide) so screens look in use.
// fresh → leaves storage untouched (first-run / onboarding captures).
//
// Tier is pinned to Pro in-memory by overriding the RevenueCat sync with a
// no-op. AdMob and RevenueCat are never initialized, so no ads can render.
//
// CANNOT SHIP: it lives outside lib/, so release builds (which compile
// lib/main.dart) never include it, and if someone does build a release with
// `-t marketing/seed/...` it refuses to start. Use --profile or --debug.
// test/marketing_seed_not_shipped_test.dart enforces both.
import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'package:beaconai_resume/constants/sample_resume_data.dart';
import 'package:beaconai_resume/main.dart' as app;
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/providers/user_settings_provider.dart';
import 'package:beaconai_resume/services/hive_service.dart';
import 'package:beaconai_resume/widgets/resume_template_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _mode = String.fromEnvironment('SEED_MODE', defaultValue: 'full');

class _ProPinnedSettings extends UserSettingsNotifier {
  @override
  Future<void> syncTierFromRevenueCat() async {}
}

Future<void> main() async {
  if (kReleaseMode) {
    throw StateError('marketing_main.dart is a capture-only entrypoint and '
        'must never run as a release build.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();
  if (_mode == 'full') await _seed();
  runApp(ProviderScope(
    overrides: [userSettingsProvider.overrideWith(_ProPinnedSettings.new)],
    child: const app.BeaconAIResumeApp(),
  ));
}

Future<void> _putSections(String resumeId, ResumeRenderData d,
    {bool ai = false}) async {
  Future<void> put(SectionTypeEnum t, String json) =>
      HiveService.resumeSectionBox.put(
        '${resumeId}_${t.name}',
        ResumeSection(
            id: '${resumeId}_${t.name}',
            resumeId: resumeId,
            type: t,
            data: json,
            hasUnreviewedAIContent: ai),
      );
  await put(SectionTypeEnum.contact, jsonEncode(d.contact.toJson()));
  await put(SectionTypeEnum.summary, jsonEncode({'text': d.summary}));
  await put(SectionTypeEnum.experience,
      jsonEncode(d.experience.map((e) => e.toJson()).toList()));
  await put(SectionTypeEnum.education,
      jsonEncode(d.education.map((e) => e.toJson()).toList()));
  await put(SectionTypeEnum.skills,
      jsonEncode(d.skills.map((e) => e.toJson()).toList()));
  await put(SectionTypeEnum.certifications,
      jsonEncode(d.certifications.map((e) => e.toJson()).toList()));
}

ExperienceEntry _exp(String id, String title, String co, String loc,
        String start, String? end, List<String> bullets) =>
    ExperienceEntry(
      id: id,
      title: title,
      company: co,
      location: loc,
      startDate: start,
      endDate: end ?? 'Present',
      isCurrent: end == null,
      bullets: bullets.map((b) => BulletEntry(text: b)).toList(),
    );

Future<void> _seed() async {
  await HiveService.resumeBox.clear();
  await HiveService.resumeSectionBox.clear();
  await HiveService.sourceDocumentBox.clear();
  await HiveService.coverLetterBox.clear();
  await HiveService.studyGuideBox.clear();
  await HiveService.addOnPurchaseBox.clear();

  final now = DateTime.now();
  final base = SampleResumeData.marcusChen;

  // Fuller master resume: base persona + one earlier role + extra skills.
  final master = ResumeRenderData(
    contact: base.contact,
    summary: 'Backend software engineer with 6 years of experience building '
        'and scaling distributed systems for high-traffic web applications. '
        'Specializes in API design, cloud infrastructure, and database '
        'performance — with a track record of cutting latency, cost, and '
        'release friction for product teams.',
    experience: [
      ...base.experience,
      _exp('mc_e3', 'Software Engineering Intern', 'Lumen Grove Labs',
          'Seattle, WA', 'Jun 2018', 'Sep 2018', [
        'Shipped an internal metrics dashboard used daily by 40+ engineers',
        'Automated nightly data exports, saving the ops team 6 hours a week',
      ]),
    ],
    education: base.education,
    skills: [
      ...base.skills,
      SkillEntry(id: 'mc_s9', name: 'Go', category: SkillCategoryEnum.technical),
      SkillEntry(
          id: 'mc_s10',
          name: 'Kubernetes',
          category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(
          id: 'mc_s11', name: 'GraphQL', category: SkillCategoryEnum.technical),
      SkillEntry(
          id: 'mc_s12', name: 'Redis', category: SkillCategoryEnum.toolsSoftware),
    ],
    certifications: base.certifications,
  );

  final m = Resume(
    id: 'mkt_master',
    title: 'Master Resume',
    createdAt: now.subtract(const Duration(days: 12)),
    updatedAt: now.subtract(const Duration(hours: 3)),
    isMaster: true,
    templateId: 'clean',
    uploadCount: 2,
  );
  await HiveService.resumeBox.put(m.id, m);
  await _putSections(m.id, master);

  // Tailored resumes.
  final tailored = [
    (
      id: 'mkt_t1',
      role: 'Senior Platform Engineer',
      co: 'Cascadia Cloud',
      tpl: 'technical',
      days: 1,
      jd: 'Senior Platform Engineer at Cascadia Cloud. Build and operate '
          'Kubernetes-based infrastructure, design high-throughput APIs in Go '
          'and Python, own observability and CI/CD, and mentor engineers.'
    ),
    (
      id: 'mkt_t2',
      role: 'Backend Engineer II',
      co: 'Ridgeway Health',
      tpl: 'sharp',
      days: 4,
      jd: 'Backend Engineer II at Ridgeway Health. Design HIPAA-compliant '
          'REST and GraphQL services on AWS, optimize PostgreSQL performance, '
          'and partner with product teams on patient-facing features.'
    ),
  ];
  for (final t in tailored) {
    final r = Resume(
      id: t.id,
      title: t.role,
      createdAt: now.subtract(Duration(days: t.days)),
      updatedAt: now.subtract(Duration(days: t.days)),
      isMaster: false,
      templateId: t.tpl,
      linkedJobDescription: t.jd,
      companyName: t.co,
      roleTitle: t.role,
    );
    await HiveService.resumeBox.put(r.id, r);
    await _putSections(
      r.id,
      ResumeRenderData(
        contact: master.contact,
        summary: t.co == 'Cascadia Cloud'
            ? 'Platform-minded backend engineer with 6 years scaling '
                'Kubernetes-hosted services, high-throughput Go and Python '
                'APIs, and CI/CD pipelines that let teams ship daily.'
            : 'Backend engineer with 6 years designing secure AWS services '
                'and tuning PostgreSQL for speed — ready to build reliable, '
                'patient-facing features at Ridgeway Health.',
        experience: master.experience,
        education: master.education,
        skills: master.skills,
        certifications: master.certifications,
      ),
      ai: false,
    );
  }

  final cl = CoverLetter(
    id: 'mkt_cl1',
    resumeId: 'mkt_t1',
    jobDescription: tailored.first.jd,
    content: 'Dear Cascadia Cloud Hiring Team,\n\n'
        'I\'m excited to apply for the Senior Platform Engineer role. Over the '
        'past six years I\'ve built the kind of infrastructure your team '
        'describes — most recently a microservices platform at Fernwood '
        'Technologies that handles more than 2 million requests a day while '
        'cutting average latency by 35%.\n\n'
        'I also led our move of a monolithic billing system to AWS, saving '
        '\$180K a year, and I mentor engineers through weekly code reviews. '
        'I\'d love to bring that mix of hands-on platform work and team '
        'support to Cascadia Cloud.\n\n'
        'Thank you for your time and consideration. I look forward to '
        'talking with you.\n\n'
        'Sincerely,\nMarcus Chen',
    createdAt: now.subtract(const Duration(days: 1)),
    updatedAt: now.subtract(const Duration(days: 1)),
  );
  await HiveService.coverLetterBox.put(cl.id, cl);

  InterviewQuestion q(int i, QuestionCategoryEnum c, String text, String a) =>
      InterviewQuestion(
          id: 'mkt_q$i', category: c, questionText: text, answerGuide: a);
  final guide = InterviewStudyGuide(
    id: 'mkt_g1',
    resumeId: 'mkt_master',
    companyName: 'Cascadia Cloud',
    roleTitle: 'Senior Platform Engineer',
    generatedAt: now.subtract(const Duration(hours: 20)),
    questions: [
      q(1, QuestionCategoryEnum.behavioral,
          'Tell me about a time you improved a system\'s performance under pressure.',
          'Use the Fernwood microservices rollout: 2M+ daily requests, latency '
              'down 35%. Explain how you found the bottleneck, what you changed, '
              'and how you measured the result.'),
      q(2, QuestionCategoryEnum.behavioral,
          'Describe a time you helped a teammate grow.',
          'Talk about mentoring 3 junior engineers and running weekly code '
              'reviews. Give one concrete example of feedback that changed how '
              'someone worked.'),
      q(3, QuestionCategoryEnum.roleSpecific,
          'How would you design a highly available API platform on Kubernetes?',
          'Cover multi-zone clusters, health checks, autoscaling, and rolling '
              'deploys. Tie it to your AWS migration and CI/CD experience.'),
      q(4, QuestionCategoryEnum.roleSpecific,
          'Walk us through how you would cut cloud costs without hurting reliability.',
          'Lead with the \$180K annual savings from the billing migration. '
              'Mention right-sizing, reserved capacity, and caching with Redis.'),
      q(5, QuestionCategoryEnum.companySpecific,
          'Why Cascadia Cloud, and why platform engineering?',
          'Connect your interest in developer experience to their focus on '
              'infrastructure that lets product teams ship faster.'),
      q(6, QuestionCategoryEnum.companySpecific,
          'What would your first 90 days on our platform team look like?',
          'Listen first: map current pain points, pick one quick reliability '
              'win, then propose a roadmap with clear metrics.'),
    ],
  );
  await HiveService.studyGuideBox.put(guide.id, guide);

  final s = HiveService.settings
    ..privacyAccepted = true
    ..privacyAcceptedAt = now.subtract(const Duration(days: 12))
    ..onboardingComplete = true
    ..ratingPromptShown = true
    ..tier = TierEnum.pro
    ..aiDataSharingAccepted = true
    ..theme = AppThemeEnum.light
    ..totalUploadCount = 2
    ..ageRestrictionNoticeShown = true;
  await HiveService.saveSettings(s);
}
