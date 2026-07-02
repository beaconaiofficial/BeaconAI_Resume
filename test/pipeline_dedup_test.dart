import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/resume_sanitizer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PRIORITY 3 — pipeline-ordering bug.
//
// Root cause: bare-duplicate-stub removal and the "same event classified as
// both a cert and a job" cross-reference existed in ResumeSanitizer but were
// only ever wired into ResumeMigrationService (the one-time retroactive
// migration for OLD data) — never into the live parseFieldMappings path, so
// every FRESH extraction still showed the bug. Fixed by running
// classify → route → dedup → cap as one ordered pass inside
// parseFieldMappings itself (see cloudflare_worker_service.dart), which
// every extraction path (text/image/single-PDF/chunked-PDF) already funnels
// through.
//
// Per the audit instructions, this reproduces the original military case
// FIRST (fastest way to confirm the fix addresses what was observed), then
// proves generality with a synthetic NON-military fixture of the same
// shape. A pipeline-ordering bug should reproduce and resolve identically
// regardless of career field — if the non-military fixture behaves
// differently, the fix is overfitting to the reproduction case.
// ─────────────────────────────────────────────────────────────────────────────

String _mergedChunkJson({
  required List<Map<String, dynamic>> experience,
  required List<Map<String, dynamic>> certifications,
}) {
  return jsonEncode({
    'contact': {'firstName': 'Test', 'lastName': 'User'},
    'summary': 'A summary.',
    'experience': experience,
    'education': <dynamic>[],
    'skills': <dynamic>[],
    'certifications': certifications,
  });
}

void main() {
  group('Military reproduction case', () {
    test('bare stubs are discarded, and the entry duplicating a training '
        'certification is dropped from experience — cert survives', () {
      // Shape of what two different chunks of the same JST independently
      // extracted for the SAME underlying training event: one chunk
      // produced a bare award-date-only stub, another chunk produced a
      // full "assignment"-shaped entry whose date range happens to contain
      // the certification's completion date — the tell that it's the same
      // event, not a second real job.
      final json = _mergedChunkJson(
        experience: [
          {
            'id': 'e1',
            'title': 'Motor Transport Operator',
            'company': 'United States Army',
            'location': '',
            'startDate': '06-JUN-2016',
            'endDate': null,
            'isCurrent': false,
            'bullets': <String>[],
            'entryType': 'employment',
          },
          {
            'id': 'e2',
            'title': 'Motor Transport Operator',
            'company': 'US Army',
            'location': 'Ft Leonard Wood, MO',
            'startDate': '2016-04-25',
            'endDate': '2016-10-03',
            'isCurrent': false,
            'bullets': ['Operated wheeled vehicles in convoy operations'],
            'entryType': 'employment',
          },
          {
            'id': 'e3',
            'title': 'Nodal Network Systems Operator-Maintainer',
            'company': 'United States Army',
            'location': '',
            'startDate': '26-SEP-2019',
            'endDate': null,
            'isCurrent': false,
            'bullets': <String>[],
            'entryType': 'employment',
          },
          {
            'id': 'e4',
            'title': 'Nodal Network Systems Operator-Maintainer',
            'company': 'US Army',
            'location': 'Fort Gordon, GA',
            'startDate': '2019-09-01',
            'endDate': '2022-08-15',
            'isCurrent': false,
            'bullets': ['Maintained tactical network infrastructure'],
            'entryType': 'employment',
          },
        ],
        certifications: [
          {
            'id': 'c1',
            'name': 'Motor Transport Operator',
            'issuer': 'US Army Training Center',
            'dateEarned': '2016-05-29',
            'certType': 'credential',
          },
        ],
      );

      final result = CloudflareWorkerService.parseFieldMappings(json);
      final expRow =
          result.mappings.where((m) => m['field'] == 'experience').toList();
      final certRow = result.mappings
          .where((m) => m['field'] == 'certifications')
          .toList();

      // Motor Transport Operator: bare stub gone, full entry ALSO gone
      // (its date range 04-25→10-03 contains the cert's 05-29 date).
      final experienceEntries =
          expRow.isEmpty ? <dynamic>[] : expRow.first['suggestedValue'] as List;
      expect(
        experienceEntries.any((e) => e['title'] == 'Motor Transport Operator'),
        isFalse,
        reason: 'the training event must not survive as an experience entry '
            'once it is correctly represented by a certification',
      );

      // Nodal Network: bare stub gone, full entry SURVIVES (no matching
      // certification exists for it in this fixture, and its own dates
      // are a real, complete range — nothing here says it's a duplicate).
      final nodalEntries = experienceEntries
          .where((e) => e['title'] == 'Nodal Network Systems Operator-Maintainer')
          .toList();
      expect(nodalEntries.length, 1,
          reason: 'the bare stub must be discarded but the one real, fuller '
              'entry must survive');
      expect(nodalEntries.first['company'], 'US Army');
      expect(nodalEntries.first['bullets'], isNotEmpty);

      // Certification survives untouched.
      final certEntries =
          certRow.isEmpty ? <dynamic>[] : certRow.first['suggestedValue'] as List;
      expect(
        certEntries.any((c) => c['name'] == 'Motor Transport Operator'),
        isTrue,
      );
    });
  });

  group('Non-military synthetic fixture — same shape, different field', () {
    test('bare stub discarded and the entry duplicating a training '
        'certification is dropped, for a healthcare career path', () {
      final json = _mergedChunkJson(
        experience: [
          {
            'id': 'e1',
            'title': 'Certified Nursing Assistant',
            'company': 'Sunrise Senior Living',
            'location': '',
            'startDate': '2019',
            'endDate': null,
            'isCurrent': false,
            'bullets': <String>[],
            'entryType': 'employment',
          },
          {
            'id': 'e2',
            'title': 'Certified Nursing Assistant',
            'company': 'Sunrise Senior Living',
            'location': 'Denver, CO',
            // Date range CONTAINS the cert completion date below — same
            // tell as the military case: this "job" is really the
            // training/clinical placement period, not separate real work.
            'startDate': '2019-01-10',
            'endDate': '2019-04-20',
            'isCurrent': false,
            'bullets': ['Completed supervised clinical rotation hours'],
            'entryType': 'employment',
          },
          {
            'id': 'e3',
            'title': 'Certified Nursing Assistant',
            'company': 'Golden Valley Care Home',
            'location': 'Denver, CO',
            // A genuinely separate, later REAL job at a different
            // employer — must survive untouched.
            'startDate': '2020-06-01',
            'endDate': '2023-01-15',
            'isCurrent': false,
            'bullets': [
              'Provided daily living assistance to 12 residents per shift',
              'Documented patient vitals and reported changes to nursing staff',
            ],
            'entryType': 'employment',
          },
        ],
        certifications: [
          {
            'id': 'c1',
            'name': 'Certified Nursing Assistant',
            'issuer': 'State Board of Nursing',
            'dateEarned': '2019-03-01',
            'certType': 'credential',
          },
        ],
      );

      final result = CloudflareWorkerService.parseFieldMappings(json);
      final expRow =
          result.mappings.where((m) => m['field'] == 'experience').toList();
      final experienceEntries =
          expRow.isEmpty ? <dynamic>[] : expRow.first['suggestedValue'] as List;

      // Bare stub + the training-placement entry at Sunrise are both gone;
      // the real, later job at Golden Valley survives.
      expect(experienceEntries.length, 1,
          reason: 'only the genuinely distinct later job should remain');
      expect(experienceEntries.first['company'], 'Golden Valley Care Home');
      expect(experienceEntries.first['bullets'], hasLength(2));
    });

    test('control: legitimate certify-then-hired pattern is NOT treated as '
        'a duplicate (cert date before job start, not inside its range)', () {
      // The common, entirely valid real-world pattern this heuristic must
      // NOT catch: someone earns a credential, then is hired afterward
      // into a real, ongoing role with the same title.
      final experience = [
        {
          'title': 'Certified Nursing Assistant',
          'company': 'Golden Valley Care Home',
          'startDate': '2019-06-01',
          'endDate': null,
          'isCurrent': true,
          'bullets': ['Provide daily living assistance to residents'],
        },
      ];
      final certifications = [
        {
          'name': 'Certified Nursing Assistant',
          'issuer': 'State Board of Nursing',
          'dateEarned': '2019-03-01', // BEFORE the job start — not inside it
        },
      ];

      final result = ResumeSanitizer.dropExperienceMatchingCertification(
          experience, certifications);

      expect(result.length, 1,
          reason: 'a real, ongoing job must never be dropped just because '
              'the candidate holds a same-titled credential earned before '
              'they started it — that is the normal certify-then-hired '
              'pattern, not a duplicate');
    });
  });
}
