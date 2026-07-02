import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/services/resume_sanitizer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Covers the mechanisms in the military-bias generalization pass that
// entry_classification_test.dart doesn't exercise directly: bare-duplicate
// dedup, bullet-cap ranking, cross-document duplicate detection in
// isolation, and the structured certType filtering added for GAP 2
// (tailored-resume generation).
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('discardBareDuplicateExperience', () {
    test('bare stub (no company, no bullets) is discarded when a fuller '
        'entry with the same title exists', () {
      final entries = [
        {
          'title': 'Store Manager',
          'company': '',
          'bullets': <String>[],
          'startDate': '2021',
        },
        {
          'title': 'Store Manager',
          'company': 'Northgate Retail Co.',
          'bullets': ['Managed a team of 6 associates'],
          'startDate': '2021',
          'endDate': '2023',
        },
      ];

      final result = ResumeSanitizer.discardBareDuplicateExperience(entries);

      expect(result.length, 1);
      expect((result.first as Map)['company'], 'Northgate Retail Co.');
    });

    test('distinct full entries with the same title but different date '
        'ranges are NOT merged or discarded', () {
      final entries = [
        {
          'title': 'Software Engineer',
          'company': 'Fernwood Technologies',
          'bullets': ['Built the v1 API'],
          'startDate': '2018',
          'endDate': '2020',
        },
        {
          'title': 'Software Engineer',
          'company': 'Fernwood Technologies',
          'bullets': ['Led the v2 rewrite'],
          'startDate': '2022',
          'endDate': '2024',
        },
      ];

      final result = ResumeSanitizer.discardBareDuplicateExperience(entries);

      expect(result.length, 2,
          reason: 'two full entries must never be merged or discarded, '
              'even with the same title');
    });

    test('two bare stubs with the same title and no fuller entry are left '
        'alone (nothing safe to discard)', () {
      final entries = [
        {'title': 'Volunteer', 'company': '', 'bullets': <String>[]},
        {'title': 'Volunteer', 'company': '', 'bullets': <String>[]},
      ];
      final result = ResumeSanitizer.discardBareDuplicateExperience(entries);
      expect(result.length, 2);
    });
  });

  group('capBullets', () {
    test('entry under the cap is returned untouched', () {
      final bullets = ['One', 'Two', 'Three'];
      final result = ResumeSanitizer.capBullets(bullets, max: 6);
      expect(result, same(bullets));
    });

    test('entry over the cap is truncated to max, keeping the longest '
        'bullets in original relative order', () {
      final bullets = [
        'Short one', // 9 chars
        'A considerably longer and more detailed achievement bullet', // long
        'Mid length bullet with some detail', // mid
        'Tiny', // 4 chars
        'Another long and specific bullet describing a measurable outcome', // long
        'Also mid-length with reasonable detail here', // mid
        'X', // 1 char
      ];

      final result = ResumeSanitizer.capBullets(bullets, max: 3);

      expect(result.length, 3);
      // Lengths: idx1=58, idx2=34, idx3=4, idx4=64, idx5=43, idx0=9, idx6=1.
      // The 3 longest are idx4(64), idx1(58), idx5(43) — kept in original
      // relative (index-ascending) order: idx1, idx4, idx5.
      expect(result, [
        bullets[1],
        bullets[4],
        bullets[5],
      ]);
      // The shortest ones must be gone.
      expect(result.contains('X'), isFalse);
      expect(result.contains('Tiny'), isFalse);
      expect(result.contains('Short one'), isFalse);
    });

    test('default max is 6', () {
      final bullets = List.generate(10, (i) => 'Bullet number $i with some padding text');
      final result = ResumeSanitizer.capBullets(bullets);
      expect(result.length, 6);
    });
  });

  group('cross-document duplicate detection (non-military)', () {
    test('same civilian company (case/whitespace/legal-suffix variance) and '
        'title, incomplete date on one side → flagged', () {
      final a = {
        'title': 'Regional Sales Director',
        'company': 'redline logistics',
        'startDate': '2020',
        'endDate': null,
        'isCurrent': false,
      };
      final b = {
        'title': 'Regional Sales Director',
        'company': '  Redline   Logistics LLC',
        'startDate': '2020',
        'endDate': '2024',
        'isCurrent': false,
      };
      expect(ResumeSanitizer.isLikelyCrossDocumentDuplicateRole(a, b), isTrue);
    });

    test('hasCrossDocumentDuplicateRoles finds the pair in a larger list', () {
      final entries = [
        {
          'title': 'Financial Analyst',
          'company': 'Bishop & Cole Advisory',
          'startDate': '2018',
          'endDate': '2021',
          'isCurrent': false,
        },
        {
          'title': 'Senior Financial Analyst',
          'company': 'Redmark Capital Partners',
          'startDate': '2021',
          'endDate': null,
          'isCurrent': true,
        },
        {
          'title': 'Financial Analyst',
          'company': 'Bishop & Cole Advisory',
          'startDate': '2018',
          'endDate': null,
          'isCurrent': false,
        },
      ];
      expect(ResumeSanitizer.hasCrossDocumentDuplicateRoles(entries), isTrue);
    });
  });

  group('GAP 2 — structured certType filtering (tailored-resume generation)', () {
    test('classifyCertType trusts an explicit, valid certType', () {
      expect(
        ResumeSanitizer.classifyCertType({'name': 'PMP', 'certType': 'credential'}),
        'credential',
      );
      expect(
        ResumeSanitizer.classifyCertType(
            {'name': 'Annual Compliance Training', 'certType': 'compliance_training'}),
        'compliance_training',
      );
      expect(
        ResumeSanitizer.classifyCertType({'name': 'Something', 'certType': 'uncertain'}),
        'uncertain',
      );
    });

    test('classifyCertType falls back to keyword list when certType is '
        'missing or malformed, and does not crash', () {
      expect(
        ResumeSanitizer.classifyCertType({'name': 'Structured Self Development'}),
        'compliance_training',
        reason: 'matches the fallback keyword list',
      );
      expect(
        ResumeSanitizer.classifyCertType(
            {'name': 'AWS Certified Solutions Architect', 'certType': 'not_a_real_value'}),
        'credential',
        reason: 'malformed certType falls back to keyword list, which does '
            'not match a real credential name',
      );
    });

    test('filterGeneratedCertifications excludes compliance_training, '
        'keeps credential and uncertain, strips certType from output', () {
      final resumeJson = {
        'certifications': [
          {'name': 'AWS Certified Solutions Architect', 'certType': 'credential'},
          {'name': 'Annual Harassment Prevention Training', 'certType': 'compliance_training'},
          {'name': 'Some Ambiguous Course', 'certType': 'uncertain'},
        ],
      };

      final result = ResumeSanitizer.filterGeneratedCertifications(resumeJson);
      final certs = result['certifications'] as List;

      expect(certs.length, 2,
          reason: 'compliance_training excluded; credential and uncertain kept');
      expect(certs.any((c) => c['name'] == 'AWS Certified Solutions Architect'), isTrue);
      expect(certs.any((c) => c['name'] == 'Some Ambiguous Course'), isTrue,
          reason: 'uncertain defaults to INCLUDE at tailored-generation time — '
              'never silently dropped');
      expect(certs.any((c) => c['name'] == 'Annual Harassment Prevention Training'), isFalse);
      for (final c in certs) {
        expect((c as Map).containsKey('certType'), isFalse,
            reason: 'certType is a generation-time signal, not part of the output schema');
      }
    });
  });
}
