import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/screens/resume_editor_screen.dart';
import 'package:beaconai_resume/widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ISSUE 2 — Preview & Edit lost its scrollbar and showed phantom blank pages
// at the bottom.
//
// Root causes (two independent bugs, both pre-dating and unrelated to each
// other in mechanism, though the zoom feature's InteractiveViewer is what
// exposed the missing-scrollbar one):
//
//   1. Missing scrollbar: InteractiveViewer's pan (not a Scrollable) is what
//      actually navigates multi-page content — it replaced whatever native
//      scroll behavior existed before without providing any visual
//      indicator that content is scrollable. Flutter's built-in Scrollbar
//      widget can't attach to InteractiveViewer directly (it requires a
//      real Scrollable). Fixed with a passive scroll-position indicator
//      driven by the same TransformationController, with no change to
//      InteractiveViewer's own pan/zoom gesture handling.
//
//   2. Phantom blank pages: _pageCount() is a heuristic (entry/cert counts),
//      not a measurement of actual rendered height — for resumes with few
//      bullets per entry, it can overshoot the real page count, rendering
//      page-card containers with nothing left to slice into them (visibly
//      blank). Fixed by measuring the real rendered height via a GlobalKey
//      + post-frame callback and overriding the heuristic once known.
// ─────────────────────────────────────────────────────────────────────────────

Resume _resumeFixture() => Resume(
      id: 'r1',
      title: 'Test Resume',
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      isMaster: true,
    );

/// Many entries, each with an empty bullet list — the heuristic
/// (1 + ceil(entryCount/3)) estimates a large page count from entry count
/// alone, but near-empty entries render far shorter than that.
ResumeRenderData _sparseManyEntriesFixture() => ResumeRenderData(
      contact: ContactInfo(firstName: 'Test', lastName: 'User'),
      summary: '',
      experience: List.generate(
        20,
        (i) => ExperienceEntry(
          id: 'e$i',
          title: 'Role $i',
          company: 'Company $i',
          bullets: const [],
        ),
      ),
      education: const [],
      skills: const [],
      certifications: const [],
    );

ResumeRenderData _minimalFixture() => ResumeRenderData(
      contact: ContactInfo(firstName: 'Test', lastName: 'User'),
      summary: 'A short summary.',
      experience: const [],
      education: const [],
      skills: const [],
      certifications: const [],
    );

/// Counts rendered page-card containers via their distinguishing fixed
/// height — a Container with a BoxDecoration and exactly kResumePageHeight
/// is a page-card, not incidental to anything else in the tree.
int _pageCardCount(WidgetTester tester) {
  return tester
      .widgetList<Container>(find.byType(Container))
      .where((c) =>
          c.constraints?.maxHeight == kResumePageHeight ||
          (c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).boxShadow != null))
      .length;
}

void main() {
  testWidgets(
      'a heuristic-overshoot resume (many entries, no bullets) settles to '
      'fewer rendered page-cards than the naive heuristic estimate — no '
      'genuinely blank trailing pages', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: EditorPreviewPane(
              resume: _resumeFixture(),
              renderData: _sparseManyEntriesFixture(),
              isDark: false,
            ),
          ),
        ),
      ),
    );

    // First frame: heuristic estimate only (measurement hasn't run yet).
    // 20 entries -> 1 + ceil(20/3) = 8 (clamped).
    final firstFrameCount = _pageCardCount(tester);
    expect(firstFrameCount, 8,
        reason: 'first frame renders the heuristic\'s estimate before '
            'measurement has had a chance to run');

    // Let the post-frame measurement callback(s) settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final settledCount = _pageCardCount(tester);
    expect(settledCount, lessThan(8),
        reason: '20 bulletless entries render far shorter than 8 full '
            'pages — once measurement overrides the heuristic, the '
            'genuinely-blank trailing page-cards must be gone');
  });

  testWidgets(
      'a minimal one-page resume settles to a single page-card, not the '
      "heuristic's default", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: EditorPreviewPane(
              resume: _resumeFixture(),
              renderData: _minimalFixture(),
              isDark: false,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(_pageCardCount(tester), 1,
        reason: 'a resume with a short summary and no sections at all must '
            'settle to exactly one page-card, not an over-estimated '
            'multi-page heuristic result');
  });

  // The scroll-position indicator is a Container with a fixed 4px width —
  // distinguishing enough within this widget's tree (page-cards, the
  // reset pill, and template content don't use a literal 4px-wide
  // Container) to check for without needing to reference the private
  // widget type directly.
  bool hasScrollIndicator(WidgetTester tester) {
    return tester
        .widgetList<Container>(find.byType(Container))
        .any((c) => c.constraints?.maxWidth == 4.0);
  }

  testWidgets(
      'the scroll indicator is absent when content fits the viewport at '
      'baseline zoom — matches a real Scrollbar staying hidden with '
      'nothing to scroll', (tester) async {
    // The default test surface (~800x600) is shorter than the 1400 this
    // test needs — without resizing it, the SizedBox below would be
    // constrained down to the surface's real height, making content
    // overflow it regardless of what height is requested here.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 1400, // tall viewport — a 1-page resume fits easily
            child: EditorPreviewPane(
              resume: _resumeFixture(),
              renderData: _minimalFixture(),
              isDark: false,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(hasScrollIndicator(tester), isFalse);
  });

  testWidgets(
      'the scroll indicator appears when content exceeds a short viewport '
      "— restores the visual affordance InteractiveViewer's pan-only "
      'navigation removed', (tester) async {
    // Many entries WITH bullets — genuinely tall, multi-page content.
    final tallData = ResumeRenderData(
      contact: ContactInfo(firstName: 'Test', lastName: 'User'),
      summary: 'A summary.',
      experience: List.generate(
        12,
        (i) => ExperienceEntry(
          id: 'e$i',
          title: 'Role $i',
          company: 'Company $i',
          bullets: const [
            'Did a substantial, detailed thing worth a full line of text',
            'Did another substantial, detailed thing worth a full line',
          ],
        ),
      ),
      education: const [],
      skills: const [],
      certifications: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400, // short viewport relative to genuinely tall content
            child: EditorPreviewPane(
              resume: _resumeFixture(),
              renderData: tallData,
              isDark: false,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(hasScrollIndicator(tester), isTrue);
  });
}
