import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/providers/resume_provider.dart';
import 'package:beaconai_resume/services/hive_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ISSUE 3 — ATS score showed 0 on tailored resumes immediately after
// creation.
//
// Confirmed which mechanism: the LOCAL section-completeness score
// (atsScoreProvider / _computeAtsScore), not the API-based keyword scanner
// (analyzeKeywords) — that one already shows a real error state on failure
// (verified: ats_analyzer_screen.dart's catch sets _errorMessage and leaves
// _analysis null, never a fake score), and it only runs on manual user
// action, which doesn't match "immediately after creation".
//
// Root cause: atsScoreProvider watches resumeListProvider (resumeBox) but
// _computeAtsScore reads a DIFFERENT box, resumeSectionBox. Both the
// tailored-resume save flow and the master-resume wizard write the Resume
// record to resumeBox FIRST, then write its sections to resumeSectionBox in
// a separate step afterward. The Resume-record write is what triggers this
// provider to compute (and cache) a value — at that moment no section
// exists yet, so it's always 0 — and the LATER section writes never
// re-trigger it, because they touch a box this provider was never watching.
// Confirmed this is not tailored-resume-specific: resume_builder_wizard_
// screen.dart has the identical two-step write ordering.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('beaconai_ats_score_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(AppConstants.resumeTypeId)) {
      Hive.registerAdapter(ResumeAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.sectionTypeEnumTypeId)) {
      Hive.registerAdapter(SectionTypeEnumAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.resumeSectionTypeId)) {
      Hive.registerAdapter(ResumeSectionAdapter());
    }
    await Hive.openBox<Resume>(AppConstants.resumeBox);
    await Hive.openBox<ResumeSection>(AppConstants.resumeSectionBox);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
      'atsScoreProvider updates when sections are written to '
      'resumeSectionBox alone, with no further write to resumeBox — '
      'reproducing exactly the two-step save order '
      '(Resume record, then sections) both the tailored-resume flow and '
      'the master-resume wizard use', () async {
    final now = DateTime.now();
    const resumeId = 'r1';

    // Step 1 of the real save flow: the Resume record lands in resumeBox.
    await HiveService.resumeBox.put(
      resumeId,
      Resume(
        id: resumeId,
        title: 'Tailored Resume',
        createdAt: now,
        updatedAt: now,
        isMaster: false,
      ),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final scores = <int>[];
    container.listen(
      atsScoreProvider(resumeId),
      (previous, next) => scores.add(next),
      fireImmediately: true,
    );

    expect(scores.single, 0,
        reason: 'no sections exist yet — a genuine 0 at this point, not a '
            'bug in itself');

    // Step 2 of the real save flow: sections land in resumeSectionBox,
    // WITHOUT any further write to resumeBox — this is exactly what
    // _writeTailoredSections (and the wizard's equivalent) does.
    Future<void> putSection(SectionTypeEnum type, String data) =>
        HiveService.resumeSectionBox.put(
          '${resumeId}_${type.name}',
          ResumeSection(
            id: 's_${type.name}',
            resumeId: resumeId,
            type: type,
            data: data,
            hasUnreviewedAIContent: true,
          ),
        );

    await putSection(SectionTypeEnum.contact,
        '{"firstName":"Test","lastName":"Veteran"}');
    await putSection(SectionTypeEnum.summary, '{"text":"A tailored summary."}');
    await putSection(SectionTypeEnum.experience, '[{"title":"Engineer"}]');
    await putSection(SectionTypeEnum.education, '[{"degree":"BS"}]');
    await putSection(SectionTypeEnum.skills, '[{"name":"Networking"}]');
    await putSection(
        SectionTypeEnum.certifications, '[{"name":"CCNA"}]');

    // perSection = 100 ~/ 6 = 16 (integer division loses 4 points to
    // rounding across 6 sections) — 96, not 100, is the correct maximum.
    expect(scores.last, 96,
        reason: 'all 6 sections now exist with real content — the score '
            'must reflect that immediately, without needing any further '
            'write to resumeBox (which nothing in this save step touches '
            'again) to trigger a recompute');
  });
}
