import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/resume_sanitizer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PRIORITY 6 — certifications must not be mixed with awards/recognition.
//
// Per the audit instructions, this is verified against a NON-military
// example first (retail) — not the military reproduction case — to prove
// the classification is general content reasoning (recognition-of-merit
// vs. certification-of-a-skill), not a career-field-specific term list.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('Extraction pipeline — retail award vs. food-safety credential', () {
    test('award_recognition is excluded, genuine credential survives', () {
      final json = jsonEncode({
        'contact': {'firstName': 'Test', 'lastName': 'User'},
        'summary': 'A summary.',
        'experience': <dynamic>[],
        'education': <dynamic>[],
        'skills': <dynamic>[],
        'certifications': [
          {
            'id': 'c1',
            'name': 'Employee of the Month',
            'issuer': 'Northgate Retail Co.',
            'dateEarned': 'March 2022',
            'certType': 'award_recognition',
          },
          {
            'id': 'c2',
            'name': 'ServSafe Food Handler Certification',
            'issuer': 'National Restaurant Association',
            'dateEarned': 'Jan 2021',
            'certType': 'credential',
          },
        ],
      });

      final result = CloudflareWorkerService.parseFieldMappings(json);
      final certRow =
          result.mappings.where((m) => m['field'] == 'certifications').toList();
      final certs = certRow.first['suggestedValue'] as List;

      expect(certs.any((c) => c['name'] == 'ServSafe Food Handler Certification'),
          isTrue);
      expect(certs.any((c) => c['name'] == 'Employee of the Month'), isFalse);
    });

    test('a sales performance award is excluded the same way a military '
        'medal would be — same classification, different field', () {
      final json = jsonEncode({
        'contact': {'firstName': 'Test', 'lastName': 'User'},
        'summary': 'A summary.',
        'experience': <dynamic>[],
        'education': <dynamic>[],
        'skills': <dynamic>[],
        'certifications': [
          {
            'id': 'c1',
            'name': "President's Club Award",
            'issuer': 'Meridian Sales Group',
            'dateEarned': '2023',
            'certType': 'award_recognition',
          },
        ],
      });

      final result = CloudflareWorkerService.parseFieldMappings(json);
      final certRow =
          result.mappings.where((m) => m['field'] == 'certifications').toList();

      expect(certRow, isEmpty,
          reason: 'the only certification provided was an award, so the '
              'field should not appear at all rather than showing an award '
              'as if it were a credential');
    });
  });

  group('Tailored-resume generation filter (GAP 2 mechanism, extended)', () {
    test('filterGeneratedCertifications excludes award_recognition, keeps '
        'credential and uncertain', () {
      final resumeJson = {
        'certifications': [
          {'name': 'Dean\'s List', 'certType': 'award_recognition'},
          {'name': 'Certified ScrumMaster', 'certType': 'credential'},
          {'name': 'Some Ambiguous Recognition', 'certType': 'uncertain'},
        ],
      };

      final result = ResumeSanitizer.filterGeneratedCertifications(resumeJson);
      final certs = result['certifications'] as List;

      expect(certs.length, 2);
      expect(certs.any((c) => c['name'] == 'Certified ScrumMaster'), isTrue);
      expect(certs.any((c) => c['name'] == 'Some Ambiguous Recognition'), isTrue);
      expect(certs.any((c) => c['name'] == 'Dean\'s List'), isFalse);
    });
  });

  group('classifyCertType', () {
    test('trusts an explicit award_recognition tag', () {
      expect(
        ResumeSanitizer.classifyCertType(
            {'name': 'Teacher of the Year', 'certType': 'award_recognition'}),
        'award_recognition',
      );
    });

    test('missing certType never falls back to award_recognition — only '
        'model classification can produce it (no keyword list)', () {
      // Even an obviously award-shaped name, with no certType provided,
      // must NOT be guessed into award_recognition by a fallback list —
      // it falls back to the existing credential/compliance_training check
      // only, per the fix's explicit "no keyword list for awards" design.
      final type = ResumeSanitizer.classifyCertType(
          {'name': 'Rookie of the Year Award'});
      expect(type, isNot('award_recognition'));
    });
  });
}
