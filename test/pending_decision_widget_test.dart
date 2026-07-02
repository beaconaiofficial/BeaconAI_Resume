import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/screens/document_upload_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Verifies the Step 0 pending-decision UI's gating contract on the real
// ConfirmationView widget used by both the document-upload confirmation
// screen and the wizard's Path A prefill confirmation (same screen):
//   - Apply All stays disabled while any PendingEntryDecision is unresolved
//   - Apply All becomes available once every decision is resolved
//   - resolving a card always passes an explicit EntryDecision — dismissing
//     via "Don't include" resolves to exclude, never a silent include
// ─────────────────────────────────────────────────────────────────────────────

// Minimal harness reproducing the parent-owns-the-list pattern
// _DocumentUploadScreenState uses: ConfirmationView is stateless and driven
// entirely by state the parent rebuilds it with.
class _Harness extends StatefulWidget {
  const _Harness({required this.onResolved});
  final void Function(String id, EntryDecision decision) onResolved;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  List<PendingEntryDecision> _pending = [
    PendingEntryDecision(
      id: 'pd1',
      rawTitle: 'Full-Stack Web Development',
      rawCompany: 'General Assembly',
      rawBullets: const ['Completed a 12-week immersive curriculum'],
      uncertaintyReason: 'Not sure if this is a job or training.',
      kind: PendingDecisionKind.employmentVsTraining,
      rawEntry: const {
        'title': 'Full-Stack Web Development',
        'company': 'General Assembly',
        'startDate': '2024',
        'bullets': ['Completed a 12-week immersive curriculum'],
      },
    ),
  ];

  final List<Map<String, dynamic>> _mappings = [
    {
      'field': 'contact.firstName',
      'suggestedValue': 'Test',
      'confidence': 0.95,
      'accepted': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ConfirmationView(
          processedFileNames: const ['resume.pdf'],
          failedFileNames: const [],
          mappings: _mappings,
          pendingDecisions: _pending,
          isDark: false,
          showSourceFile: false,
          onToggleMapping: (i, accepted) {
            setState(() => _mappings[i]['accepted'] = accepted);
          },
          onResolveDecision: (id, decision) {
            widget.onResolved(id, decision);
            setState(() {
              _pending = _pending.where((d) => d.id != id).toList();
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
      'Apply All is disabled while a pending decision is unresolved, and '
      'enabled once resolved', (tester) async {
    String? resolvedId;
    EntryDecision? resolvedDecision;

    await tester.pumpWidget(_Harness(onResolved: (id, decision) {
      resolvedId = id;
      resolvedDecision = decision;
    }));

    // Pending card is visible.
    expect(find.text('Full-Stack Web Development · General Assembly'),
        findsOneWidget);

    // Apply All must be disabled while the card is unresolved.
    final applyButtonFinder =
        find.widgetWithText(ElevatedButton, 'Apply 1 Field');
    expect(applyButtonFinder, findsOneWidget);
    ElevatedButton applyButton = tester.widget(applyButtonFinder);
    expect(applyButton.onPressed, isNull,
        reason: 'Apply All must not be pressable while a decision is pending');

    // Resolve via "Don't include" — must resolve to EntryDecision.exclude,
    // never silently to include.
    await tester.tap(find.widgetWithText(TextButton, "Don't include"));
    await tester.pumpAndSettle();

    expect(resolvedId, 'pd1');
    expect(resolvedDecision, EntryDecision.exclude);

    // Card is gone, Apply All is now enabled.
    expect(find.text('Full-Stack Web Development · General Assembly'),
        findsNothing);
    applyButton = tester.widget(applyButtonFinder);
    expect(applyButton.onPressed, isNotNull,
        reason: 'Apply All must become available once every decision is resolved');
  });

  testWidgets('resolving via "Work Experience" passes EntryDecision.employment',
      (tester) async {
    EntryDecision? resolvedDecision;
    await tester.pumpWidget(_Harness(onResolved: (id, decision) {
      resolvedDecision = decision;
    }));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Work Experience'));
    await tester.pumpAndSettle();

    expect(resolvedDecision, EntryDecision.employment);
  });

  testWidgets('resolving via "Certification" passes EntryDecision.certification',
      (tester) async {
    EntryDecision? resolvedDecision;
    await tester.pumpWidget(_Harness(onResolved: (id, decision) {
      resolvedDecision = decision;
    }));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Certification'));
    await tester.pumpAndSettle();

    expect(resolvedDecision, EntryDecision.certification);
  });
}
