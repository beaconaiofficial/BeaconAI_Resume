import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/resume_sanitizer.dart';
import 'package:beaconai_resume/constants/sample_resume_data.dart';
import 'package:beaconai_resume/models/supporting_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Verifies the military-bias generalization pass:
//   - entryType/certType classification (model-driven, general fallback only)
//   - uncertain entries route to a PendingEntryDecision instead of being
//     silently guessed
//   - the same parseFieldMappings choke point is used regardless of source
//     document type, so this test doubles as proof text/DOCX/image/PDF paths
//     all get the same protection
//   - template preview personas no longer default non-military templates to
//     an Army-jargon persona
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

Map<String, dynamic>? _mappingValue(
    List<Map<String, dynamic>> mappings, String field) {
  final row = mappings.where((m) => m['field'] == field).toList();
  if (row.isEmpty) return null;
  return row.first;
}

void main() {
  group('1. Ambiguous non-military entry → pending decision, not a guess', () {
    test('bootcamp listed under experience with entryType uncertain', () {
      final json = _resumeJson(experience: [
        {
          'id': 'x1',
          'title': 'Full-Stack Web Development',
          'company': 'General Assembly',
          'location': 'Remote',
          'startDate': 'Jan 2024',
          'endDate': 'Apr 2024',
          'isCurrent': false,
          'bullets': ['Completed a 12-week immersive curriculum covering React and Node.js'],
          'entryType': 'uncertain',
          'uncertaintyReason': 'Bullets describe coursework, but company name looks like an employer.',
        }
      ]);

      final result = CloudflareWorkerService.parseFieldMappings(json);

      expect(result.pendingDecisions.length, 1,
          reason: 'uncertain entryType must produce exactly one pending decision');
      final decision = result.pendingDecisions.first;
      expect(decision.kind, PendingDecisionKind.employmentVsTraining);
      expect(decision.rawTitle, 'Full-Stack Web Development');
      expect(decision.rawCompany, 'General Assembly');
      expect(decision.uncertaintyReason, isNotEmpty);

      // Must NOT silently appear in either experience or certifications.
      final expRow = _mappingValue(result.mappings, 'experience');
      expect(expRow, isNull,
          reason: 'an uncertain entry must not be silently included as employment');
    });
  });

  group('2. Niche civilian medical credential survives the compliance filter', () {
    test('model-classified as credential', () {
      final json = _resumeJson(certifications: [
        {
          'id': 'c1',
          'name': 'Certified Phlebotomy Technician (CPT)',
          'issuer': 'ASCP',
          'dateEarned': 'May 2023',
          'certType': 'credential',
        }
      ]);
      final result = CloudflareWorkerService.parseFieldMappings(json);
      final certRow = _mappingValue(result.mappings, 'certifications');
      expect(certRow, isNotNull);
      final certs = certRow!['suggestedValue'] as List;
      expect(certs.any((c) => c['name'] == 'Certified Phlebotomy Technician (CPT)'),
          isTrue);
      expect(result.pendingDecisions, isEmpty);
    });

    test('fallback path (no certType) no longer matches medical terms', () {
      // Simulates an older/malformed model response with no certType field —
      // exercises the ResumeSanitizer fallback list directly.
      const medicalCertNames = [
        'Certified Surgical Technologist',
        'Registered Diagnostic Medical Sonographer (Ultrasound)',
        'Dental Assisting National Board Certification',
        'Radiologic Technologist (ARRT)',
        'X-Ray Certification',
      ];
      for (final name in medicalCertNames) {
        final matchesFallback = ResumeSanitizer.fallbackComplianceCertPatterns
            .any((p) => name.toLowerCase().contains(p));
        expect(matchesFallback, isFalse,
            reason: '"$name" must not be caught by the fallback compliance list');
      }

      final json = _resumeJson(certifications: [
        {
          'id': 'c2',
          'name': 'Certified Surgical Technologist',
          'issuer': 'NBSTSA',
          'dateEarned': 'Mar 2022',
          // no certType — forces the fallback path
        }
      ]);
      final result = CloudflareWorkerService.parseFieldMappings(json);
      final certRow = _mappingValue(result.mappings, 'certifications');
      expect(certRow, isNotNull);
      final certs = certRow!['suggestedValue'] as List;
      expect(certs.any((c) => c['name'] == 'Certified Surgical Technologist'), isTrue,
          reason: 'a real medical credential must survive the fallback path');
    });
  });

  group('3. Cross-document duplicate-role detection is no longer military-gated', () {
    test('civilian company, incomplete dates on one side → flagged', () {
      final fromResume = {
        'title': 'Store Manager',
        'company': 'Northgate Retail Co.',
        'startDate': '2021',
        'endDate': null,
        'isCurrent': false,
      };
      final fromReferenceLetter = {
        'title': 'Store Manager',
        'company': 'Northgate Retail Co.',
        'startDate': '2021',
        'endDate': '2023',
        'isCurrent': false,
      };
      expect(
        ResumeSanitizer.isLikelyCrossDocumentDuplicateRole(
            fromResume, fromReferenceLetter),
        isTrue,
      );
    });

    test('different companies → not flagged', () {
      final a = {
        'title': 'Store Manager',
        'company': 'Northgate Retail Co.',
        'startDate': '2021',
        'endDate': '2023',
        'isCurrent': false,
      };
      final b = {
        'title': 'Store Manager',
        'company': 'Southline Retail',
        'startDate': '2021',
        'endDate': '2023',
        'isCurrent': false,
      };
      expect(ResumeSanitizer.isLikelyCrossDocumentDuplicateRole(a, b), isFalse);
    });
  });

  group('4. Single choke point → DOCX/TXT/image paths get the same protection', () {
    test('parseFieldMappings is document-type agnostic', () {
      // DocumentUploadScreen routes DOCX/TXT/image/PDF (chunked and
      // single-call) extraction results through this exact function — see
      // _extractOneFile in document_upload_screen.dart. There is no
      // separate, unprotected path.
      final json = _resumeJson(experience: [
        {
          'id': 'x2',
          'title': 'Data Analytics Certificate',
          'company': 'Metro Community College Continuing Ed',
          'startDate': '2023',
          'endDate': '2023',
          'isCurrent': false,
          'bullets': ['Completed coursework in SQL and data visualization'],
          'entryType': 'education_training',
        }
      ]);
      final result = CloudflareWorkerService.parseFieldMappings(json);
      final expRow = _mappingValue(result.mappings, 'experience');
      expect(expRow, isNull, reason: 'training entry must not appear as employment');
      final certRow = _mappingValue(result.mappings, 'certifications');
      expect(certRow, isNotNull);
      final certs = certRow!['suggestedValue'] as List;
      expect(certs.any((c) => c['name'] == 'Data Analytics Certificate'), isTrue,
          reason: 'training entry must be promoted to certifications for ANY document type');
    });
  });

  group('5. Template preview personas', () {
    test('non-military personas contain no military jargon', () {
      const jargonTerms = ['COMSEC', 'ISYSCON', 'JNMS', 'MOS', 'PMCS'];
      final personas = {
        'marcusChen (Technical)': SampleResumeData.marcusChen,
        'elenaVasquez (Sharp)': SampleResumeData.elenaVasquez,
        'priyaNair (Sidebar)': SampleResumeData.priyaNair,
        'owenBennett (Pillar)': SampleResumeData.owenBennett,
        'mayaThompson (Entry)': SampleResumeData.mayaThompson,
      };
      for (final entry in personas.entries) {
        final allText = [
          entry.value.summary,
          ...entry.value.experience.expand((e) => [e.title, e.company, ...e.bullets]),
          ...entry.value.skills.map((s) => s.name),
        ].join(' ');
        for (final term in jargonTerms) {
          expect(allText.contains(term), isFalse,
              reason: '${entry.key} persona must not contain military jargon "$term"');
        }
      }
    });

    test('Veteran persona (Jane Rivera) is untouched and still military-flavored', () {
      final allText = [
        SampleResumeData.janeRivera.summary,
        ...SampleResumeData.janeRivera.experience.expand((e) => [e.title, e.company, ...e.bullets]),
        ...SampleResumeData.janeRivera.skills.map((s) => s.name),
      ].join(' ');
      expect(allText.contains('COMSEC'), isTrue);
    });
  });

  group('6. JST regression — military users still fully supported', () {
    test('employment MOS entry kept, credentialed course kept, compliance training dropped', () {
      final json = _resumeJson(
        experience: [
          {
            'id': 'e1',
            'title': 'Nodal Network Systems Operator-Maintainer',
            'company': 'US Army',
            'startDate': 'Jun 2019',
            'endDate': 'Aug 2022',
            'isCurrent': false,
            'bullets': ['Maintained tactical network infrastructure supporting 200+ users'],
            'entryType': 'employment',
          },
        ],
        certifications: [
          {
            'id': 'c1',
            'name': 'Nodal Network Systems Operator-Maintainer Course',
            'issuer': 'US Army Signal School',
            'dateEarned': '2019',
            'certType': 'credential',
          },
          {
            'id': 'c2',
            'name': 'Level I Antiterrorism Awareness Training',
            'issuer': 'US Army',
            'dateEarned': '2020',
            'certType': 'compliance_training',
          },
        ],
      );

      final result = CloudflareWorkerService.parseFieldMappings(json);

      final expRow = _mappingValue(result.mappings, 'experience');
      expect(expRow, isNotNull);
      final exp = expRow!['suggestedValue'] as List;
      expect(exp.any((e) => e['title'] == 'Nodal Network Systems Operator-Maintainer'),
          isTrue);

      final certRow = _mappingValue(result.mappings, 'certifications');
      expect(certRow, isNotNull);
      final certs = certRow!['suggestedValue'] as List;
      expect(certs.any((c) => c['name'].toString().contains('Nodal Network')), isTrue,
          reason: 'ACE-credited MOS course must survive as a credential');
      expect(certs.any((c) => c['name'].toString().contains('Antiterrorism')), isFalse,
          reason: 'compliance training must still be dropped for military users');
      expect(result.pendingDecisions, isEmpty);
    });
  });

  group('7. Title-based training fallback (real STP shape: duty title '
      '"RA Trainee", no company name signal)', () {
    test('a trainee-titled entry with no entryType and no training-pattern '
        'company name is still routed to certifications, not left as a '
        'standalone job', () {
      final json = _resumeJson(experience: [
        {
          'id': 'x1',
          'title': 'RA Trainee',
          'company': 'US Army',
          'startDate': '2019',
          'endDate': null,
          'isCurrent': false,
          'bullets': const [],
        },
      ]);

      final result = CloudflareWorkerService.parseFieldMappings(json);

      final expRow = _mappingValue(result.mappings, 'experience');
      expect(expRow, isNull,
          reason: 'the only experience entry was a trainee title and must '
              'have been promoted to certifications, not survive as a job');

      final certRow = _mappingValue(result.mappings, 'certifications');
      expect(certRow, isNotNull);
      final certs = certRow!['suggestedValue'] as List;
      expect(certs.any((c) => c['name'] == 'RA Trainee'), isTrue);
      expect(result.pendingDecisions, isEmpty);
    });

    test('a real job title is unaffected by the trainee-title fallback', () {
      final json = _resumeJson(experience: [
        {
          'id': 'x1',
          'title': 'Network Systems Engineer',
          'company': 'Acme Corp',
          'startDate': '2019',
          'endDate': '2022',
          'isCurrent': false,
          'bullets': ['Maintained enterprise network infrastructure'],
        },
      ]);

      final result = CloudflareWorkerService.parseFieldMappings(json);

      final expRow = _mappingValue(result.mappings, 'experience');
      expect(expRow, isNotNull);
      final exp = expRow!['suggestedValue'] as List;
      expect(exp.any((e) => e['title'] == 'Network Systems Engineer'), isTrue);
    });
  });

  group('8. .mil email flagged as an informational, non-blocking nudge', () {
    test('a .mil contact email is marked with milEmailWarning', () {
      final json = jsonEncode({
        'contact': {
          'firstName': 'Test',
          'lastName': 'User',
          'email': 'test.user@mail.mil',
        },
        'summary': '',
        'experience': <dynamic>[],
        'education': <dynamic>[],
        'skills': <dynamic>[],
        'certifications': <dynamic>[],
      });

      final result = CloudflareWorkerService.parseFieldMappings(json);

      final emailRow = _mappingValue(result.mappings, 'contact.email');
      expect(emailRow, isNotNull);
      expect(emailRow!['milEmailWarning'], isTrue);
      expect(emailRow['accepted'], isTrue,
          reason: 'the .mil flag is informational only and must not block '
              'the field from being accepted/applied');
    });

    test('a civilian email is not flagged', () {
      final json = jsonEncode({
        'contact': {
          'firstName': 'Test',
          'lastName': 'User',
          'email': 'test.user@gmail.com',
        },
        'summary': '',
        'experience': <dynamic>[],
        'education': <dynamic>[],
        'skills': <dynamic>[],
        'certifications': <dynamic>[],
      });

      final result = CloudflareWorkerService.parseFieldMappings(json);

      final emailRow = _mappingValue(result.mappings, 'contact.email');
      expect(emailRow, isNotNull);
      expect(emailRow!['milEmailWarning'], isNot(true));
    });
  });

  group('8b. documentType — Stage 1 source-of-truth priority prerequisite',
      () {
    test('a recognized documentType value round-trips onto the parse result',
        () {
      final json = jsonEncode({
        'documentType': 'stp',
        'contact': {'firstName': 'Test', 'lastName': 'User'},
        'summary': '',
        'experience': <dynamic>[],
        'education': <dynamic>[],
        'skills': <dynamic>[],
        'certifications': <dynamic>[],
      });

      final result = CloudflareWorkerService.parseFieldMappings(json);

      expect(result.documentType, 'stp');
    });

    test('a missing documentType parses to null rather than crashing', () {
      final json = jsonEncode({
        'contact': {'firstName': 'Test', 'lastName': 'User'},
        'summary': '',
        'experience': <dynamic>[],
        'education': <dynamic>[],
        'skills': <dynamic>[],
        'certifications': <dynamic>[],
      });

      final result = CloudflareWorkerService.parseFieldMappings(json);

      expect(result.documentType, isNull);
    });
  });

  group('9. Unplaced findings — a number/claim that does not cleanly map to '
      'a structured field', () {
    test('surfaces as an UnplacedFinding, not folded into the summary', () {
      final json = jsonEncode({
        'contact': {'firstName': 'Test', 'lastName': 'User'},
        'summary': 'A generalist with a strong academic record.',
        'experience': <dynamic>[],
        'education': <dynamic>[],
        'skills': <dynamic>[],
        'certifications': <dynamic>[],
        'unplacedFindings': [
          {
            'value': '3.94 GPA',
            'context': 'achieving the dean\'s list with a 3.94 GPA in '
                'Information Technology',
          },
        ],
      });

      final result = CloudflareWorkerService.parseFieldMappings(json);

      expect(result.unplacedFindings.length, 1);
      final finding = result.unplacedFindings.first;
      expect(finding.value, '3.94 GPA');
      expect(finding.context, contains('Information Technology'));
      expect(finding.id, isNotEmpty);
    });

    test('an empty unplacedFindings array produces no findings', () {
      final json = jsonEncode({
        'contact': {'firstName': 'Test', 'lastName': 'User'},
        'summary': '',
        'experience': <dynamic>[],
        'education': <dynamic>[],
        'skills': <dynamic>[],
        'certifications': <dynamic>[],
        'unplacedFindings': <dynamic>[],
      });

      final result = CloudflareWorkerService.parseFieldMappings(json);

      expect(result.unplacedFindings, isEmpty);
    });

    test('a finding with an empty value is dropped rather than surfaced as '
        'a blank card', () {
      final json = jsonEncode({
        'contact': {'firstName': 'Test', 'lastName': 'User'},
        'summary': '',
        'experience': <dynamic>[],
        'education': <dynamic>[],
        'skills': <dynamic>[],
        'certifications': <dynamic>[],
        'unplacedFindings': [
          {'value': '', 'context': 'some context with no real value'},
        ],
      });

      final result = CloudflareWorkerService.parseFieldMappings(json);

      expect(result.unplacedFindings, isEmpty);
    });
  });

  group('10. Bullets extracted as objects (text + hasQuantifiableData)', () {
    test('a bullet with hasQuantifiableData: false survives extraction '
        'and is not discarded', () {
      final json = _resumeJson(experience: [
        {
          'id': 'e1',
          'title': 'Network Systems Engineer',
          'company': 'Acme Corp',
          'startDate': '2019',
          'endDate': '2022',
          'isCurrent': false,
          'bullets': [
            {
              'text': 'Maintained enterprise network infrastructure',
              'hasQuantifiableData': false,
            },
            {
              'text': 'Reduced downtime by 40% across 12 data centers',
              'hasQuantifiableData': true,
            },
          ],
        },
      ]);

      final result = CloudflareWorkerService.parseFieldMappings(json);

      final expRow = _mappingValue(result.mappings, 'experience');
      expect(expRow, isNotNull);
      final exp = expRow!['suggestedValue'] as List;
      final bullets = (exp.first as Map)['bullets'] as List;
      expect(bullets.length, 2);
      expect((bullets[0] as Map)['hasQuantifiableData'], isFalse);
      expect((bullets[1] as Map)['hasQuantifiableData'], isTrue);
    });
  });
}
