import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/screens/resume_editor_screen.dart';
import 'package:beaconai_resume/widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pinch-to-zoom on the resume preview pane. EditorPreviewPane is the same
// widget used by both the wide (two-pane, >800px) and narrow (tabbed)
// editor layouts, so testing it directly at different container widths
// covers both.
// ─────────────────────────────────────────────────────────────────────────────

final _resume = Resume(
  id: 'r1',
  title: 'Test Resume',
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
  isMaster: true,
);

final _renderData = ResumeRenderData(
  contact: ContactInfo(firstName: 'Jane', lastName: 'Doe'),
  summary: 'A summary.',
  experience: [
    ExperienceEntry(id: 'e1', title: 'Engineer', company: 'Acme', bullets: ['Did things']),
  ],
  education: const [],
  skills: const [],
  certifications: const [],
);

Widget _wrap(Widget child, {double width = 900, bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        disableAnimations: disableAnimations,
      ),
      child: Scaffold(
        body: SizedBox(width: width, height: 800, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('builds cleanly and shows InteractiveViewer with the correct '
      'min/max zoom bounds', (tester) async {
    await tester.pumpWidget(_wrap(
      EditorPreviewPane(resume: _resume, renderData: _renderData, isDark: false),
    ));
    await tester.pump();

    final viewerFinder = find.byType(InteractiveViewer);
    expect(viewerFinder, findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    expect(viewer.minScale, 1.0,
        reason: 'must not allow zooming out past fit-to-width');
    expect(viewer.maxScale, 3.0, reason: 'max zoom should be ~3x fit-to-width');
  });

  testWidgets('reset pill is hidden at baseline and appears once zoomed',
      (tester) async {
    // find.bySemanticsLabel requires an active semantics tree, which the
    // test binding doesn't build by default (no screen reader listening).
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap(
      EditorPreviewPane(resume: _resume, renderData: _renderData, isDark: false),
    ));
    await tester.pump();

    expect(find.text('Reset zoom'), findsNothing,
        reason: 'pill must not show at the fit-to-width baseline');

    final controller =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;
    controller.value = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
    await tester.pump();

    expect(find.text('Reset zoom'), findsOneWidget,
        reason: 'pill must appear once meaningfully zoomed in');
    expect(find.bySemanticsLabel('Reset zoom'), findsOneWidget);

    semanticsHandle.dispose();
  });

  testWidgets('tapping the reset pill returns the transform to identity '
      '(animated by default)', (tester) async {
    await tester.pumpWidget(_wrap(
      EditorPreviewPane(resume: _resume, renderData: _renderData, isDark: false),
    ));
    await tester.pump();

    final controller =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;
    controller.value = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
    await tester.pump();
    expect(find.text('Reset zoom'), findsOneWidget);

    await tester.tap(find.text('Reset zoom'));
    // Animated reset (220ms) — advance past it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.value, Matrix4.identity());
    expect(find.text('Reset zoom'), findsNothing,
        reason: 'pill must hide again once back at baseline');
  });

  testWidgets('double-tap on the preview resets zoom the same way as the pill',
      (tester) async {
    await tester.pumpWidget(_wrap(
      EditorPreviewPane(resume: _resume, renderData: _renderData, isDark: false),
    ));
    await tester.pump();

    final controller =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;
    controller.value = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
    await tester.pump();
    expect(find.text('Reset zoom'), findsOneWidget);

    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tapAt(center);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.value, Matrix4.identity());
  });

  testWidgets('reduce-motion makes reset instant rather than animated',
      (tester) async {
    await tester.pumpWidget(_wrap(
      EditorPreviewPane(resume: _resume, renderData: _renderData, isDark: false),
      disableAnimations: true,
    ));
    await tester.pump();

    final controller =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;
    controller.value = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
    await tester.pump();

    await tester.tap(find.text('Reset zoom'));
    // A single pump (no extra animation time) is enough under reduce-motion.
    await tester.pump();

    expect(controller.value, Matrix4.identity(),
        reason: 'reset must be instant under reduce-motion, not mid-animation');
  });

  testWidgets('panning while zoomed changes the transform translation',
      (tester) async {
    await tester.pumpWidget(_wrap(
      EditorPreviewPane(resume: _resume, renderData: _renderData, isDark: false),
    ));
    await tester.pump();

    final controller =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;
    controller.value = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
    await tester.pump();

    final before = controller.value.clone();
    await tester.drag(find.byType(InteractiveViewer), const Offset(-40, -40));
    await tester.pump();
    // The drag's initial pointer-down is also tracked by the InteractiveViewer's
    // internal double-tap recognizer (it must watch every tap-down in case a
    // second one follows) — let that ~300ms timeout resolve before the test
    // tears down, or the binding flags it as a leaked pending timer.
    await tester.pump(const Duration(milliseconds: 350));

    expect(controller.value, isNot(before),
        reason: 'dragging while zoomed in should pan the content');
  });

  testWidgets('builds without overflow at a narrow (mobile-width) container',
      (tester) async {
    await tester.pumpWidget(_wrap(
      EditorPreviewPane(resume: _resume, renderData: _renderData, isDark: false),
      width: 360,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('builds without overflow at a wide (desktop two-pane) container',
      (tester) async {
    await tester.pumpWidget(_wrap(
      EditorPreviewPane(resume: _resume, renderData: _renderData, isDark: false),
      width: 1100,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
}
