import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/models/user_settings.dart';
import 'package:beaconai_resume/services/hive_service.dart';
import 'package:beaconai_resume/services/resume_migration_service.dart';
import 'package:beaconai_resume/services/resume_sanitizer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GAP 1 — retroactive migration test.
//
// Seeds a plain (non-Flutter-bound) Hive instance in a temp directory with a
// resume matching the pre-generalization-pass "bad" shape: a training entry
// stored as employment, a bare-duplicate stub, an over-cap bullet list, and
// an unflagged compliance-training-shaped certification. Runs the migration,
// asserts it's cleaned per GAP 1's rules, and asserts a second run is a
// true no-op (version-gated).
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('beaconai_migration_test');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(AppConstants.tierEnumTypeId)) {
      Hive.registerAdapter(TierEnumAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.exportFormatEnumTypeId)) {
      Hive.registerAdapter(ExportFormatEnumAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.appThemeEnumTypeId)) {
      Hive.registerAdapter(AppThemeEnumAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.sectionTypeEnumTypeId)) {
      Hive.registerAdapter(SectionTypeEnumAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.userSettingsTypeId)) {
      Hive.registerAdapter(UserSettingsAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.resumeTypeId)) {
      Hive.registerAdapter(ResumeAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.resumeSectionTypeId)) {
      Hive.registerAdapter(ResumeSectionAdapter());
    }

    await Hive.openBox<UserSettings>(AppConstants.userSettingsBox);
    await Hive.openBox<Resume>(AppConstants.resumeBox);
    await Hive.openBox<ResumeSection>(AppConstants.resumeSectionBox);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('seeds old-shape data, migrates once, cleans per GAP 1 rules, and '
      'a second run is a true no-op', () async {
    // ── Seed: UserSettings never migrated (version 0) ──────────────────
    await HiveService.userSettingsBox
        .put(AppConstants.userSettingsKey, UserSettings.defaults());
    expect(HiveService.settings.experienceSanitizedVersion, 0);

    // ── Seed: one resume with old-shape experience + certifications ────
    const resumeId = 'r1';
    await HiveService.resumeBox.put(
      resumeId,
      Resume(
        id: resumeId,
        title: 'Master Resume',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
        isMaster: true,
      ),
    );

    // Experience: a real job, a training entry masquerading as a job
    // (matches a fallbackTrainingCompanyPatterns keyword), a bare stub
    // duplicating the real job's title, and a job with 9 bullets (over cap).
    final overCapBullets = [
      'Short bullet one',
      'A considerably longer and more detailed achievement bullet with metrics',
      'Mid length bullet with some detail here',
      'Tiny bullet',
      'Another long and specific bullet describing a measurable outcome for the team',
      'Also mid-length with reasonable detail included',
      'Short again',
      'One more reasonably detailed bullet about process improvement',
      'Final short one',
    ];
    final experienceJson = jsonEncode([
      {
        'id': 'e1',
        'title': 'Operations Manager',
        'company': 'Northgate Retail Co.',
        'location': 'Columbus, OH',
        'startDate': '2019',
        'endDate': '2023',
        'isCurrent': false,
        'bullets': overCapBullets,
        'isAIPrefilled': true,
      },
      {
        'id': 'e2',
        // Bare stub duplicating the title above — no company, no bullets.
        'title': 'Operations Manager',
        'company': '',
        'location': '',
        'startDate': '',
        'endDate': '',
        'isCurrent': false,
        'bullets': <String>[],
        'isAIPrefilled': true,
      },
      {
        'id': 'e3',
        'title': 'Data Analytics Bootcamp',
        'company': 'General Assembly Academy',
        'location': 'Remote',
        'startDate': '2018',
        'endDate': '2018',
        'isCurrent': false,
        'bullets': ['Completed a 10-week data analytics bootcamp'],
        'isAIPrefilled': true,
      },
    ]);
    await HiveService.resumeSectionBox.put(
      '${resumeId}_${SectionTypeEnum.experience.name}',
      ResumeSection(
        id: 'sec_exp',
        resumeId: resumeId,
        type: SectionTypeEnum.experience,
        data: experienceJson,
      ),
    );

    // Certifications: one real credential, one compliance-training-shaped
    // entry never classified (no certType — old data), stored as-is.
    final certsJson = jsonEncode([
      {
        'id': 'c1',
        'name': 'PMP Certification',
        'issuer': 'PMI',
        'dateEarned': '2021',
        'expiresDate': null,
        'credentialId': null,
        'isAIPrefilled': true,
      },
      {
        'id': 'c2',
        'name': 'Structured Self Development',
        'issuer': 'Internal',
        'dateEarned': '2020',
        'expiresDate': null,
        'credentialId': null,
        'isAIPrefilled': true,
      },
    ]);
    await HiveService.resumeSectionBox.put(
      '${resumeId}_${SectionTypeEnum.certifications.name}',
      ResumeSection(
        id: 'sec_cert',
        resumeId: resumeId,
        type: SectionTypeEnum.certifications,
        data: certsJson,
      ),
    );

    // ── Run the migration ────────────────────────────────────────────
    await ResumeMigrationService.runIfNeeded();

    // Version flag advanced.
    expect(HiveService.settings.experienceSanitizedVersion,
        ResumeSanitizer.currentSanitizationVersion);

    // Experience: bare stub discarded, training entry moved out, real job's
    // bullets capped at 6.
    final expAfter = jsonDecode(
        HiveService.resumeSectionBox
            .get('${resumeId}_${SectionTypeEnum.experience.name}')!
            .data) as List<dynamic>;
    expect(expAfter.length, 1,
        reason: 'bare stub discarded and training entry promoted out, '
            'leaving only the real job');
    final realJob = expAfter.first as Map<String, dynamic>;
    expect(realJob['title'], 'Operations Manager');
    expect(realJob['company'], 'Northgate Retail Co.');
    expect((realJob['bullets'] as List).length, 6,
        reason: 'bullets over the cap must be trimmed to 6');

    // Certifications: PMP untouched, training entry promoted in, compliance
    // entry FLAGGED (not deleted).
    final certsAfter = jsonDecode(
        HiveService.resumeSectionBox
            .get('${resumeId}_${SectionTypeEnum.certifications.name}')!
            .data) as List<dynamic>;
    expect(certsAfter.length, 3,
        reason: 'original 2 certs + 1 promoted from the training entry');

    final pmp = certsAfter
        .cast<Map<String, dynamic>>()
        .firstWhere((c) => c['name'] == 'PMP Certification');
    expect(pmp['needsComplianceReview'], isNot(true),
        reason: 'a real credential must not be flagged');

    final ssd = certsAfter
        .cast<Map<String, dynamic>>()
        .firstWhere((c) => c['name'] == 'Structured Self Development');
    expect(ssd['needsComplianceReview'], true,
        reason: 'likely compliance training must be FLAGGED, not deleted');
    expect(ssd['complianceReviewReason'], isNotEmpty);

    final promoted = certsAfter.cast<Map<String, dynamic>>().firstWhere(
        (c) => c['name'] == 'Data Analytics Bootcamp',
        orElse: () => <String, dynamic>{});
    expect(promoted, isNotEmpty,
        reason: 'the training entry must be promoted into certifications, '
            'not silently dropped');

    // ── Second run: must be a true no-op ────────────────────────────
    // Reintroduce a bad-shape entry directly (bypassing the migration) to
    // prove the second call doesn't re-scan: if it did, this would get
    // cleaned too.
    final tamperedJson = jsonEncode([
      ...expAfter,
      {
        'id': 'e_tampered',
        'title': 'Operations Manager',
        'company': '',
        'bullets': <String>[],
      },
    ]);
    final expSection = HiveService.resumeSectionBox
        .get('${resumeId}_${SectionTypeEnum.experience.name}')!;
    expSection.data = tamperedJson;
    await expSection.save();

    await ResumeMigrationService.runIfNeeded();

    final expAfterSecondRun = jsonDecode(
        HiveService.resumeSectionBox
            .get('${resumeId}_${SectionTypeEnum.experience.name}')!
            .data) as List<dynamic>;
    expect(expAfterSecondRun.length, 2,
        reason: 'second run must be a no-op — the tampered bare stub added '
            'after the version flag was set must survive untouched, proving '
            'the migration did not re-scan');
  });
}
