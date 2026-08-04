import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/screens/document_upload_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Verifies the timeline-coverage-gap confirmation-screen card (Stage 3 of
// the tailored-resume-pipeline spec) renders on ConfirmationView and that
// both resolutions ("Nothing missing" / "Dismiss") remove the card without
// blocking Apply All — the same non-blocking convention as UnplacedFinding.
// ─────────────────────────────────────────────────────────────────────────────

class _Harness extends StatefulWidget {
  const _Harness({required this.onResolved});

  final void Function(String id, TimelineGapStatus status) onResolved;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  List<TimelineCoverageGap> _gaps = [
    TimelineCoverageGap(
      id: 'gap1',
      startDate: DateTime(2019, 6, 1),
      endDate: DateTime(2020, 6, 1),
      kind: TimelineGapKind.betweenEntries,
      adjacentEntryIds: const ['job1', 'job2'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ConfirmationView(
          processedFileNames: const ['resume.pdf'],
          failedFileNames: const [],
          mappings: const [],
          pendingDecisions: const [],
          unplacedFindings: const [],
          timelineGaps: _gaps,
          isDark: false,
          showSourceFile: false,
          onToggleMapping: (i, accepted) {},
          onManualLocationChanged: (i, city, state) {},
          onResolveDecision: (id, decision) {},
          onResolveUnplacedFinding: (id,
              {attachToEducationIndex, appendToExperienceIndex}) {},
          onResolveBulletMetric: (experienceIndex, bulletIndex, metricText) {},
          onResolveTimelineGap: (id, status) {
            widget.onResolved(id, status);
            setState(() {
              _gaps = _gaps.where((g) => g.id != id).toList();
            });
          },
          onApplyAll: () {},
          onCancel: () {},
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
      'a timeline gap card shows the date range and prompt, and Apply All '
      'is never blocked by it', (tester) async {
    final resolutions = <(String, TimelineGapStatus)>[];

    await tester.pumpWidget(_Harness(
      onResolved: (id, status) => resolutions.add((id, status)),
    ));

    expect(find.text('Possible gap: Jun 2019 – Jun 2020'), findsOneWidget);
    expect(find.textContaining('what were you doing'), findsOneWidget,
        reason: 'betweenEntries gaps use the "what were you doing" prompt');

    await tester.ensureVisible(find.text('Nothing missing'));
    await tester.tap(find.text('Nothing missing'));
    await tester.pump();

    expect(resolutions, [('gap1', TimelineGapStatus.userConfirmedNoGap)]);
    expect(find.text('Possible gap: Jun 2019 – Jun 2020'), findsNothing,
        reason: 'resolving the card removes it');
  });

  testWidgets('a withinEntry gap uses the "did your duties change" prompt',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConfirmationView(
          processedFileNames: const ['resume.pdf'],
          failedFileNames: const [],
          mappings: const [],
          pendingDecisions: const [],
          unplacedFindings: const [],
          timelineGaps: [
            TimelineCoverageGap(
              id: 'gap2',
              startDate: DateTime(2021, 11, 1),
              endDate: DateTime(2023, 7, 1),
              kind: TimelineGapKind.withinEntry,
              adjacentEntryIds: const ['role1'],
            ),
          ],
          isDark: false,
          showSourceFile: false,
          onToggleMapping: (i, accepted) {},
          onManualLocationChanged: (i, city, state) {},
          onResolveDecision: (id, decision) {},
          onResolveUnplacedFinding: (id,
              {attachToEducationIndex, appendToExperienceIndex}) {},
          onResolveBulletMetric: (experienceIndex, bulletIndex, metricText) {},
          onResolveTimelineGap: (id, status) {},
          onApplyAll: () {},
          onCancel: () {},
        ),
      ),
    ));

    expect(find.textContaining('did your duties change'), findsOneWidget);
  });

  testWidgets('dismissing a gap also removes it, not just confirming no gap',
      (tester) async {
    final resolutions = <(String, TimelineGapStatus)>[];

    await tester.pumpWidget(_Harness(
      onResolved: (id, status) => resolutions.add((id, status)),
    ));

    await tester.ensureVisible(find.text('Dismiss'));
    await tester.tap(find.text('Dismiss'));
    await tester.pump();

    expect(resolutions, [('gap1', TimelineGapStatus.dismissed)]);
  });
}
