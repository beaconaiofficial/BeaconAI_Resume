import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/providers/cover_letter_provider.dart';
import 'package:beaconai_resume/services/hive_service.dart';
import 'package:beaconai_resume/screens/my_documents_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ISSUE 1 — generated cover letters were invisible on Home and in My
// Documents. Root cause: both screens' data models were Resume-only.
// DocFilterType.coverLetter existed as a selectable filter option (with a
// "Cover Letters" label) but nothing ever fed it real data — My Documents'
// entire list came from a List<Resume>, and Dashboard had no cover-letter
// section or card widget at all. The save path itself
// (CoverLetterBuilderScreen._onSave -> HiveService.coverLetterBox.put) was
// already correct; this was purely a missing read/display path.
//
// coverLetterListProvider mirrors resumeListProvider's Hive-listenable
// reactivity pattern — both screens now watch it, so a newly-saved cover
// letter appears without needing an app restart, same as a newly-saved
// resume already does.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir =
        Directory.systemTemp.createTempSync('beaconai_cover_letter_vis_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(AppConstants.resumeTypeId)) {
      Hive.registerAdapter(ResumeAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.coverLetterTypeId)) {
      Hive.registerAdapter(CoverLetterAdapter());
    }
    await Hive.openBox<Resume>(AppConstants.resumeBox);
    await Hive.openBox<CoverLetter>(AppConstants.coverLetterBox);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
      'coverLetterListProvider reflects a newly-saved cover letter without '
      'needing to be re-created — the same reactive mechanism '
      'resumeListProvider already uses, proving no app restart is needed',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final states = <List<CoverLetter>>[];
    container.listen(
      coverLetterListProvider,
      (previous, next) => states.add(next),
      fireImmediately: true,
    );

    expect(states.single, isEmpty);

    // Simulates CoverLetterBuilderScreen._onSave's exact write.
    await HiveService.coverLetterBox.put(
      'cl1',
      CoverLetter(
        id: 'cl1',
        resumeId: 'r1',
        jobDescription: 'Senior Network Systems Engineer at Acme Networks',
        content: 'Dear Hiring Manager, ...',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    expect(states.last.length, 1,
        reason: 'the provider must pick up the new Hive entry immediately '
            'via the box listenable, with no manual refresh/restart');
    expect(states.last.first.id, 'cl1');
  });

  group('My Documents widget rendering', () {
    // Seeded here, in setUp() — NOT inside the testWidgets() body below.
    // See test/widget_test.dart's comment: a real async Hive write issued
    // from inside a testWidgets() callback hangs indefinitely, because
    // TestWidgetsFlutterBinding runs the test body in a zone that doesn't
    // drive genuine OS-level I/O completion the way a plain async setUp()
    // does. The identical .put() calls resolve instantly from here.
    setUp(() async {
      final now = DateTime.now();
      await HiveService.resumeBox.put(
        'r1',
        Resume(
          id: 'r1',
          title: 'Tailored Resume',
          createdAt: now,
          updatedAt: now,
          isMaster: false,
          companyName: 'Acme Networks',
          roleTitle: 'Senior Network Systems Engineer',
        ),
      );
      await HiveService.coverLetterBox.put(
        'cl1',
        CoverLetter(
          id: 'cl1',
          resumeId: 'r1',
          jobDescription: 'Senior Network Systems Engineer at Acme Networks',
          content: 'Dear Hiring Manager, ...',
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    testWidgets(
        'a saved cover letter appears in My Documents and is findable by '
        "its linked tailored resume's company/role — the association the "
        'plan doc explicitly cares about', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: MyDocumentsScreen()),
        ),
      );
      // Bounded pumps, not pumpAndSettle() — see test/widget_test.dart's
      // comment: a connectivity_plus platform channel with no test-env
      // handler keeps scheduling frames forever, so pumpAndSettle() never
      // returns. A couple of bounded pumps is enough for the first frame
      // (and this screen has no async initState work) to settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Cover Letter — Senior Network Systems Engineer'),
          findsOneWidget,
          reason: 'the cover letter must be visible in the unified document '
              'list, not just the resume it was generated from');

      // Search by the LINKED resume's company name — CoverLetter itself
      // has no companyName field, so this only works if the association
      // was actually resolved when the list was built.
      await tester.enterText(find.byType(TextField), 'Acme Networks');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Cover Letter — Senior Network Systems Engineer'),
          findsOneWidget,
          reason: 'searching by the company name from the linked tailored '
              'resume must still find the cover letter');
    });
  });
}
