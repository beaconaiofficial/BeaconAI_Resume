import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Stage 7 — density tiers.
//
// Verifies ResumeTemplateRenderer's merged density-tier + keep-together
// retry loop (see the doc comment on _ResumeTemplateRendererState): render
// at comfortable first, retry standard then compact against the Tailored
// Resume's 1-page target, accept up to the 2-page max, and never touch
// tier or page-limit at all for a Master Resume (Stage 9 exhaustiveness).
// ─────────────────────────────────────────────────────────────────────────────

Resume _resume({required bool isMaster, String? linkedJobDescription}) => Resume(
      id: 'r1',
      title: 'Test',
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      isMaster: isMaster,
      linkedJobDescription: linkedJobDescription,
    );

List<ExperienceEntry> _entries(int count, {int bulletsPerEntry = 3}) =>
    List.generate(
      count,
      (i) => ExperienceEntry(
        id: 'e$i',
        title: 'Job Title $i',
        company: 'Company $i',
        startDate: '2018',
        endDate: '2019',
        bullets: [
          for (int b = 0; b < bulletsPerEntry; b++)
            BulletEntry(
                text:
                    'A reasonably detailed achievement bullet number $b for role $i '
                    'describing scope and a measurable outcome'),
        ],
      ),
    );

ResumeRenderData _data(int entryCount, {int bulletsPerEntry = 3}) =>
    ResumeRenderData(
      contact: ContactInfo(firstName: 'Test', lastName: 'User'),
      summary: 'A short professional summary.',
      experience: _entries(entryCount, bulletsPerEntry: bulletsPerEntry),
      education: const [],
      skills: const [],
      certifications: const [],
    );

Future<({DensityTier tier, int pageCount, bool exceedsTailoredMax})>
    _renderAndSettle(
  WidgetTester tester, {
  required Resume resume,
  required ResumeRenderData data,
}) async {
  DensityTier? tier;
  int? pageCount;
  bool? exceedsMax;

  // SingleChildScrollView (not a fixed-size viewport) gives its child
  // genuinely UNBOUNDED height, matching how the real app measures this
  // widget: EditorPreviewPane wraps it in Positioned(top: ...) inside a
  // Stack, which is also unbounded in height. A bounded-but-large fake
  // viewport instead gives Column (mainAxisSize.max by default) a finite
  // height to stretch-fill, so rootBox.size.height would just report
  // whatever viewport height was picked, not the true content height.
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: kResumePageWidth,
            child: ResumeTemplateRenderer(
              resume: resume,
              data: data,
              onDensityResult: (t, p, e) {
                tier = t;
                pageCount = p;
                exceedsMax = e;
              },
            ),
          ),
        ),
      ),
    ),
  );
  for (int i = 0; i < 40; i++) {
    await tester.pump();
  }

  return (tier: tier!, pageCount: pageCount!, exceedsTailoredMax: exceedsMax!);
}

void main() {
  group('Stage 7 — density tiers', () {
    testWidgets(
        'a Tailored Resume that fits at comfortable renders there without '
        'retrying', (tester) async {
      final result = await _renderAndSettle(
        tester,
        resume: _resume(isMaster: false, linkedJobDescription: 'Some job'),
        data: _data(2, bulletsPerEntry: 2),
      );

      expect(result.tier, DensityTier.comfortable);
      expect(result.pageCount, 1);
      expect(result.exceedsTailoredMax, isFalse);
    });

    testWidgets(
        'a Tailored Resume that only fits within the 2-page max at compact '
        'retries through both tiers correctly', (tester) async {
      final result = await _renderAndSettle(
        tester,
        resume: _resume(isMaster: false, linkedJobDescription: 'Some job'),
        data: _data(8, bulletsPerEntry: 3),
      );

      expect(result.tier, DensityTier.compact,
          reason: 'the retry loop always steps comfortable -> standard -> '
              'compact in order, one tier at a time, and this fixture does '
              'not fit the 1-page target at comfortable — landing on '
              'compact proves both earlier tiers were tried first and '
              'rejected, not skipped to');
      expect(result.pageCount, lessThanOrEqualTo(2));
      expect(result.exceedsTailoredMax, isFalse,
          reason: 'compact brings this fixture within the 2-page max, even '
              'though it does not reach the 1-page target');
    });

    testWidgets(
        'a Tailored Resume that does not fit even at compact triggers the '
        'user-facing prompt rather than truncating or silently overflowing',
        (tester) async {
      final result = await _renderAndSettle(
        tester,
        resume: _resume(isMaster: false, linkedJobDescription: 'Some job'),
        data: _data(60, bulletsPerEntry: 4),
      );

      expect(result.tier, DensityTier.compact,
          reason: 'must exhaust every tier before giving up');
      expect(result.pageCount, greaterThan(2));
      expect(result.exceedsTailoredMax, isTrue,
          reason: 'still over the 2-page max even at the tightest tier — '
              'must be reported, never silently truncated or silently left '
              'overflowing');
    });

    testWidgets(
        'a Master Resume with the same over-length content never gets '
        'tier-shrunk or prompted at all', (tester) async {
      final result = await _renderAndSettle(
        tester,
        resume: _resume(isMaster: true),
        data: _data(60, bulletsPerEntry: 4),
      );

      expect(result.tier, DensityTier.comfortable,
          reason: 'Master Resumes always render at comfortable, no '
              'exceptions, regardless of length (Stage 9 exhaustiveness)');
      expect(result.pageCount, greaterThan(2),
          reason: 'the exact same content that triggers the Tailored '
              'prompt above must be allowed to run long here');
      expect(result.exceedsTailoredMax, isFalse,
          reason: 'Master Resumes never trip the max — there is no limit '
              'to trip');
    });
  });
}
