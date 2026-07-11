// Website footer link (Settings, below every real section): quiet,
// centered, tappable text opening getbeaconai.dev via url_launcher — the
// same package/pattern as the bug-report mailto link — with the same
// copyable-text fallback dialog when no browser handler is available
// (the common case on web/desktop). launchUrlFn is a swappable static
// field (same pattern as BugReportService.launchUrlFn) so these tests fake
// the platform launch without touching url_launcher's platform interface.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/models/user_settings.dart';
import 'package:beaconai_resume/screens/settings_screen.dart';
import 'package:beaconai_resume/services/bug_report_service.dart';
import 'package:beaconai_resume/services/external_link_service.dart';
import 'package:beaconai_resume/services/hive_service.dart';
import 'package:beaconai_resume/theme/app_theme.dart';

void main() {
  final originalExternalLaunch = ExternalLinkService.launchUrlFn;
  final originalBugReportLaunch = BugReportService.launchUrlFn;

  setUp(() {
    // The footer sits below Report a Bug, which fires on Settings load only
    // via user interaction — nothing to stub here, but keep bug-report
    // launches harmless in case a stray tap lands on it during scrolling.
    BugReportService.launchUrlFn = (uri) async => true;
  });

  tearDown(() {
    ExternalLinkService.launchUrlFn = originalExternalLaunch;
    BugReportService.launchUrlFn = originalBugReportLaunch;
  });

  group('ExternalLinkService.open', () {
    test('returns true and launches the exact URL when the platform launch '
        'succeeds', () async {
      Uri? captured;
      ExternalLinkService.launchUrlFn = (uri) async {
        captured = uri;
        return true;
      };

      final result = await ExternalLinkService.open('https://getbeaconai.dev');

      expect(result, isTrue);
      expect(captured, Uri.parse('https://getbeaconai.dev'));
    });

    test('returns false when the platform launch reports failure', () async {
      ExternalLinkService.launchUrlFn = (uri) async => false;
      expect(await ExternalLinkService.open('https://getbeaconai.dev'), isFalse);
    });

    test('returns false instead of throwing when the platform launch '
        'itself throws', () async {
      ExternalLinkService.launchUrlFn =
          (uri) async => throw PlatformException(code: 'no_handler');
      expect(await ExternalLinkService.open('https://getbeaconai.dev'), isFalse);
    });
  });

  group('Settings screen — website footer link', () {
    late Directory tempDir;
    String? clipboardText;

    setUp(() async {
      clipboardText = null;
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

      tempDir =
          Directory.systemTemp.createTempSync('beaconai_footer_link_test');
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

    const footerText =
        'For more information or to see our other apps, please visit '
        'getbeaconai.dev';

    Future<void> pumpSettings(WidgetTester tester, {bool dark = false}) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text(footerText),
        200,
        scrollable: find.byType(Scrollable),
      );
      // scrollUntilVisible only guarantees the widget is *found*, not
      // fully inside the 600px-tall default test viewport (it can land a
      // few px past the bottom edge, which fails tap()'s hit test).
      // ensureVisible scrolls precisely so the whole widget rect is
      // on-screen before any tap.
      await tester.ensureVisible(find.text(footerText));
      await tester.pump();
    }

    testWidgets('renders below every real section with a Semantics label',
        (tester) async {
      await pumpSettings(tester);

      expect(find.text(footerText), findsOneWidget);
      final semanticsWidget = tester.widget<Semantics>(find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').contains('getbeaconai.dev')));
      expect(semanticsWidget.properties.button, isTrue);
    });

    testWidgets(
        'uses the secondary text color (light mode), not the accent color '
        'used by real settings rows', (tester) async {
      await pumpSettings(tester, dark: false);

      final text = tester.widget<Text>(find.text(footerText));
      expect(text.style?.color, const Color(0xFF6B7280)); // secondaryTextLight
      expect(text.style?.fontSize, 11.5);
    });

    testWidgets('uses the secondary text color (dark mode), not the accent '
        'color used by real settings rows', (tester) async {
      await pumpSettings(tester, dark: true);

      final text = tester.widget<Text>(find.text(footerText));
      expect(text.style?.color, const Color(0xFF9CA3AF)); // secondaryTextDark
      expect(text.style?.fontSize, 11.5);
    });

    testWidgets('tapping it launches getbeaconai.dev and shows no fallback '
        'when the launch succeeds', (tester) async {
      Uri? captured;
      ExternalLinkService.launchUrlFn = (uri) async {
        captured = uri;
        return true;
      };

      await pumpSettings(tester);
      await tester.tap(find.text(footerText));
      await tester.pump();
      await tester.pump();

      expect(captured, Uri.parse('https://getbeaconai.dev'));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('falls back to a copyable-URL dialog when the browser '
        'launch fails (mocked, not environment-dependent)', (tester) async {
      ExternalLinkService.launchUrlFn = (uri) async => false;

      await pumpSettings(tester);
      await tester.tap(find.text(footerText));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('getbeaconai.dev'), findsWidgets);

      await tester.tap(find.text('Copy Link'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(clipboardText, 'getbeaconai.dev');
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
