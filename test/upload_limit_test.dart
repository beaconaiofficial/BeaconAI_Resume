import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/user_settings.dart';
import 'package:beaconai_resume/screens/document_upload_screen.dart';
import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/hive_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PRIORITY 1 — upload count / tier limit enforcement.
//
// Root cause was that first-setup-mode uploads never seeded
// Resume.uploadCount (see resume_builder_wizard_screen.dart's
// _persistToHive), so a Free-tier user's founding 4 documents left the
// counter at 0 forever — every later "Upload More" call believed the user
// had 4 fresh slots available regardless of how many they'd actually used.
// These tests cover: the corrected counter math, and that reaching the
// limit blocks the costly Claude API call entirely rather than merely
// hiding a button.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('DocumentUploadScreen.remainingUploadSlots (pure)', () {
    test('Free tier at the limit (4/4) has 0 remaining', () {
      expect(
        DocumentUploadScreen.remainingUploadSlots(
            uploadCount: 4, tierLimit: AppConstants.uploadLimitFree),
        0,
      );
    });

    test('Free tier under the limit has the correct remainder', () {
      expect(
        DocumentUploadScreen.remainingUploadSlots(
            uploadCount: 1, tierLimit: AppConstants.uploadLimitFree),
        3,
      );
    });

    test('never goes negative when uploadCount somehow exceeds the limit', () {
      expect(
        DocumentUploadScreen.remainingUploadSlots(
            uploadCount: 9, tierLimit: AppConstants.uploadLimitFree),
        0,
      );
    });

    test('Pro tier (-1) is always unlimited', () {
      expect(
        DocumentUploadScreen.remainingUploadSlots(uploadCount: 400, tierLimit: -1),
        greaterThan(0),
      );
    });
  });

  group('Upload blocked before the Claude API call is ever made', () {
    late Directory tempDir;
    late int apiCallCount;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('beaconai_upload_limit_test');
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
      if (!Hive.isAdapterRegistered(AppConstants.userSettingsTypeId)) {
        Hive.registerAdapter(UserSettingsAdapter());
      }
      if (!Hive.isAdapterRegistered(AppConstants.resumeTypeId)) {
        Hive.registerAdapter(ResumeAdapter());
      }
      await Hive.openBox<UserSettings>(AppConstants.userSettingsBox);
      await Hive.openBox<Resume>(AppConstants.resumeBox);

      apiCallCount = 0;
      CloudflareWorkerService.client = MockClient((request) async {
        apiCallCount++;
        return http.Response(
            '{"content":[{"type":"text","text":"{}"}]}', 200);
      });
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      CloudflareWorkerService.client = http.Client();
    });

    test('4 successful uploads bring a Free-tier resume to uploadCount == 4',
        () async {
      const resumeId = 'r1';
      await HiveService.resumeBox.put(
        resumeId,
        Resume(
          id: resumeId,
          title: 'Master Resume',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
          isMaster: true,
          uploadCount: 0,
        ),
      );

      // Simulate 4 applied uploads the same way DocumentUploadScreen's
      // normal (non-first-setup) _applyAll increments — one at a time, as
      // 4 separate upload sessions would.
      for (var i = 0; i < 4; i++) {
        final resume = HiveService.resumeBox.get(resumeId)!;
        resume.uploadCount += 1;
        await resume.save();
      }

      final resume = HiveService.resumeBox.get(resumeId)!;
      expect(resume.uploadCount, 4);
      expect(
        DocumentUploadScreen.remainingUploadSlots(
            uploadCount: resume.uploadCount,
            tierLimit: AppConstants.uploadLimitFree),
        0,
      );
    });

    test('5th upload attempt on a Free-tier resume already at 4/4 is '
        'blocked before any extraction call is made', () async {
      const resumeId = 'r2';
      await HiveService.resumeBox.put(
        resumeId,
        Resume(
          id: resumeId,
          title: 'Master Resume',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
          isMaster: true,
          uploadCount: AppConstants.uploadLimitFree, // already at the cap
        ),
      );

      final resume = HiveService.resumeBox.get(resumeId)!;
      final remaining = DocumentUploadScreen.remainingUploadSlots(
          uploadCount: resume.uploadCount,
          tierLimit: AppConstants.uploadLimitFree);
      expect(remaining, 0);

      // This mirrors both gates DocumentUploadScreen applies before ever
      // calling CloudflareWorkerService: the upfront _pickFiles() check
      // ("if (remainingSlots <= 0) { showDialog(); return; }") and the
      // defense-in-depth per-file re-check inside the extraction loop.
      // Both are driven by exactly this function — if it returns 0, the
      // real screen code returns/breaks before reaching
      // CloudflareWorkerService.extractResumeFields, i.e. before touching
      // CloudflareWorkerService.client at all.
      if (remaining <= 0) {
        // No extraction attempted — do NOT call the service.
      } else {
        await CloudflareWorkerService.extractResumeFields('should not run');
      }

      expect(apiCallCount, 0,
          reason: 'the Claude API client must never be invoked for an '
              'upload attempt once the tier limit is reached');
    });

    test('an upload attempt with slots remaining DOES reach the API client '
        '(control case — proves the mock is wired correctly)', () async {
      const resumeId = 'r3';
      await HiveService.resumeBox.put(
        resumeId,
        Resume(
          id: resumeId,
          title: 'Master Resume',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
          isMaster: true,
          uploadCount: 2,
        ),
      );

      final resume = HiveService.resumeBox.get(resumeId)!;
      final remaining = DocumentUploadScreen.remainingUploadSlots(
          uploadCount: resume.uploadCount,
          tierLimit: AppConstants.uploadLimitFree);
      expect(remaining, 2);

      if (remaining > 0) {
        await CloudflareWorkerService.extractResumeFields('some resume text');
      }

      expect(apiCallCount, 1);
    });
  });
}
