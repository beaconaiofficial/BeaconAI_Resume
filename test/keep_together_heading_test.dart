import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Stage 11 — header/subtitle keep-together rendering rule.
//
// A real formatting problem: a job's title/subtitle landed alone at the
// bottom of a page with its bullets starting fresh on the next page.
// resume_editor_screen.dart's preview renders the WHOLE resume as one
// continuous, unbounded-height column and slices it into fixed-height
// kResumePageHeight windows purely by Y position — there is no reflow, so a
// heading could land anywhere relative to a page boundary by coincidence.
//
// This constructs a fixture with many identical experience entries, each
// contributing the same natural height, so their headings fall at a
// spread of offsets relative to a kResumePageHeight boundary — some would
// straddle one without the fix, purely from the periodic natural height,
// deliberately landing at least one heading at a page boundary rather than
// relying on the exact pixel math of any single hand-picked entry. The
// invariant checked for every entry: its title/subtitle row and first
// bullet never land on two different pages.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  testWidgets(
      'a job heading (title/subtitle + first bullet) is never split across '
      'a page boundary — it is pushed to the next page as one unit instead',
      (tester) async {
    // Big enough to render every one of the many entries below without a
    // RenderFlex overflow — this test cares about true, unconstrained
    // document-relative Y positions, the same coordinate space
    // _ResumeTemplateRendererState measures against.
    tester.view.physicalSize = const Size(1000, 60000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final resume = Resume(
      id: 'r1',
      title: 'Test Resume',
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      isMaster: true,
    );

    final experience = List.generate(
      30,
      (i) => ExperienceEntry(
        id: 'e$i',
        title: 'Job Title $i',
        company: 'Company $i',
        startDate: '2020',
        endDate: '2021',
        bullets: [BulletEntry(text: 'Distinct achievement bullet number $i')],
      ),
    );

    final data = ResumeRenderData(
      contact: ContactInfo(firstName: 'Test', lastName: 'User'),
      summary: '',
      experience: experience,
      education: const [],
      skills: const [],
      certifications: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: kResumePageWidth,
            child: ResumeTemplateRenderer(resume: resume, data: data),
          ),
        ),
      ),
    );

    // Let the measure/render/remeasure loop settle (bounded at 6 passes
    // internally — a handful of extra pumps is enough to exhaust it).
    for (int i = 0; i < 8; i++) {
      await tester.pump();
    }

    var checkedAtLeastOne = false;
    for (int i = 0; i < experience.length; i++) {
      final headingFinder = find.text('Job Title $i  |  Company $i');
      final bulletFinder =
          find.text('Distinct achievement bullet number $i');
      if (tester.widgetList(headingFinder).isEmpty ||
          tester.widgetList(bulletFinder).isEmpty) {
        continue;
      }

      final headingTop = tester.getTopLeft(headingFinder).dy;
      final bulletBottom = tester.getBottomLeft(bulletFinder).dy;
      final blockHeight = bulletBottom - headingTop;

      // A block taller than a full page can never avoid straddling
      // regardless of spacing — not something keep-together can fix, and
      // not what this test is checking.
      if (blockHeight > kResumePageHeight) continue;

      checkedAtLeastOne = true;
      final startPage = (headingTop / kResumePageHeight).floor();
      // Subtract an epsilon so a block landing exactly ON a boundary
      // (bulletBottom == n * kResumePageHeight) isn't misread as spilling
      // one pixel onto the next page.
      final endPage = ((bulletBottom - 0.01) / kResumePageHeight).floor();

      expect(
        startPage,
        endPage,
        reason: "Job Title $i's heading + first bullet straddles a page "
            'boundary (top=$headingTop, bottom=$bulletBottom, '
            'kResumePageHeight=$kResumePageHeight) — it should have been '
            'pushed to the next page as a whole unit instead of splitting',
      );
    }

    expect(checkedAtLeastOne, isTrue,
        reason: 'the fixture should produce enough content to actually '
            'exercise the page-boundary check for at least one entry');
  });
}
