import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/resume_sanitizer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PRIORITY 4 — education completion-aware dedup.
//
// Reproduction case was three "American Military University" entries for
// one degree (bare, completed, in-progress) — but the underlying problem
// (a degree extracted at multiple completeness levels from different
// document sections) applies to any school/program, so this uses a
// generic non-military university example.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('ResumeSanitizer.deduplicateEducation', () {
    test('bare + in-progress + completed for the same institution/degree '
        '→ only the completed entry survives', () {
      final entries = [
        {
          'id': 'e1',
          'degree': '',
          'institution': 'Riverside State University',
          'fieldOfStudy': '',
          'graduationYear': '',
          'gpa': null,
          'honors': null,
        },
        {
          'id': 'e2',
          'degree': 'Bachelor of Science',
          'institution': 'Riverside State University',
          'fieldOfStudy': 'Business Administration',
          'graduationYear': 'In Progress',
          'gpa': '3.94',
          'honors': null,
        },
        {
          'id': 'e3',
          'degree': 'Bachelor of Science',
          'institution': 'Riverside State University',
          'fieldOfStudy': 'Business Administration',
          'graduationYear': 'June 2026',
          'gpa': '3.9772',
          'honors': null,
        },
      ];

      final result = ResumeSanitizer.deduplicateEducation(entries);

      expect(result.length, 1,
          reason: 'all three entries describe one degree — only one must survive');
      final survivor = result.first as Map<String, dynamic>;
      expect(survivor['graduationYear'], 'June 2026');
      expect(survivor['gpa'], '3.9772',
          reason: 'the completed entry wins even though the in-progress '
              'sibling had a different (conflicting) GPA');
    });

    test('two distinct named degrees at the same institution are both kept '
        '(a Bachelor\'s and a later Master\'s are not the same enrollment)', () {
      final entries = [
        {
          'degree': 'Bachelor of Arts',
          'institution': 'Cedar Valley College',
          'fieldOfStudy': 'Psychology',
          'graduationYear': '2018',
        },
        {
          'degree': 'Master of Arts',
          'institution': 'Cedar Valley College',
          'fieldOfStudy': 'Clinical Psychology',
          'graduationYear': '2021',
        },
      ];

      final result = ResumeSanitizer.deduplicateEducation(entries);

      expect(result.length, 2,
          reason: 'two genuinely different degrees at the same school must '
              'never be collapsed into one');
    });

    test('bare stub with a completed entry, no in-progress sibling — bare '
        'is dropped', () {
      final entries = [
        {
          'degree': '',
          'institution': 'Northfield Community College',
          'graduationYear': '',
        },
        {
          'degree': 'Associate of Applied Science',
          'institution': 'Northfield Community College',
          'fieldOfStudy': 'Culinary Arts',
          'graduationYear': '2020',
          'gpa': '3.5',
        },
      ];

      final result = ResumeSanitizer.deduplicateEducation(entries);

      expect(result.length, 1);
      expect((result.first as Map)['gpa'], '3.5');
    });

    test('entries at different institutions are never merged', () {
      final entries = [
        {'degree': 'Bachelor of Science', 'institution': 'University A', 'graduationYear': '2020'},
        {'degree': 'Bachelor of Science', 'institution': 'University B', 'graduationYear': '2020'},
      ];
      final result = ResumeSanitizer.deduplicateEducation(entries);
      expect(result.length, 2);
    });
  });

  group('End-to-end via parseFieldMappings', () {
    test('the same bare/in-progress/completed shape resolves to one clean '
        'education entry through the full extraction pipeline', () {
      final json = jsonEncode({
        'contact': {'firstName': 'Test', 'lastName': 'User'},
        'summary': 'A summary.',
        'experience': <dynamic>[],
        'education': [
          {
            'id': 'e1',
            'degree': '',
            'institution': 'Meridian University',
            'fieldOfStudy': '',
            'graduationYear': '',
            'entryType': 'degree',
          },
          {
            'id': 'e2',
            'degree': 'Bachelor of Science',
            'institution': 'Meridian University',
            'fieldOfStudy': 'Information Technology',
            'graduationYear': 'Expected 2027',
            'gpa': '3.6',
            'entryType': 'degree',
          },
          {
            'id': 'e3',
            'degree': 'Bachelor of Science',
            'institution': 'Meridian University',
            'fieldOfStudy': 'Information Technology',
            'graduationYear': '2026',
            'gpa': '3.75',
            'entryType': 'degree',
          },
        ],
        'skills': <dynamic>[],
        'certifications': <dynamic>[],
      });

      final result = CloudflareWorkerService.parseFieldMappings(json);
      final eduRow =
          result.mappings.where((m) => m['field'] == 'education').toList();

      expect(eduRow, isNotEmpty);
      final entries = eduRow.first['suggestedValue'] as List;
      expect(entries.length, 1);
      expect(entries.first['graduationYear'], '2026');
      expect(entries.first['gpa'], '3.75');
    });
  });
}
