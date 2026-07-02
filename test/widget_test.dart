// Minimal smoke test for the real app root widget. The previous version of
// this file was the unmodified Flutter counter-app template (pumped a
// nonexistent MyApp(), looked for a counter and a '+' button) — dead
// scaffolding left over from initial project creation, unrelated to
// BeaconAI Resume.
//
// Seeds a fresh (privacyAccepted: false) UserSettings, which is exactly the
// first-launch state — no other Hive data required, since
// BeaconAIResumeApp.build() only reads userSettingsProvider before routing.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/main.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/user_settings.dart';
import 'package:beaconai_resume/services/hive_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('beaconai_widget_test');
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
    await Hive.openBox<UserSettings>(AppConstants.userSettingsBox);

    // Seed here, in setUp() — NOT inside the testWidgets() body below.
    // A real async Hive write issued from inside a testWidgets() callback
    // hangs indefinitely: TestWidgetsFlutterBinding runs the test body in a
    // zone that doesn't drive genuine OS-level I/O completion the way a
    // plain async setUp()/test() context does. The identical .put() call
    // resolves instantly from here.
    await HiveService.userSettingsBox
        .put(AppConstants.userSettingsKey, UserSettings.defaults());
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('app builds without throwing and shows the first-launch '
      'Privacy Policy gate', (tester) async {
    expect(HiveService.settings.privacyAccepted, isFalse,
        reason: 'first launch — privacy must not already be accepted');

    await tester.pumpWidget(
      const ProviderScope(child: BeaconAIResumeApp()),
    );
    // Bounded pumps, not pumpAndSettle(): the app-wide offline banner
    // subscribes to connectivity_plus's platform channel, which has no
    // handler registered in a widget-test environment — pumpAndSettle()
    // waits for every scheduled frame to stop, which never happens while
    // that channel keeps retrying, so it hangs indefinitely. A few bounded
    // pumps are enough for the initial route's first frame to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('I Agree'), findsOneWidget);
  });
}
