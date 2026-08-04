import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/screens/document_upload_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Stage 10 — contact address manual-entry fallback.
//
// Real testing showed neither of Stage 2's two extracted location
// candidates is guaranteed correct (a user's actual current address matched
// neither their home-of-record nor their duty-station city). This verifies
// the fix on the real ConfirmationView/_MappingRow widgets used by the
// document-upload confirmation screen: a third, always-present, equally
// prominent manual-entry option in the contact.location conflict group,
// defaulted to selected instead of either extracted candidate.
//
// Harness reproduces the parent-owns-the-list pattern
// _DocumentUploadScreenState uses (see pending_decision_widget_test.dart
// for the same convention).
// ─────────────────────────────────────────────────────────────────────────────

class _Harness extends StatefulWidget {
  const _Harness({required this.initialMappings});
  final List<Map<String, dynamic>> initialMappings;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final List<Map<String, dynamic>> _mappings = [];

  @override
  void initState() {
    super.initState();
    _mappings.addAll(widget.initialMappings);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ConfirmationView(
          processedFileNames: const ['stp.pdf', 'ncoer.pdf'],
          failedFileNames: const [],
          mappings: _mappings,
          pendingDecisions: const [],
          unplacedFindings: const [],
          timelineGaps: const [],
          isDark: false,
          showSourceFile: true,
          onToggleMapping: (i, accepted) {
            setState(() {
              final groupId = _mappings[i]['conflictGroupId'] as String?;
              if (groupId != null) {
                if (!accepted) return;
                for (final m in _mappings) {
                  if (m['conflictGroupId'] == groupId) m['accepted'] = false;
                }
              }
              _mappings[i]['accepted'] = accepted;
            });
          },
          onManualLocationChanged: (i, city, state) {
            setState(() {
              final groupId = _mappings[i]['conflictGroupId'] as String?;
              if (groupId != null) {
                for (final m in _mappings) {
                  if (m['conflictGroupId'] == groupId) m['accepted'] = false;
                }
              }
              _mappings[i]['accepted'] = true;
              _mappings[i]['_locationCity'] = city;
              _mappings[i]['_locationState'] = state;
              _mappings[i]['suggestedValue'] =
                  [city, state].where((s) => s.isNotEmpty).join(', ');
            });
          },
          onResolveDecision: (id, decision) {},
          onResolveUnplacedFinding: (id,
              {attachToEducationIndex, appendToExperienceIndex}) {},
          onResolveBulletMetric: (experienceIndex, bulletIndex, metricText) {},
          onResolveTimelineGap: (id, status) {},
          onApplyAll: () {},
          onCancel: () {},
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _locationConflictFixture() => [
      {
        'field': 'contact.location',
        'suggestedValue': 'Fort Hood, TX',
        'confidence': 0.9,
        'accepted': false,
        'conflict': true,
        'conflictGroupId': 'contact.location',
        'locationConflict': true,
        'sourceFile': 'stp.pdf',
        '_locationCity': 'Fort Hood',
        '_locationState': 'TX',
      },
      {
        'field': 'contact.location',
        'suggestedValue': 'Fort Bragg, NC',
        'confidence': 0.85,
        'accepted': false,
        'conflict': true,
        'conflictGroupId': 'contact.location',
        'locationConflict': true,
        'sourceFile': 'ncoer.pdf',
        '_locationCity': 'Fort Bragg',
        '_locationState': 'NC',
      },
      {
        'field': 'contact.location',
        'suggestedValue': '',
        'confidence': 0.0,
        'accepted': true,
        'conflict': true,
        'conflictGroupId': 'contact.location',
        'locationConflict': true,
        'manualEntry': true,
        'sourceFile': null,
        '_locationCity': '',
        '_locationState': '',
      },
    ];

void main() {
  testWidgets(
      'a third, always-present manual-entry row renders alongside both '
      'extracted candidates, styled the same way (same field label, same '
      'row type) — not hidden behind an extra tap', (tester) async {
    await tester.pumpWidget(_Harness(initialMappings: _locationConflictFixture()));

    expect(find.text('Location'), findsNWidgets(3),
        reason: 'all three options in the conflict group share the same '
            'row/label styling');
    expect(find.text('Fort Hood, TX'), findsOneWidget);
    expect(find.text('Fort Bragg, NC'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget,
        reason: 'exactly one manual text-entry field — the third option');
    expect(find.text('MANUAL'), findsOneWidget);
  });

  testWidgets(
      'the manual-entry option starts pre-selected — neither extracted '
      'candidate is pre-selected for contact address', (tester) async {
    final fixture = _locationConflictFixture();
    await tester.pumpWidget(_Harness(initialMappings: fixture));

    expect(fixture[0]['accepted'], isFalse,
        reason: 'STP candidate is not pre-selected — neither extracted '
            'candidate is guaranteed correct for this field');
    expect(fixture[1]['accepted'], isFalse,
        reason: 'NCOER candidate is not pre-selected either');
    expect(fixture[2]['accepted'], isTrue,
        reason: 'manual entry defaults to selected for contact.location');
  });

  testWidgets(
      'typing into the manual-entry field supplies its value and selects '
      'it, deselecting whichever extracted candidate was chosen before',
      (tester) async {
    final fixture = _locationConflictFixture();
    // Simulate a user having tapped the STP candidate first.
    fixture[0]['accepted'] = true;
    fixture[2]['accepted'] = false;
    await tester.pumpWidget(_Harness(initialMappings: fixture));

    await tester.enterText(find.byType(TextField), 'Denver, CO');
    await tester.pump();

    expect(fixture[2]['accepted'], isTrue,
        reason: 'typing into the manual field selects it within the '
            'conflict group');
    expect(fixture[0]['accepted'], isFalse,
        reason: 'the previously-selected extracted candidate is deselected '
            '— mutual exclusion still holds with the new manual option');
    expect(fixture[2]['_locationCity'], 'Denver');
    expect(fixture[2]['_locationState'], 'CO');
  });

  testWidgets(
      'selecting an extracted candidate after typing manually deselects '
      'the manual entry — the radio group treats all three as peers',
      (tester) async {
    final fixture = _locationConflictFixture();
    await tester.pumpWidget(_Harness(initialMappings: fixture));

    await tester.tap(find.text('Fort Bragg, NC'));
    await tester.pump();

    expect(fixture[1]['accepted'], isTrue);
    expect(fixture[2]['accepted'], isFalse,
        reason: 'the manual-entry option is deselected once a real '
            'candidate is chosen instead');
  });
}
