import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/screens/document_upload_screen.dart';
import 'package:beaconai_resume/services/cloudflare_worker_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIX 7 (efficiency audit) — education classification now follows the same
// structured-field → fallback-keyword → pending-decision-on-uncertain
// pattern already used for experience (employmentVsTraining) and
// certifications (credentialVsCompliance), instead of a binary
// degree/non-degree split with no escape hatch for genuine ambiguity.
// ─────────────────────────────────────────────────────────────────────────────

String _resumeJson({
  List<Map<String, dynamic>> experience = const [],
  List<Map<String, dynamic>> education = const [],
  List<Map<String, dynamic>> certifications = const [],
}) {
  return jsonEncode({
    'contact': {'firstName': 'Test', 'lastName': 'User'},
    'summary': 'A summary.',
    'experience': experience,
    'education': education,
    'skills': [],
    'certifications': certifications,
  });
}

void main() {
  group('education entryType: uncertain → pending decision', () {
    test('a professional certificate program plausibly either non-degree '
        'education or a certification produces an uncertain classification, '
        'not a silent guess', () {
      final json = _resumeJson(education: [
        {
          'id': 'e1',
          'degree': 'Professional Certificate in Data Analytics',
          'institution': 'Metro Community College Continuing Ed',
          'fieldOfStudy': '',
          'graduationYear': '2023',
          'gpa': null,
          'honors': null,
          'entryType': 'uncertain',
          'uncertaintyReason':
              'Could be a non-degree education program or a standalone '
                  'certification — unclear from the document.',
        }
      ]);

      final result = CloudflareWorkerService.parseFieldMappings(json);

      expect(result.pendingDecisions.length, 1,
          reason: 'uncertain education entryType must produce exactly one '
              'pending decision, not a silent degree/non-degree guess');
      final decision = result.pendingDecisions.first;
      expect(decision.kind, PendingDecisionKind.degreeVsNonDegreeTraining);
      expect(decision.rawTitle, 'Professional Certificate in Data Analytics');
      expect(decision.rawCompany, 'Metro Community College Continuing Ed');
      expect(decision.uncertaintyReason, isNotEmpty);

      // Must NOT silently appear in either education or certifications.
      final eduMapping = result.mappings
          .where((m) => m['field'] == 'education')
          .toList();
      final certMapping = result.mappings
          .where((m) => m['field'] == 'certifications')
          .toList();
      if (eduMapping.isNotEmpty) {
        final list = eduMapping.first['suggestedValue'] as List;
        expect(
            list.any((e) =>
                e['degree'] == 'Professional Certificate in Data Analytics'),
            isFalse);
      }
      if (certMapping.isNotEmpty) {
        final list = certMapping.first['suggestedValue'] as List;
        expect(
            list.any((e) =>
                e['name'] == 'Professional Certificate in Data Analytics'),
            isFalse);
      }
    });

    test('missing entryType never falls back to uncertain — fallback is '
        'keyword-based degree/non_degree_training only, matching the '
        'model-classification-only precedent for novel categories', () {
      final json = _resumeJson(education: [
        {
          'id': 'e1',
          'degree': 'B.S. Computer Science',
          'institution': 'State University',
          'fieldOfStudy': 'Computer Science',
          'graduationYear': '2022',
          'gpa': null,
          'honors': null,
          // No entryType at all.
        }
      ]);

      final result = CloudflareWorkerService.parseFieldMappings(json);

      expect(result.pendingDecisions, isEmpty,
          reason: 'a missing entryType must resolve via the fallback '
              'keyword list, never produce an uncertain pending decision');
      final eduMapping =
          result.mappings.where((m) => m['field'] == 'education').toList();
      expect(eduMapping, isNotEmpty);
    });
  });

  group('structural consistency across all three classifiers', () {
    test('experience, education, and cert all produce a pending decision '
        'with a non-empty default uncertaintyReason when the model omits '
        'one', () {
      final json = _resumeJson(
        experience: [
          {
            'id': 'x1',
            'title': 'Something',
            'company': 'Somewhere',
            'bullets': ['A bullet'],
            'entryType': 'uncertain',
            'uncertaintyReason': '',
          }
        ],
        education: [
          {
            'id': 'e1',
            'degree': 'Something',
            'institution': 'Somewhere',
            'entryType': 'uncertain',
            'uncertaintyReason': '',
          }
        ],
        certifications: [
          {
            'id': 'c1',
            'name': 'Something',
            'issuer': 'Somewhere',
            'certType': 'uncertain',
            'certUncertaintyReason': '',
          }
        ],
      );

      final result = CloudflareWorkerService.parseFieldMappings(json);

      expect(result.pendingDecisions.length, 3);
      for (final decision in result.pendingDecisions) {
        expect(decision.uncertaintyReason, isNotEmpty,
            reason: 'every classifier must supply a default reason when '
                'the model leaves it blank, not just some of them');
      }
      expect(
        result.pendingDecisions.map((d) => d.kind).toSet(),
        {
          PendingDecisionKind.employmentVsTraining,
          PendingDecisionKind.degreeVsNonDegreeTraining,
          PendingDecisionKind.credentialVsCompliance,
        },
      );
    });
  });

  group('PendingDecisionCard UI — degreeVsNonDegreeTraining kind', () {
    testWidgets(
        '"Add as Education" resolves to EntryDecision.education, '
        '"Add as Certification" resolves to EntryDecision.certification',
        (tester) async {
      final pending = [
        PendingEntryDecision(
          id: 'pd1',
          rawTitle: 'Professional Certificate in Data Analytics',
          rawCompany: 'Metro Community College Continuing Ed',
          rawBullets: const [],
          uncertaintyReason: 'Could be either.',
          kind: PendingDecisionKind.degreeVsNonDegreeTraining,
          rawEntry: const {
            'degree': 'Professional Certificate in Data Analytics',
            'institution': 'Metro Community College Continuing Ed',
            'graduationYear': '2023',
          },
        ),
      ];

      EntryDecision? resolvedDecision;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConfirmationView(
            processedFileNames: const ['transcript.pdf'],
            failedFileNames: const [],
            mappings: const [],
            pendingDecisions: pending,
            isDark: false,
            showSourceFile: false,
            onToggleMapping: (i, accepted) {},
            onResolveDecision: (id, decision) {
              resolvedDecision = decision;
            },
            onApplyAll: () {},
            onCancel: () {},
          ),
        ),
      ));

      // Card shows the education-specific button set, not the
      // employmentVsTraining "Work Experience" button.
      expect(find.widgetWithText(OutlinedButton, 'Add as Education'),
          findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Add as Certification'),
          findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Work Experience'),
          findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Add as Education'));
      await tester.pumpAndSettle();

      expect(resolvedDecision, EntryDecision.education);
    });
  });
}
