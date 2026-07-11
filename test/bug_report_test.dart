// Report a Bug (Settings > Support): a mailto: link pre-filled with app
// version/build/platform, with a copyable-email fallback when no mail
// handler is available (the common case on web/desktop). launchUrlFn and
// packageInfoFn are swappable static fields (same pattern as
// CloudflareWorkerService.client) so these tests fake the platform launch
// without touching url_launcher's platform interface.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/models/user_settings.dart';
import 'package:beaconai_resume/screens/settings_screen.dart';
import 'package:beaconai_resume/services/bug_report_service.dart';
import 'package:beaconai_resume/services/hive_service.dart';

PackageInfo _fakeInfo() => PackageInfo(
      appName: 'BeaconAI Resume',
      packageName: 'dev.getbeaconai.beaconai_resume',
      version: '1.0.0',
      buildNumber: '11',
    );

void main() {
  final originalLaunch = BugReportService.launchUrlFn;
  final originalPackageInfo = BugReportService.packageInfoFn;

  setUp(() {
    BugReportService.packageInfoFn = () async => _fakeInfo();
  });

  tearDown(() {
    BugReportService.launchUrlFn = originalLaunch;
    BugReportService.packageInfoFn = originalPackageInfo;
  });

  group('BugReportService.buildMailtoUri', () {
    test('addresses the support email with the correct subject and a '
        'pre-filled body containing version, build, and platform', () async {
      final uri = await BugReportService.buildMailtoUri();

      expect(uri.scheme, 'mailto');
      expect(uri.path, BugReportService.supportEmail);
      expect(uri.queryParameters['subject'], 'BeaconAI Resume - Bug Report');

      final body = uri.queryParameters['body']!;
      expect(body, contains('App version: 1.0.0 (build 11)'));
      expect(body, contains('Platform: ${BugReportService.platformName}'));
      expect(body, contains('Describe the issue:'));
    });
  });

  group('BugReportService.sendBugReport', () {
    test('returns true and launches the exact mailto URI when the '
        'platform launch succeeds', () async {
      Uri? captured;
      BugReportService.launchUrlFn = (uri) async {
        captured = uri;
        return true;
      };

      final result = await BugReportService.sendBugReport();
      final expected = await BugReportService.buildMailtoUri();

      expect(result, isTrue);
      expect(captured, expected);
    });

    test('returns false when the platform launch reports failure '
        '(e.g. no mail app configured)', () async {
      BugReportService.launchUrlFn = (uri) async => false;

      expect(await BugReportService.sendBugReport(), isFalse);
    });

    test('returns false instead of throwing when the platform launch '
        'itself throws', () async {
      BugReportService.launchUrlFn = (uri) async =>
          throw PlatformException(code: 'no_handler');

      expect(await BugReportService.sendBugReport(), isFalse);
    });
  });

  group('Settings screen — Report a Bug row', () {
    late Directory tempDir;
    String? clipboardText;

    setUp(() async {
      clipboardText = null;
      // Explicit mock for the clipboard platform channel rather than
      // relying on TestWidgetsFlutterBinding's built-in handler — gives a
      // deterministic, synchronous result instead of a call that can hang
      // waiting on a response in this environment.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': clipboardText};
        }
        return null;
      });

      tempDir = Directory.systemTemp.createTempSync('beaconai_bug_report_test');
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
      if (!Hive.isAdapterRegistered(AppConstants.coverLetterTypeId)) {
        Hive.registerAdapter(CoverLetterAdapter());
      }
      if (!Hive.isAdapterRegistered(AppConstants.interviewStudyGuideTypeId)) {
        Hive.registerAdapter(InterviewStudyGuideAdapter());
      }
      await Hive.openBox<UserSettings>(AppConstants.userSettingsBox);
      await Hive.openBox<Resume>(AppConstants.resumeBox);
      await Hive.openBox<CoverLetter>(AppConstants.coverLetterBox);
      await Hive.openBox<InterviewStudyGuide>(
          AppConstants.interviewStudyGuideBox);
      await HiveService.userSettingsBox
          .put(AppConstants.userSettingsKey, UserSettings.defaults());
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // "Report a Bug" sits below the Account/Preferences/Accessibility/
    // Storage sections — below the default 800x600 test viewport's cache
    // extent, so ListView(children: [...])'s underlying SliverList won't
    // have built it yet. Scroll it into view before interacting, same as
    // a real device would need to.
    Future<void> pumpSettings(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Report a Bug'),
        200,
        scrollable: find.byType(Scrollable),
      );
    }

    testWidgets('is present with a Semantics label matching every other row',
        (tester) async {
      await pumpSettings(tester);

      expect(find.text('Report a Bug'), findsOneWidget);
      // Read the configured Semantics widget's properties directly rather
      // than the rendered/merged SemanticsNode tree (which needs a
      // semantics handle and mixes in Material/InkWell's own internal
      // Semantics wrappers) — this checks exactly what _SettingsTile sets:
      // the same Semantics(label: ..., button: true) wrapper every other
      // Settings row uses.
      final semanticsWidget = tester.widget<Semantics>(find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Report a Bug'));
      expect(semanticsWidget.properties.button, isTrue);
    });

    testWidgets('tapping it launches the mailto link and shows no fallback '
        'when the launch succeeds', (tester) async {
      var launchCalled = false;
      BugReportService.launchUrlFn = (uri) async {
        launchCalled = true;
        return true;
      };

      await pumpSettings(tester);
      await tester.tap(find.text('Report a Bug'));
      await tester.pump();
      await tester.pump();

      expect(launchCalled, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('falls back to a copyable-email dialog when the mail '
        'launch fails (mocked, not environment-dependent)', (tester) async {
      BugReportService.launchUrlFn = (uri) async => false;

      await pumpSettings(tester);
      await tester.tap(find.text('Report a Bug'));
      // Bounded pumps, not pumpAndSettle() — see widget_test.dart: a
      // platform channel retry loop in this environment never lets
      // pumpAndSettle() converge.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(BugReportService.supportEmail), findsOneWidget);

      await tester.tap(find.text('Copy Email'));
      await tester.pump();
      // Dialog-dismiss route transition, same reasoning as the open pumps
      // above — one immediate pump isn't enough for the exit animation.
      await tester.pump(const Duration(milliseconds: 300));

      expect(clipboardText, BugReportService.supportEmail);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
