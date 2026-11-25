import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/hive_registrar.g.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/screens/interview_prep_pro_screen.dart';
import 'package:beaconai_resume/services/hive_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pro Interview Prep was opened from the dashboard with no resume id, so
// saved study guides (keyed by resume id) never loaded and generation could
// not run. The dashboard now passes the master resume's id; when the screen
// is opened without one it shows a resume picker instead of a dead end.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('beaconai_prep_pro_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(AppConstants.resumeTypeId)) {
      Hive.registerAdapters();
    }
    await Hive.openBox<Resume>(AppConstants.resumeBox);
    await Hive.openBox<ResumeSection>(AppConstants.resumeSectionBox);
    await Hive.openBox<InterviewStudyGuide>(
        AppConstants.interviewStudyGuideBox);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> addResume(String id, {required bool master}) =>
      HiveService.resumeBox.put(
        id,
        Resume(
          id: id,
          title: master ? 'Master Resume' : 'Platform Engineer',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          isMaster: master,
          companyName: master ? null : 'Cascadia Cloud',
          roleTitle: master ? null : 'Platform Engineer',
        ),
      );

  Future<void> addGuide(String resumeId, String role) =>
      HiveService.studyGuideBox.put(
        'g_$resumeId',
        InterviewStudyGuide(
          id: 'g_$resumeId',
          resumeId: resumeId,
          companyName: 'Cascadia Cloud',
          roleTitle: role,
          generatedAt: DateTime(2026, 1, 2),
          questions: [
            InterviewQuestion(
              id: 'q1',
              category: QuestionCategoryEnum.behavioral,
              questionText: 'Tell me about a hard bug you fixed.',
              answerGuide: 'Use the latency story.',
            ),
          ],
        ),
      );

  Future<void> pumpScreen(WidgetTester tester, {Object? args}) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: RouteSettings(name: '/prep', arguments: args),
          builder: (_) => const InterviewPrepProScreen(),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('opened with the master resume id, its saved guide loads',
      (tester) async {
    await tester.runAsync(() async {
      await addResume('m1', master: true);
      await addGuide('m1', 'Senior Platform Engineer');
    });

    await pumpScreen(tester, args: {'resumeId': 'm1'});

    expect(find.text('Senior Platform Engineer'), findsOneWidget);
    expect(find.text('Which resume should we prep you from?'), findsNothing);
  });

  testWidgets(
      'opened without a resume id, it shows a picker; picking a resume loads '
      'that resume\'s saved guide', (tester) async {
    await tester.runAsync(() async {
      await addResume('m1', master: true);
      await addResume('t1', master: false);
      await addGuide('t1', 'Tailored Guide Role');
    });

    await pumpScreen(tester);

    expect(find.text('Which resume should we prep you from?'), findsOneWidget);
    expect(find.text('Master Resume'), findsOneWidget);
    expect(find.text('Platform Engineer — Cascadia Cloud'), findsOneWidget);
    expect(find.text('Generate Study Guide'), findsNothing);

    await tester.tap(find.text('Platform Engineer — Cascadia Cloud'));
    await tester.pump();

    expect(find.text('Tailored Guide Role'), findsOneWidget);
  });

  testWidgets(
      'picking a resume with no saved guide shows the job-posting input, and '
      'Change returns to the picker', (tester) async {
    await tester.runAsync(() => addResume('m1', master: true));

    await pumpScreen(tester);
    await tester.tap(find.text('Master Resume'));
    await tester.pump();

    expect(find.text('Generate Study Guide'), findsOneWidget);
    expect(find.text('Prepping from: Master Resume'), findsOneWidget);

    await tester.tap(find.text('Change'));
    await tester.pump();
    expect(find.text('Which resume should we prep you from?'), findsOneWidget);
  });

  testWidgets('a stale resume id falls back to the picker instead of failing',
      (tester) async {
    await tester.runAsync(() => addResume('m1', master: true));

    await pumpScreen(tester, args: {'resumeId': 'deleted-id'});

    expect(find.text('Which resume should we prep you from?'), findsOneWidget);
  });

  testWidgets('with no resumes at all, the picker says to create one',
      (tester) async {
    await pumpScreen(tester);
    expect(find.textContaining('You don\'t have a resume yet'), findsOneWidget);
  });
}
