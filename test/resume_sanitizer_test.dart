import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
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
    Map<String, dynamic> bulletMap(String text) =>
        {'text': text, 'hasQuantifiableData': true};

    test('entry under the cap is returned untouched', () {
      final bullets = ['One', 'Two', 'Three'].map(bulletMap).toList();
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
      ].map(bulletMap).toList();

      final result = ResumeSanitizer.capBullets(bullets, max: 3);
      final resultTexts = result.map((b) => b['text']).toList();

      expect(result.length, 3);
      // Lengths: idx1=58, idx2=34, idx3=4, idx4=64, idx5=43, idx0=9, idx6=1.
      // The 3 longest are idx4(64), idx1(58), idx5(43) — kept in original
      // relative (index-ascending) order: idx1, idx4, idx5.
      expect(resultTexts, [
        bullets[1]['text'],
        bullets[4]['text'],
        bullets[5]['text'],
      ]);
      // The shortest ones must be gone.
      expect(resultTexts.contains('X'), isFalse);
      expect(resultTexts.contains('Tiny'), isFalse);
      expect(resultTexts.contains('Short one'), isFalse);
    });

    test('default max is 6', () {
      final bullets = List.generate(
              10, (i) => 'Bullet number $i with some padding text')
          .map(bulletMap)
          .toList();
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

  group('companiesAreLikelyTheSame (general fuzzy org-name matching)', () {
    test('acronym vs. spelled-out form matches — "US Army" / "United '
        'States Army"', () {
      expect(
        ResumeSanitizer.companiesAreLikelyTheSame(
            'US Army', 'United States Army'),
        isTrue,
      );
    });

    test('abbreviated vs. full legal suffix matches — "Acme Corp" / "Acme '
        'Corporation" (proves this isn\'t military-specific)', () {
      expect(
        ResumeSanitizer.companiesAreLikelyTheSame(
            'Acme Corp', 'Acme Corporation'),
        isTrue,
      );
    });

    test('genuinely different companies do not match', () {
      expect(
        ResumeSanitizer.companiesAreLikelyTheSame(
            'Acme Corp', 'Zenith Industries'),
        isFalse,
      );
    });
  });

  group('mergeCrossDocumentDuplicateRoles (FIX D — auto-merge, not just flag)',
      () {
    List<String> bulletTexts(dynamic mergedBullets) => (mergedBullets as List)
        .map((b) => (b as Map<String, dynamic>)['text'] as String)
        .toList();
    test('same title, near-duplicate company via acronym, overlapping '
        'open-ended dates — the exact shape from the real log — merges '
        'into one entry with bullets from both', () {
      final entries = [
        {
          'title': 'Nodal Network Systems Operator-Maintainer',
          'company': 'US Army',
          'startDate': '2019-09-26',
          'endDate': null,
          'isCurrent': true,
          'bullets': ['Maintained nodal network switching systems'],
        },
        {
          'title': 'Nodal Network Systems Operator-Maintainer',
          'company': 'United States Army',
          'startDate': '16-MAR-2018',
          'endDate': null,
          'isCurrent': true,
          'bullets': ['Operated tactical communications equipment'],
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1,
          reason: 'both entries describe the same real-world role and must '
              'collapse into one, not survive as two separate resume '
              'entries');
      final merged = result.first as Map<String, dynamic>;
      expect(merged['startDate'], '16-MAR-2018',
          reason: 'the earlier start date wins');
      expect(merged['isCurrent'], isTrue);
      expect(
        bulletTexts(merged['bullets']),
        containsAll([
          'Maintained nodal network switching systems',
          'Operated tactical communications equipment',
        ]),
        reason: 'bullets from both source entries must survive the merge',
      );
    });

    test('same title, same company, genuinely non-overlapping dates — two '
        'distinct roles at different times — are NOT merged', () {
      final entries = [
        {
          'title': 'Sales Associate',
          'company': 'Meridian Retail Group',
          'startDate': '2015',
          'endDate': '2017',
          'isCurrent': false,
          'bullets': ['Worked the electronics department'],
        },
        {
          'title': 'Sales Associate',
          'company': 'Meridian Retail Group',
          'startDate': '2021',
          'endDate': '2023',
          'isCurrent': false,
          'bullets': ['Rehired seasonally for the home goods department'],
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 2,
          reason: 'two genuinely distinct stints at different times must '
              'never be collapsed into one — a legitimate re-hire sequence, '
              'not a duplicate');
    });

    test('non-military fixture: "Acme Corp" vs "Acme Corporation" with an '
        'overlapping role merges — proves the fuzzy company matching isn\'t '
        'accidentally military-specific', () {
      final entries = [
        {
          'title': 'Operations Manager',
          'company': 'Acme Corp',
          'startDate': '2019',
          'endDate': '2022',
          'isCurrent': false,
          'bullets': ['Oversaw daily warehouse operations'],
        },
        {
          'title': 'Operations Manager',
          'company': 'Acme Corporation',
          'startDate': '2020',
          'endDate': '2023',
          'isCurrent': false,
          'bullets': ['Managed a team of 12 warehouse staff'],
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1);
      final merged = result.first as Map<String, dynamic>;
      expect(merged['startDate'], '2019');
      expect(merged['endDate'], '2023');
      expect(
        bulletTexts(merged['bullets']),
        containsAll([
          'Oversaw daily warehouse operations',
          'Managed a team of 12 warehouse staff',
        ]),
      );
    });

    test('an incomplete-date-only match (the weaker signal) is left alone '
        'for manual review rather than auto-merged', () {
      // Same company + title, but neither a real date overlap nor an
      // incomplete-date fallback trigger here — both sides are fully dated
      // and genuinely don't overlap, so this must NOT merge (covered above)
      // — this test instead confirms a single incomplete-date-only pair
      // still passes through mergeCrossDocumentDuplicateRoles unmerged,
      // since _isConfidentCrossDocumentDuplicateRole requires a real
      // overlap, not just "one side is missing an end date".
      final entries = [
        {
          'title': 'Project Coordinator',
          'company': 'Whitfield Consulting',
          'startDate': '2016',
          'endDate': null,
          'isCurrent': false,
          'bullets': ['Coordinated cross-team deliverables'],
        },
        {
          'title': 'Project Coordinator',
          'company': 'Whitfield Consulting',
          'startDate': '2019',
          'endDate': '2021',
          'isCurrent': false,
          'bullets': ['Managed vendor relationships'],
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 2,
          reason: 'an incomplete date alone is not confident enough to '
              'auto-merge — this pair should still be surfaced via '
              'hasCrossDocumentDuplicateRoles for the user to decide, not '
              'silently combined');
      expect(ResumeSanitizer.hasCrossDocumentDuplicateRoles(entries), isTrue);
    });

    test('real JST shape: same title, both sides a single IDENTICAL award '
        'date, no company field at all — merges (previously survived as '
        'two entries since sa < eb was false for equal years)', () {
      final entries = [
        {
          'title': 'Nodal Network Systems Operator-Maintainer',
          'company': '',
          'startDate': '26-SEP-2019',
          'endDate': null,
          'isCurrent': false,
          'bullets': ['Installed and maintained nodal network components'],
        },
        {
          'title': 'Nodal Network Systems Operator-Maintainer',
          'company': '',
          'startDate': '26-SEP-2019',
          'endDate': null,
          'isCurrent': false,
          'bullets': ['Supervised nodal communications security operations'],
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1,
          reason: 'two JST skill-level entries for the same duty title, '
              'both stamped with the identical single "Dates Held" value, '
              'describe one real assignment');
      final merged = result.first as Map<String, dynamic>;
      expect(
        bulletTexts(merged['bullets']),
        containsAll([
          'Installed and maintained nodal network components',
          'Supervised nodal communications security operations',
        ]),
      );
    });

    test('single incomplete award date falling INSIDE a same-title/company '
        'full range merges (STP single-date row vs. a fuller assignment '
        'range for the same role)', () {
      final entries = [
        {
          'title': 'Motor Transport Operator',
          'company': 'US Army',
          'startDate': '2019',
          'endDate': null,
          'isCurrent': false,
          'bullets': ['Completed initial qualification'],
        },
        {
          'title': 'Motor Transport Operator',
          'company': 'US Army',
          'startDate': '2018',
          'endDate': '2020',
          'isCurrent': false,
          'bullets': ['Operated tractor-trailers over varied terrain'],
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1);
    });

    test('same title, same GENUINE re-hire shape (both full ranges, real '
        'gap, no incomplete-date side) is still NOT merged — the fix must '
        'not weaken the existing promotion/re-hire protection', () {
      final entries = [
        {
          'title': 'Sales Associate',
          'company': 'Meridian Retail Group',
          'startDate': '2015',
          'endDate': '2017',
          'isCurrent': false,
          'bullets': ['Worked the electronics department'],
        },
        {
          'title': 'Sales Associate',
          'company': 'Meridian Retail Group',
          'startDate': '2021',
          'endDate': '2023',
          'isCurrent': false,
          'bullets': ['Rehired seasonally for the home goods department'],
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 2);
    });

    test('single incomplete award date far outside a same-title/company '
        'range (multi-year gap) is NOT merged', () {
      final entries = [
        {
          'title': 'Project Coordinator',
          'company': 'Whitfield Consulting',
          'startDate': '2016',
          'endDate': null,
          'isCurrent': false,
          'bullets': ['Coordinated cross-team deliverables'],
        },
        {
          'title': 'Project Coordinator',
          'company': 'Whitfield Consulting',
          'startDate': '2021',
          'endDate': '2023',
          'isCurrent': false,
          'bullets': ['Managed vendor relationships'],
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 2,
          reason: 'a multi-year gap between a single date and an unrelated '
              'later range is not confident enough to auto-merge');
    });
  });

  group('fallbackTrainingTitlePatterns (title-based training signal)', () {
    test('a title containing "trainee" is present in the fallback list '
        '(STP real-log shape: duty title "TC RA TRAINEE")', () {
      expect(
        ResumeSanitizer.fallbackTrainingTitlePatterns
            .any((p) => 'tc ra trainee'.contains(p)),
        isTrue,
      );
    });

    test('an ordinary job title does not match any training title pattern',
        () {
      expect(
        ResumeSanitizer.fallbackTrainingTitlePatterns
            .any((p) => 'network systems engineer'.contains(p)),
        isFalse,
      );
    });
  });

  group('deduplicateEducation — genuine conflict between two COMPLETED '
      'entries is surfaced, not silently resolved', () {
    test('two entries with real (non-"in progress") completion dates that '
        'disagree on GPA are both returned, flagged, instead of one being '
        'silently picked', () {
      final entries = [
        {
          'degree': 'Bachelor of Science',
          'institution': 'American Military University',
          'fieldOfStudy': 'Information Technology',
          'graduationYear': 'June 2026',
          'gpa': '3.9772',
        },
        {
          'degree': 'Bachelor of Science',
          'institution': 'American Military University',
          'fieldOfStudy': 'Information Technology',
          'graduationYear': 'May 2026',
          'gpa': '3.94',
        },
      ];

      final result = ResumeSanitizer.deduplicateEducation(entries);

      expect(result.length, 2,
          reason: 'both completed entries disagree on GPA — a real '
              'conflict between two supposedly-final records, not the '
              'completed-vs-in-progress case, so neither should be '
              'silently discarded');
      expect(
        result.every((e) => (e as Map<String, dynamic>)['educationConflict'] == true),
        isTrue,
      );
    });

    test('completed entry beating an in-progress sibling with a different '
        'GPA is still resolved silently (unchanged behavior — not a real '
        'conflict, an expected snapshot-vs-final difference)', () {
      final entries = [
        {
          'degree': 'Bachelor of Science',
          'institution': 'Riverside State University',
          'fieldOfStudy': 'Business Administration',
          'graduationYear': 'In Progress',
          'gpa': '3.94',
        },
        {
          'degree': 'Bachelor of Science',
          'institution': 'Riverside State University',
          'fieldOfStudy': 'Business Administration',
          'graduationYear': 'June 2026',
          'gpa': '3.9772',
        },
      ];

      final result = ResumeSanitizer.deduplicateEducation(entries);

      expect(result.length, 1);
      final survivor = result.first as Map<String, dynamic>;
      expect(survivor['gpa'], '3.9772');
      expect(survivor['educationConflict'], isNot(true));
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

  group('parseSourceDocType', () {
    test('recognizes every documented value', () {
      expect(ResumeSanitizer.parseSourceDocType('stp'), SourceDocType.stp);
      expect(ResumeSanitizer.parseSourceDocType('ncoer'), SourceDocType.ncoer);
      expect(ResumeSanitizer.parseSourceDocType('jst'), SourceDocType.jst);
      expect(ResumeSanitizer.parseSourceDocType('transcript'),
          SourceDocType.transcript);
      expect(ResumeSanitizer.parseSourceDocType('civilian_resume'),
          SourceDocType.civilianResume);
    });

    test('is case/whitespace tolerant', () {
      expect(ResumeSanitizer.parseSourceDocType('  STP  '), SourceDocType.stp);
    });

    test('null, empty, "other", and unrecognized values all parse to null '
        '— never participate in priority tie-breaking', () {
      expect(ResumeSanitizer.parseSourceDocType(null), isNull);
      expect(ResumeSanitizer.parseSourceDocType(''), isNull);
      expect(ResumeSanitizer.parseSourceDocType('other'), isNull);
      expect(ResumeSanitizer.parseSourceDocType('cover_letter'), isNull);
    });

    test('Stage 8 — recognizes the new document-type-taxonomy values, '
        'not other/null', () {
      expect(ResumeSanitizer.parseSourceDocType('award_recommendation'),
          SourceDocType.awardRecommendation);
      expect(ResumeSanitizer.parseSourceDocType('equipment_qualification'),
          SourceDocType.equipmentQualification);
      expect(ResumeSanitizer.parseSourceDocType('training_certificate'),
          SourceDocType.trainingCertificate);
    });
  });

  group('mergeCrossDocumentDuplicateRoles — Stage 1 source-of-truth priority '
      '(STP > NCOER > JST for dates/station; NCOER > JST > STP for '
      'narrative identity)', () {
    test('STP duty station wins over NCOER when they genuinely disagree, '
        'even though the STP side has fewer bullets (proves it is doc-type '
        'driven, not the old bullet-count heuristic)', () {
      final entries = [
        {
          'title': 'Network Communications Systems Operator',
          'company': 'U.S. Army',
          'location': 'Fort Hood, TX',
          'startDate': '2019',
          'endDate': null,
          'isCurrent': true,
          'bullets': ['Managed the current assignment\'s network operations'],
          '_sourceDocType': 'stp',
        },
        {
          'title': 'Network Communications Systems Operator',
          'company': 'U.S. Army',
          'location': 'Fort Bragg, NC',
          'startDate': '2019',
          'endDate': null,
          'isCurrent': true,
          'bullets': [
            'Led a team of 6 in daily network operations',
            'Reduced outage response time by 30%',
          ],
          '_sourceDocType': 'ncoer',
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1);
      final merged = result.first as Map<String, dynamic>;
      expect(merged['location'], 'Fort Hood, TX',
          reason: 'STP outranks NCOER for duty station per the source '
              'priority table, even though the NCOER side has more bullets');
    });

    test('NCOER duty narrative donates title/company identity over a JST '
        'with more bullets (narrative priority, not bullet count)', () {
      // Titles/companies must be equal (case-insensitively) or fuzzy-matched
      // to enter the merge path at all — normalizeTitle is a literal
      // lowercase/trim, not fuzzy. So the observable proof of "who donates
      // identity" is CASING: the NCOER side's well-formatted casing must
      // survive even though the JST side has more bullets.
      final entries = [
        {
          'title': 'Supply Chain Coordinator',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2019',
          'endDate': null,
          'isCurrent': true,
          'bullets': ['Led a team of 6 through a major systems migration'],
          '_sourceDocType': 'ncoer',
        },
        {
          'title': 'SUPPLY CHAIN COORDINATOR',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2019',
          'endDate': null,
          'isCurrent': true,
          'bullets': [
            'Generic MOS description bullet one',
            'Generic MOS description bullet two',
            'Generic MOS description bullet three',
          ],
          '_sourceDocType': 'jst',
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1);
      final merged = result.first as Map<String, dynamic>;
      expect(merged['title'], 'Supply Chain Coordinator',
          reason: 'NCOER outranks JST for duty narrative/identity even '
              'though the JST side has more bullets — its casing must '
              'survive, not the all-caps JST version');
    });

    test('when doc type is unknown/missing on either side, falls back to '
        'the pre-existing bullet-count heuristic unchanged', () {
      final entries = [
        {
          'title': 'Operations Manager',
          'company': 'Acme Corp',
          'location': 'Springfield, IL',
          'startDate': '2019',
          'endDate': '2022',
          'isCurrent': false,
          'bullets': ['One bullet only'],
        },
        {
          'title': 'OPERATIONS MANAGER',
          'company': 'Acme Corporation',
          'location': 'Chicago, IL',
          'startDate': '2019',
          'endDate': '2022',
          'isCurrent': false,
          'bullets': ['First bullet', 'Second bullet'],
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1);
      final merged = result.first as Map<String, dynamic>;
      expect(merged['title'], 'OPERATIONS MANAGER',
          reason: 'neither side has a known document type, so the merge '
              'falls back to the original "more bullets wins" heuristic');
      expect(merged['location'], 'Chicago, IL');
    });

    test('when only one side has a location, it always survives regardless '
        'of document type (never silently dropped)', () {
      final entries = [
        {
          'title': 'Supply Chain Coordinator',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2019',
          'endDate': null,
          'isCurrent': true,
          'bullets': ['Coordinated logistics for a battalion-sized element'],
          '_sourceDocType': 'jst',
        },
        {
          'title': 'Supply Chain Coordinator',
          'company': 'U.S. Army',
          'location': 'Fort Campbell, KY',
          'startDate': '2019',
          'endDate': null,
          'isCurrent': true,
          'bullets': ['Managed a \$2M equipment inventory'],
          '_sourceDocType': 'stp',
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1);
      expect((result.first as Map<String, dynamic>)['location'],
          'Fort Campbell, KY');
    });
  });

  group('mergeCrossDocumentDuplicateRoles — Stage 8 award-recommendation '
      'is a PEER of NCOER for duty narrative, not subordinate', () {
    test('a DA-638-shaped award-recommendation entry and an NCOER entry for '
        'the same role/period cluster and combine — both sides\' bullets '
        'survive, neither silently outranks the other', () {
      final entries = [
        {
          'title': 'Supply Chain Coordinator',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2020',
          'endDate': '2021',
          'isCurrent': false,
          'bullets': ['Led a team of 6 through a major systems migration'],
          '_sourceDocType': 'ncoer',
        },
        {
          'title': 'Supply Chain Coordinator',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2020',
          'endDate': '2021',
          'isCurrent': false,
          'bullets': [
            'Directed a \$4.2M equipment modernization effort across 3 '
                'battalions, cutting fielding time by 40%',
          ],
          '_sourceDocType': 'award_recommendation',
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1,
          reason: 'same title/company/date-range — must cluster into one '
              'entry rather than surviving as two duplicates');
      final merged = result.first as Map<String, dynamic>;
      final bulletTexts =
          (merged['bullets'] as List<dynamic>)
              .map((b) => (b as Map<String, dynamic>)['text'] as String)
              .toList();
      expect(
        bulletTexts,
        containsAll([
          'Led a team of 6 through a major systems migration',
          'Directed a \$4.2M equipment modernization effort across 3 '
              'battalions, cutting fielding time by 40%',
        ]),
        reason: 'award-recommendation content must reach the same '
            'clustering/combination path as NCOER content for the same '
            'role — neither source silently outranks or drops the other',
      );
    });

    test('when NCOER and award-recommendation tie (same priority tier) and '
        'genuinely disagree on identity text, falls back to the '
        'more-bullets heuristic instead of either doc type auto-winning',
        () {
      final entries = [
        {
          'title': 'Supply Chain Coordinator',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2020',
          'endDate': '2021',
          'isCurrent': false,
          'bullets': ['One NCOER bullet'],
          '_sourceDocType': 'ncoer',
        },
        {
          'title': 'SUPPLY CHAIN COORDINATOR',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2020',
          'endDate': '2021',
          'isCurrent': false,
          'bullets': [
            'First award-recommendation bullet',
            'Second award-recommendation bullet',
          ],
          '_sourceDocType': 'award_recommendation',
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1);
      final merged = result.first as Map<String, dynamic>;
      expect(merged['title'], 'SUPPLY CHAIN COORDINATOR',
          reason: 'ncoer and award_recommendation share the same duty-'
              'narrative priority tier, so there is no doc-type tie-break '
              'between them — identity falls back to whichever side has '
              'more bullets, exactly as when both sides are unknown');
    });
  });

  group('deduplicateEducation — Stage 1 source priority breaks equally-'
      'detailed ties (Transcript > STP > NCOER)', () {
    test('a transcript entry wins over an equally-detailed STP entry for '
        'the same completed degree', () {
      final entries = [
        {
          'degree': 'Bachelor of Science',
          'institution': 'American Military University',
          'fieldOfStudy': 'Information Technology',
          'graduationYear': 'June 2026',
          'gpa': '3.94',
          '_sourceDocType': 'stp',
        },
        {
          'degree': 'Bachelor of Science',
          'institution': 'American Military University',
          'fieldOfStudy': 'Information Technology',
          'graduationYear': 'June 2026',
          'gpa': '3.94',
          '_sourceDocType': 'transcript',
        },
      ];

      final result = ResumeSanitizer.deduplicateEducation(entries);

      expect(result.length, 1);
      expect((result.first as Map<String, dynamic>)['_sourceDocType'],
          'transcript',
          reason: 'both entries score identically on detail — the '
              'transcript is the authoritative source for education and '
              'must win the tie, not entry order');
    });

    test('a genuine GPA conflict between two completed entries is still '
        'surfaced (not silently auto-resolved by source priority)', () {
      final entries = [
        {
          'degree': 'Bachelor of Science',
          'institution': 'American Military University',
          'fieldOfStudy': 'Information Technology',
          'graduationYear': 'June 2026',
          'gpa': '3.9772',
          '_sourceDocType': 'stp',
        },
        {
          'degree': 'Bachelor of Science',
          'institution': 'American Military University',
          'fieldOfStudy': 'Information Technology',
          'graduationYear': 'May 2026',
          'gpa': '3.94',
          '_sourceDocType': 'transcript',
        },
      ];

      final result = ResumeSanitizer.deduplicateEducation(entries);

      expect(result.length, 2,
          reason: 'a genuine GPA disagreement between two completed '
              'records is surfaced to the user regardless of source '
              'priority — source priority only breaks ties with no '
              'genuine conflict');
      expect(
        result.every(
            (e) => (e as Map<String, dynamic>)['educationConflict'] == true),
        isTrue,
      );
    });
  });

  group('detectLocationConflict — home-of-record vs. duty-station address '
      'conflict', () {
    test('a genuine location conflict is flagged, and the more-authoritative '
        '(STP) source is pre-selected over an NCOER', () {
      final result = ResumeSanitizer.detectLocationConflict([
        {
          'sourceFile': 'ncoer.pdf',
          'city': 'Fort Benning',
          'state': 'Georgia',
          'documentType': 'ncoer',
        },
        {
          'sourceFile': 'stp.pdf',
          'city': 'Colorado Springs',
          'state': 'CO',
          'documentType': 'stp',
        },
      ]);

      expect(result, isNotNull,
          reason: 'Fort Benning, GA and Colorado Springs, CO are genuinely '
              'different locations — a real conflict, not a formatting '
              'difference');
      expect(result!.length, 2);

      final preferred = result.singleWhere((c) => c['isPreferred'] == true);
      expect(preferred['city'], 'Colorado Springs',
          reason: 'STP outranks NCOER for the current-location default, '
              'per the same authority order as duty-station merging');
      expect(preferred['state'], 'CO');

      final other = result.singleWhere((c) => c['isPreferred'] != true);
      expect(other['city'], 'Fort Benning',
          reason: 'the non-selected address must remain present as the '
              'visible alternate, not dropped');
    });

    test('a trivial formatting difference — abbreviation, punctuation, '
        'whitespace — does not trigger a false-positive conflict', () {
      final result = ResumeSanitizer.detectLocationConflict([
        {
          'sourceFile': 'a.pdf',
          'city': 'Ft. Benning',
          'state': 'Georgia',
          'documentType': 'stp',
        },
        {
          'sourceFile': 'b.pdf',
          'city': 'Fort   Benning',
          'state': 'GA',
          'documentType': 'ncoer',
        },
      ]);

      expect(result, isNull,
          reason: '"Ft. Benning, Georgia" and "Fort Benning, GA" are the '
              'same real-world location once normalized — must not be '
              'flagged as a conflict just because the raw strings differ');
    });

    test('"CO" vs "Colorado" specifically does not conflict — the exact '
        'false-positive case called out during review', () {
      final result = ResumeSanitizer.detectLocationConflict([
        {
          'sourceFile': 'a.pdf',
          'city': 'Denver',
          'state': 'CO',
          'documentType': 'stp',
        },
        {
          'sourceFile': 'b.pdf',
          'city': 'Denver',
          'state': 'Colorado',
          'documentType': 'ncoer',
        },
      ]);

      expect(result, isNull);
    });

    test('a single address (only one file, or every file agrees) produces '
        'no conflict — unaffected by this detection', () {
      expect(
        ResumeSanitizer.detectLocationConflict([
          {
            'sourceFile': 'only.pdf',
            'city': 'Fort Benning',
            'state': 'GA',
            'documentType': 'stp',
          },
        ]),
        isNull,
        reason: 'fewer than 2 addresses — nothing to conflict with',
      );

      expect(
        ResumeSanitizer.detectLocationConflict([
          {
            'sourceFile': 'a.pdf',
            'city': 'Fort Benning',
            'state': 'GA',
            'documentType': 'stp',
          },
          {
            'sourceFile': 'b.pdf',
            'city': 'Fort Benning',
            'state': 'GA',
            'documentType': 'ncoer',
          },
        ]),
        isNull,
        reason: 'every file reports the same address — not a conflict',
      );
    });

    test('generalizes to 3+ documents and 3+ distinct addresses, not just '
        'the STP-vs-NCOER pair', () {
      final result = ResumeSanitizer.detectLocationConflict([
        {
          'sourceFile': 'jst.pdf',
          'city': 'Fort Carson',
          'state': 'CO',
          'documentType': 'jst',
        },
        {
          'sourceFile': 'ncoer.pdf',
          'city': 'Fort Benning',
          'state': 'GA',
          'documentType': 'ncoer',
        },
        {
          'sourceFile': 'resume.pdf',
          'city': 'Austin',
          'state': 'TX',
          'documentType': 'civilian_resume',
        },
      ]);

      expect(result, isNotNull);
      expect(result!.length, 3);
      // NCOER outranks JST for current-location authority (same order as
      // duty-station merging); the civilian_resume entry has no ranked
      // authority at all, so it never wins the pre-selection over a
      // recognized military document type.
      final preferred = result.singleWhere((c) => c['isPreferred'] == true);
      expect(preferred['city'], 'Fort Benning');
    });

    test('isSameLocation and normalizeStateToCode handle the abbreviation '
        'cases directly', () {
      expect(ResumeSanitizer.normalizeStateToCode('Colorado'), 'CO');
      expect(ResumeSanitizer.normalizeStateToCode('CO'), 'CO');
      expect(ResumeSanitizer.normalizeStateToCode('co'), 'CO');
      expect(
        ResumeSanitizer.isSameLocation(
            'Ft Benning', 'GA', 'Fort Benning', 'Georgia'),
        isTrue,
      );
      expect(
        ResumeSanitizer.isSameLocation(
            'Colorado Springs', 'CO', 'Fort Benning', 'GA'),
        isFalse,
      );
    });

    test('"St" only expands to "Saint" as a standalone word — a city like '
        '"Stockton" that merely STARTS WITH the "st" letters is untouched, '
        'not mangled into "Saintockton"', () {
      expect(ResumeSanitizer.normalizeCityForComparison('Stockton'),
          'stockton',
          reason: '"st" is not a standalone token here (immediately '
              'followed by "ockton", no word boundary) — must not expand');
      expect(ResumeSanitizer.normalizeCityForComparison('Austin'), 'austin',
          reason: '"st" appears mid-word ("Au-st-in") with no word '
              'boundary on either side — must not expand');

      // The intended case still works: "St" as its own token (an
      // abbreviated "Saint" prefix) does expand, so it compares equal to
      // the spelled-out form.
      expect(
        ResumeSanitizer.isSameLocation('St Louis', 'MO', 'Saint Louis', 'MO'),
        isTrue,
      );

      // And the two shapes are never confused with each other: a real
      // "St " abbreviation must not collide with an unrelated city that
      // merely starts with the same three letters.
      expect(
        ResumeSanitizer.isSameLocation('St Louis', 'MO', 'Stockton', 'MO'),
        isFalse,
      );
    });
  });

  group('contactMapFromAcceptedMappings — shared by both apply-time call '
      'sites (_buildPrefillFromMappings and _writeMappingsToSections)', () {
    test('splits a synthetic contact.location conflict resolution back into '
        'real city/state values — the exact transformation '
        '_buildPrefillFromMappings needs when building the first-setup '
        'prefill map', () {
      final accepted = [
        {'field': 'contact.firstName', 'suggestedValue': 'Jane'},
        {'field': 'contact.lastName', 'suggestedValue': 'Rivera'},
        {
          'field': 'contact.location',
          'suggestedValue': 'Colorado Springs, CO',
          '_locationCity': 'Colorado Springs',
          '_locationState': 'CO',
        },
      ];

      final result = ResumeSanitizer.contactMapFromAcceptedMappings(accepted);

      expect(result['firstName'], 'Jane');
      expect(result['lastName'], 'Rivera');
      expect(result['city'], 'Colorado Springs',
          reason: 'must split from _locationCity/_locationState, not '
              're-parse the "City, State" display string');
      expect(result['state'], 'CO');
      expect(result.containsKey('location'), isFalse,
          reason: 'the synthetic field name itself must never leak into '
              'the saved ContactInfo shape');
    });

    test('the identical transformation is what _writeMappingsToSections '
        'writes into the persisted contact ResumeSection JSON — same '
        'function, same input shape, same result, proving both call sites '
        'can never silently drift apart', () {
      // Mirrors exactly what _writeMappingsToSections passes: the full
      // accepted-mappings list, including non-contact fields that must be
      // ignored rather than crash the split.
      final accepted = [
        {'field': 'summary', 'suggestedValue': 'A summary.'},
        {
          'field': 'contact.location',
          'suggestedValue': 'Fort Benning, GA',
          '_locationCity': 'Fort Benning',
          '_locationState': 'GA',
        },
        {'field': 'contact.email', 'suggestedValue': 'jane@example.com'},
      ];

      final result = ResumeSanitizer.contactMapFromAcceptedMappings(accepted);
      final persistedJson = jsonEncode(result);
      final roundTripped =
          jsonDecode(persistedJson) as Map<String, dynamic>;

      expect(roundTripped['city'], 'Fort Benning');
      expect(roundTripped['state'], 'GA');
      expect(roundTripped['email'], 'jane@example.com');
      expect(roundTripped.containsKey('summary'), isFalse,
          reason: 'non-contact fields must be ignored, not written into '
              'the contact section');
    });

    test('a non-conflicting contact.city/contact.state pair (no '
        'contact.location synthesized at all) still assembles normally — '
        'the common case, unaffected by the new synthetic-field handling',
        () {
      final accepted = [
        {'field': 'contact.city', 'suggestedValue': 'Denver'},
        {'field': 'contact.state', 'suggestedValue': 'CO'},
      ];

      final result = ResumeSanitizer.contactMapFromAcceptedMappings(accepted);

      expect(result['city'], 'Denver');
      expect(result['state'], 'CO');
    });
  });

  group('_contributingRanges — Stage 3 plumbing carried through '
      'mergeCrossDocumentDuplicateRoles', () {
    test('a 2-way merge records both original sides\' own date range and '
        'whether each individually had bullets', () {
      final entries = [
        {
          'title': 'Network Communications Systems Operator',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2021-11-01',
          'endDate': null,
          'isCurrent': true,
          'bullets': [],
          '_sourceDocType': 'stp',
        },
        {
          'title': 'Network Communications Systems Operator',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2023-07-01',
          'endDate': null,
          'isCurrent': true,
          'bullets': ['Led a team of 6 in daily network operations'],
          '_sourceDocType': 'ncoer',
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1);
      final merged = result.first as Map<String, dynamic>;
      final ranges =
          merged['_contributingRanges'] as List<Map<String, dynamic>>;
      expect(ranges.length, 2);
      expect(ranges.any((r) => r['start'] == '2021-11-01' && r['hasBullets'] == false),
          isTrue,
          reason: 'the bulletless STP side must be recorded as such');
      expect(ranges.any((r) => r['start'] == '2023-07-01' && r['hasBullets'] == true),
          isTrue,
          reason: 'the bulleted NCOER side must be recorded as such');
    });

    test('a chained 3-way merge accumulates all three original ranges, not '
        'just the last pairwise result', () {
      // First two are single-award-date-shaped (JST "Dates Held" style —
      // no endDate, not current) close enough together to pass the
      // incomplete-date tolerance check; the third is an open-ended
      // current assignment close enough to the accumulated blob's date to
      // also merge in. Exact date arithmetic isn't the point of this test
      // (that's covered by the existing mergeCrossDocumentDuplicateRoles
      // group) — just that a 3-way chain preserves all three sources.
      final entries = [
        {
          'title': 'Supply Chain Coordinator',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2019-06-01',
          'endDate': null,
          'isCurrent': false,
          'bullets': ['Managed initial equipment issue'],
        },
        {
          'title': 'Supply Chain Coordinator',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2019-10-01',
          'endDate': null,
          'isCurrent': false,
          'bullets': [],
        },
        {
          'title': 'Supply Chain Coordinator',
          'company': 'U.S. Army',
          'location': '',
          'startDate': '2020-06-01',
          'endDate': null,
          'isCurrent': true,
          'bullets': ['Manages a multi-million-dollar inventory'],
        },
      ];

      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles(entries);

      expect(result.length, 1,
          reason: 'all three must merge into one entry for this test to be '
              'meaningful');
      final merged = result.first as Map<String, dynamic>;
      final ranges =
          merged['_contributingRanges'] as List<Map<String, dynamic>>;
      expect(ranges.length, 3,
          reason: 'all three original leaf entries must be recorded, not '
              'just the two sides of whichever pairwise merge ran last');
    });

    test('an entry that never merges (single source) has no '
        '_contributingRanges at all', () {
      final result = ResumeSanitizer.mergeCrossDocumentDuplicateRoles([
        {
          'title': 'Solo Role',
          'company': 'Acme',
          'startDate': '2020',
          'endDate': '2022',
          'isCurrent': false,
          'bullets': ['Did the job'],
        },
      ]);

      expect((result.first as Map<String, dynamic>).containsKey('_contributingRanges'),
          isFalse);
    });
  });

  group('detectIntraEntryGaps — a widened entry whose bullets don\'t cover '
      'the full merged span (Stage 3)', () {
    test('the real motivating case: an STP-widened current assignment with '
        'no bullets covering Nov 2021-Jul 2023, only Jul 2023-present', () {
      final merged = ResumeSanitizer.mergeCrossDocumentDuplicateRoles([
        {
          'title': 'Network Communications Systems Operator',
          'company': 'U.S. Army',
          'startDate': '2021-11-01',
          'endDate': null,
          'isCurrent': true,
          'bullets': [],
          '_sourceDocType': 'stp',
        },
        {
          'title': 'Network Communications Systems Operator',
          'company': 'U.S. Army',
          'startDate': '2023-07-01',
          'endDate': null,
          'isCurrent': true,
          'bullets': ['Led a team of 6 in daily network operations'],
          '_sourceDocType': 'ncoer',
        },
      ]);

      final gaps = ResumeSanitizer.detectIntraEntryGaps(merged);

      expect(gaps.length, 1);
      expect(gaps.first.kind, TimelineGapKind.withinEntry);
      expect(gaps.first.startDate, DateTime(2021, 11, 1));
      expect(gaps.first.endDate, DateTime(2023, 7, 1));
    });

    test('a widened entry whose contributing ranges fully cover the merged '
        'span produces no gap', () {
      final merged = ResumeSanitizer.mergeCrossDocumentDuplicateRoles([
        {
          'title': 'Operations Sergeant',
          'company': 'U.S. Army',
          'startDate': '2021-01-01',
          'endDate': '2023-06-01',
          'isCurrent': false,
          'bullets': ['Led daily operations for a 40-person platoon'],
        },
        {
          'title': 'Operations Sergeant',
          'company': 'U.S. Army',
          'startDate': '2022-06-01',
          'endDate': '2024-01-01',
          'isCurrent': false,
          'bullets': ['Managed a subsequent rating period with equal scope'],
        },
      ]);

      expect(merged.length, 1,
          reason: 'the two ranges must genuinely overlap (2022-06-01 through '
              '2023-06-01) for this test to be meaningful');
      final gaps = ResumeSanitizer.detectIntraEntryGaps(merged);

      expect(gaps, isEmpty);
    });

    test('a single-source (never merged) entry is skipped entirely — '
        'nothing for this failure mode to apply to', () {
      final merged = ResumeSanitizer.mergeCrossDocumentDuplicateRoles([
        {
          'id': 'solo',
          'title': 'Solo Role',
          'company': 'Acme',
          'startDate': '2020',
          'endDate': '2022',
          'isCurrent': false,
          'bullets': [],
        },
      ]);

      expect(ResumeSanitizer.detectIntraEntryGaps(merged), isEmpty);
    });

    test('generalizes to 3+ contributing ranges: the middle one is the only '
        'one lacking bullets, producing exactly one gap in the middle — '
        'exercises detectIntraEntryGaps directly against a hand-built '
        '_contributingRanges list, since getting mergeCrossDocumentDuplicateRoles '
        'itself to organically produce a 3-way chain with precise day-level '
        'gap boundaries is a separate concern already covered by the '
        "plumbing group above", () {
      final entry = {
        'id': 'e1',
        'startDate': '2019-01-01',
        'endDate': '2022-01-01',
        'isCurrent': false,
        '_contributingRanges': [
          {
            'start': '2019-01-01',
            'end': '2020-01-01',
            'isCurrent': false,
            'hasBullets': true,
          },
          {
            'start': '2020-01-01',
            'end': '2021-01-01',
            'isCurrent': false,
            'hasBullets': false,
          },
          {
            'start': '2021-01-01',
            'end': '2022-01-01',
            'isCurrent': false,
            'hasBullets': true,
          },
        ],
      };

      final gaps = ResumeSanitizer.detectIntraEntryGaps([entry]);

      expect(gaps.length, 1);
      expect(gaps.first.startDate, DateTime(2020, 1, 1));
      expect(gaps.first.endDate, DateTime(2021, 1, 1));
      expect(gaps.first.adjacentEntryIds, ['e1']);
    });
  });

  group('detectInterEntryGaps — dead time between separate jobs (Stage 3)',
      () {
    test('a deliberate 6+ month gap between two jobs is flagged', () {
      final gaps = ResumeSanitizer.detectInterEntryGaps(
        [
          {
            'id': 'job1',
            'startDate': '2018-01-01',
            'endDate': '2019-06-01',
            'isCurrent': false,
          },
          {
            'id': 'job2',
            'startDate': '2020-06-01',
            'endDate': '2022-01-01',
            'isCurrent': false,
          },
        ],
        [],
        [],
      );

      expect(gaps.length, 1);
      expect(gaps.first.kind, TimelineGapKind.betweenEntries);
      expect(gaps.first.adjacentEntryIds, ['job1', 'job2']);
      expect(gaps.first.startDate, DateTime(2019, 6, 1));
      expect(gaps.first.endDate, DateTime(2020, 6, 1));
    });

    test('a gap under the 30-day threshold is not flagged (rounding, not a '
        'real gap)', () {
      final gaps = ResumeSanitizer.detectInterEntryGaps(
        [
          {
            'id': 'job1',
            'startDate': '2018-01-01',
            'endDate': '2019-06-01',
            'isCurrent': false,
          },
          {
            'id': 'job2',
            'startDate': '2019-06-15',
            'endDate': '2022-01-01',
            'isCurrent': false,
          },
        ],
        [],
        [],
      );

      expect(gaps, isEmpty);
    });

    test('a gap covered by an education/certification date within it is not '
        'flagged', () {
      final gaps = ResumeSanitizer.detectInterEntryGaps(
        [
          {
            'id': 'job1',
            'startDate': '2018-01-01',
            'endDate': '2019-06-01',
            'isCurrent': false,
          },
          {
            'id': 'job2',
            'startDate': '2020-06-01',
            'endDate': '2022-01-01',
            'isCurrent': false,
          },
        ],
        [
          {'graduationYear': '2019-12-01'},
        ],
        [],
      );

      expect(gaps, isEmpty,
          reason: 'a degree completed mid-gap plausibly explains the dead '
              'time — not flagged as unexplained');
    });

    test('adjacent/overlapping entries produce no gap at all', () {
      final gaps = ResumeSanitizer.detectInterEntryGaps(
        [
          {
            'id': 'job1',
            'startDate': '2018-01-01',
            'endDate': '2019-06-01',
            'isCurrent': false,
          },
          {
            'id': 'job2',
            'startDate': '2019-06-01',
            'endDate': '2022-01-01',
            'isCurrent': false,
          },
        ],
        [],
        [],
      );

      expect(gaps, isEmpty);
    });

    test('fewer than 2 experience entries never produces a gap', () {
      expect(
        ResumeSanitizer.detectInterEntryGaps(
          [
            {
              'id': 'job1',
              'startDate': '2018-01-01',
              'endDate': '2019-06-01',
              'isCurrent': false,
            },
          ],
          [],
          [],
        ),
        isEmpty,
      );
    });

    test(
        'a DA-638-shaped compact "YYYYMMDD" entry is not silently dropped '
        'from gap analysis (live-document pass finding: extractYear\'s \\b '
        'boundary regex can\'t see a year inside an unbroken digit run, so '
        'this entry used to vanish from _entrySpan entirely and a phantom '
        'gap got reported across a period it actually covers)', () {
      final gaps = ResumeSanitizer.detectInterEntryGaps(
        [
          {
            'id': 'job1',
            'startDate': '2018-01-01',
            'endDate': '2018-06-01',
            'isCurrent': false,
          },
          // Covers the entire would-be gap below via its compact dates.
          {
            'id': 'award',
            'startDate': '20180601',
            'endDate': '20190101',
            'isCurrent': false,
          },
          {
            'id': 'job2',
            'startDate': '2019-01-01',
            'endDate': '2020-01-01',
            'isCurrent': false,
          },
        ],
        [],
        [],
      );

      expect(gaps, isEmpty,
          reason: 'the compact-dated "award" entry fully covers the window '
              'between job1 and job2 — it must be seen by span computation, '
              'not skipped as unparseable');
    });
  });

  group('extractYear / parseApproxDate — compact "YYYYMMDD" dates '
      '(a real DA-638 shape found by the live-document verification pass)',
      () {
    test('extractYear reads the year out of a bare YYYYMMDD string', () {
      expect(ResumeSanitizer.extractYear('20181025'), 2018);
    });

    test('parseApproxDate parses a bare YYYYMMDD string to the exact day',
        () {
      expect(ResumeSanitizer.parseApproxDate('20181025'),
          DateTime(2018, 10, 25));
    });

    test(
        'dateRangesOverlap recognizes a genuine overlap when both sides are '
        'compact YYYYMMDD', () {
      expect(
        ResumeSanitizer.dateRangesOverlap(
          '20160607', '20190503', false,
          '20170105', '20171001', false,
        ),
        isTrue,
      );
    });
  });
}
