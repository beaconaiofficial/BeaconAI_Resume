import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Stage 7 — keep-together (Stage 11) must still hold at every density tier,
// not just whichever tier it was originally built and verified against.
//
// The retry loop (see _ResumeTemplateRendererState) targets exactly 1 page
// for a Tailored Resume before accepting the 2-page max — which means, by
// construction, a Tailored Resume only ever settles at DensityTier.standard
// when standard ALREADY brings it to a single page (if it needed more than
// one page, the loop would have kept going to compact instead). So a
// multi-page, boundary-crossing scenario is structurally impossible to
// produce at standard specifically — there's only ever one page, so
// nothing CAN straddle a page boundary there. That tier is covered here as
// a "runs cleanly, asserts nothing needs correcting" check instead.
// Comfortable (via a Master Resume, which never limits length) and compact
// (via a Tailored Resume pushed past both easier tiers) are where genuine
// multi-page boundary crossings are actually exercised, matching how the
// original Stage 11 test already covers comfortable.
// ─────────────────────────────────────────────────────────────────────────────

Resume _resume({required bool isMaster}) => Resume(
      id: 'r1',
      title: 'Test',
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      isMaster: isMaster,
      linkedJobDescription: isMaster ? null : 'Some job',
    );

List<ExperienceEntry> _identicalEntries(int count, int bulletsPerEntry) =>
    List.generate(
      count,
      (i) => ExperienceEntry(
        id: 'e$i',
        title: 'Job Title $i',
        company: 'Company $i',
        startDate: '2020',
        endDate: '2021',
        bullets: [
          for (int b = 0; b < bulletsPerEntry; b++)
            BulletEntry(
                text:
                    'Distinct achievement bullet number $b for role $i with detail'),
        ],
      ),
    );

ResumeRenderData _data(int entryCount, int bulletsPerEntry) => ResumeRenderData(
      contact: ContactInfo(firstName: 'Test', lastName: 'User'),
      summary: '',
      experience: _identicalEntries(entryCount, bulletsPerEntry),
      education: const [],
      skills: const [],
      certifications: const [],
    );

/// Renders [resume]/[data], settles the retry loop, and asserts no
/// experience entry's title/subtitle + first bullet straddles a
/// kResumePageHeight boundary — the Stage 11 invariant, checked at whatever
/// tier this fixture settles at (captured tier for the caller to assert on
/// separately).
Future<DensityTier> _renderAndCheckNoStraddle(
  WidgetTester tester, {
  required Resume resume,
  required ResumeRenderData data,
}) async {
  DensityTier? settledTier;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: kResumePageWidth,
            child: ResumeTemplateRenderer(
              resume: resume,
              data: data,
              onDensityResult: (tier, pageCount, exceedsMax) {
                settledTier = tier;
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

  var checkedAtLeastOne = false;
  for (int i = 0; i < data.experience.length; i++) {
    final entry = data.experience[i];
    final headingFinder =
        find.text('${entry.title}  |  ${entry.company}');
    final firstBulletFinder = find.text(entry.bullets.first.text);
    if (tester.widgetList(headingFinder).isEmpty ||
        tester.widgetList(firstBulletFinder).isEmpty) {
      continue;
    }

    final headingTop = tester.getTopLeft(headingFinder).dy;
    final bulletBottom = tester.getBottomLeft(firstBulletFinder).dy;
    final blockHeight = bulletBottom - headingTop;
    if (blockHeight > kResumePageHeight) continue;

    checkedAtLeastOne = true;
    final startPage = (headingTop / kResumePageHeight).floor();
    final endPage = ((bulletBottom - 0.01) / kResumePageHeight).floor();
    expect(
      startPage,
      endPage,
      reason: '${entry.title} straddles a page boundary at tier '
          '$settledTier (top=$headingTop, bottom=$bulletBottom)',
    );
  }
  expect(checkedAtLeastOne, isTrue,
      reason: 'fixture should produce enough content to actually exercise '
          'the check');

  return settledTier!;
}

void main() {
  group('Stage 7 — keep-together holds at every density tier', () {
    testWidgets('comfortable — Master Resume, many entries, multiple pages',
        (tester) async {
      final tier = await _renderAndCheckNoStraddle(
        tester,
        resume: _resume(isMaster: true),
        data: _data(30, 1),
      );
      expect(tier, DensityTier.comfortable);
    });

    testWidgets(
        'standard — Tailored Resume that settles at standard (single page '
        'by construction — see file header comment for why a multi-page '
        'standard scenario cannot occur)', (tester) async {
      final tier = await _renderAndCheckNoStraddle(
        tester,
        resume: _resume(isMaster: false),
        data: _data(12, 2),
      );
      expect(tier, DensityTier.standard);
    });

    testWidgets(
        'compact — Tailored Resume pushed past comfortable and standard, '
        'many entries, multiple pages', (tester) async {
      final tier = await _renderAndCheckNoStraddle(
        tester,
        resume: _resume(isMaster: false),
        data: _data(19, 3),
      );
      expect(tier, DensityTier.compact);
    });
  });
}
