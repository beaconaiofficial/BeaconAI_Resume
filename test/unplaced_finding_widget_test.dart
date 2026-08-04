import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/screens/document_upload_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Verifies Stage 3's two new confirmation-screen card types, built on the
// same ConfirmationView the pending-decision cards already use:
//   - UnplacedFinding cards: a number/claim Claude couldn't confidently map
//     to a structured field, surfaced with source context; the user attaches
//     it to an entry or discards it — discarding is a fully valid resolution,
//     never blocks Apply All.
//   - Bullet metric-request cards: a bullet Claude kept without a
//     quantifiable result, inviting the user to add one or skip.
// ─────────────────────────────────────────────────────────────────────────────

class _Harness extends StatefulWidget {
  const _Harness({
    required this.onFindingResolved,
    required this.onBulletMetricResolved,
  });

  final void Function(
    String id, {
    int? attachToEducationIndex,
    int? appendToExperienceIndex,
  }) onFindingResolved;
  final void Function(int experienceIndex, int bulletIndex, String? metricText)
      onBulletMetricResolved;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  List<UnplacedFinding> _unplaced = [
    UnplacedFinding(
      id: 'uf1',
      value: '3.94 GPA',
      context: 'achieving the dean\'s list with a 3.94 GPA in Information '
          'Technology',
    ),
  ];

  final List<Map<String, dynamic>> _mappings = [
    {
      'field': 'education',
      'suggestedValue': [
        {
          'id': 'edu1',
          'degree': 'Bachelor of Science',
          'institution': 'American Military University',
          'fieldOfStudy': 'Information Technology',
          'graduationYear': '2026',
          'gpa': null,
        },
      ],
      'confidence': 0.9,
      'accepted': true,
    },
    {
      'field': 'experience',
      'suggestedValue': [
        {
          'id': 'exp1',
          'title': 'Network Systems Engineer',
          'company': 'Acme Corp',
          'startDate': '2019',
          'endDate': '2022',
          'isCurrent': false,
          'bullets': [
            {
              'text': 'Maintained enterprise network infrastructure',
              'hasQuantifiableData': false,
              'metricRequested': false,
            },
          ],
        },
      ],
      'confidence': 0.88,
      'accepted': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ConfirmationView(
          processedFileNames: const ['transcript.pdf'],
          failedFileNames: const [],
          mappings: _mappings,
          pendingDecisions: const [],
          unplacedFindings: _unplaced,
          timelineGaps: const [],
          isDark: false,
          showSourceFile: false,
          onToggleMapping: (i, accepted) {},
          onManualLocationChanged: (i, city, state) {},
          onResolveDecision: (id, decision) {},
          onResolveUnplacedFinding: (id,
              {attachToEducationIndex, appendToExperienceIndex}) {
            widget.onFindingResolved(id,
                attachToEducationIndex: attachToEducationIndex,
                appendToExperienceIndex: appendToExperienceIndex);
            setState(() {
              _unplaced = _unplaced.where((f) => f.id != id).toList();
            });
          },
          onResolveBulletMetric: (experienceIndex, bulletIndex, metricText) {
            widget.onBulletMetricResolved(
                experienceIndex, bulletIndex, metricText);
            setState(() {
              final expRow =
                  _mappings.firstWhere((m) => m['field'] == 'experience');
              final list =
                  List<dynamic>.from(expRow['suggestedValue'] as List);
              final entry = Map<String, dynamic>.from(list[experienceIndex] as Map);
              final bullets =
                  List<dynamic>.from(entry['bullets'] as List);
              final bullet = Map<String, dynamic>.from(bullets[bulletIndex] as Map);
              bullet['metricRequested'] = true;
              if (metricText != null && metricText.trim().isNotEmpty) {
                bullet['text'] = metricText.trim();
                bullet['hasQuantifiableData'] = true;
              }
              bullets[bulletIndex] = bullet;
              entry['bullets'] = bullets;
              list[experienceIndex] = entry;
              expRow['suggestedValue'] = list;
            });
          },
          onResolveTimelineGap: (id, status) {},
          onApplyAll: () {},
          onCancel: () {},
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
      'unplaced finding card shows the value and context, and Apply All is '
      'never blocked by it', (tester) async {
    await tester.pumpWidget(_Harness(
      onFindingResolved: (_, {attachToEducationIndex, appendToExperienceIndex}) {},
      onBulletMetricResolved: (_, __, ___) {},
    ));

    expect(find.textContaining('Found: 3.94 GPA'), findsOneWidget);
    expect(find.textContaining('dean\'s list'), findsOneWidget);

    // Apply All must already be enabled — an unplaced finding is not a
    // pending decision and must never block applying.
    final applyButton = tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Apply 2 Fields'));
    expect(applyButton.onPressed, isNotNull);
  });

  testWidgets('"Attach to..." resolves with the matching education index',
      (tester) async {
    String? resolvedId;
    int? resolvedEduIndex;
    await tester.pumpWidget(_Harness(
      onFindingResolved: (id, {attachToEducationIndex, appendToExperienceIndex}) {
        resolvedId = id;
        resolvedEduIndex = attachToEducationIndex;
      },
      onBulletMetricResolved: (_, __, ___) {},
    ));

    await tester.tap(find.widgetWithText(
        OutlinedButton, 'Attach to American Military University'));
    await tester.pumpAndSettle();

    expect(resolvedId, 'uf1');
    expect(resolvedEduIndex, 0);
    expect(find.textContaining('Found: 3.94 GPA'), findsNothing,
        reason: 'the card should be gone once resolved');
  });

  testWidgets('"Discard" resolves with no target indices', (tester) async {
    int? eduIndex = -1;
    int? expIndex = -1;
    await tester.pumpWidget(_Harness(
      onFindingResolved: (id, {attachToEducationIndex, appendToExperienceIndex}) {
        eduIndex = attachToEducationIndex;
        expIndex = appendToExperienceIndex;
      },
      onBulletMetricResolved: (_, __, ___) {},
    ));

    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(eduIndex, isNull);
    expect(expIndex, isNull);
  });

  testWidgets(
      'bullet metric card shows the prompt for a hasQuantifiableData:false '
      'bullet, and Skip marks it resolved without changing the text',
      (tester) async {
    await tester.pumpWidget(_Harness(
      onFindingResolved: (_, {attachToEducationIndex, appendToExperienceIndex}) {},
      onBulletMetricResolved: (_, __, ___) {},
    ));

    expect(find.textContaining('could be stronger with a number'),
        findsOneWidget);
    expect(find.byType(TextField), findsWidgets);

    final skipButton = find.widgetWithText(TextButton, 'Skip');
    await tester.ensureVisible(skipButton);
    await tester.pumpAndSettle();
    await tester.tap(skipButton);
    await tester.pumpAndSettle();

    // Resolved (metricRequested: true) — the card must not reappear.
    expect(find.textContaining('could be stronger with a number'),
        findsNothing);
  });

  testWidgets('supplying a metric and tapping Save rewrites the bullet text',
      (tester) async {
    int? capturedExpIndex;
    int? capturedBulletIndex;
    String? capturedMetric;
    await tester.pumpWidget(_Harness(
      onFindingResolved: (_, {attachToEducationIndex, appendToExperienceIndex}) {},
      onBulletMetricResolved: (expIdx, bulletIdx, metric) {
        capturedExpIndex = expIdx;
        capturedBulletIndex = bulletIdx;
        capturedMetric = metric;
      },
    ));

    final field = find.byType(TextField).first;
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field,
        'Maintained enterprise network infrastructure for 300+ endpoints');
    final saveButton = find.widgetWithText(OutlinedButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(capturedExpIndex, 0);
    expect(capturedBulletIndex, 0);
    expect(capturedMetric, contains('300+ endpoints'));
  });
}
