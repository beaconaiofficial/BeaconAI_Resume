import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/user_settings.dart';
import 'package:beaconai_resume/providers/user_settings_provider.dart';
import 'package:beaconai_resume/services/hive_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIX 5 (efficiency audit) — regression test for the updateShouldNotify
// always-true rebuild-scope bug.
//
// UserSettings is a mutable HiveObject mutated in place via cascades
// (state = state..x = y), so by the time Riverpod's Notifier could compare
// previous vs next in updateShouldNotify, they're already the same mutated
// object — there is no way to tell what changed at that layer. That's why
// updateShouldNotify unconditionally returns true (see the comment on it).
// The actual narrowing has to happen downstream, via .select() — this test
// verifies a .select()'d listener watching one field does NOT fire when an
// unrelated field changes, and DOES fire when its own field changes. This is
// exactly the pattern main.dart's BeaconAIResumeApp now uses.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('beaconai_settings_scope_test');
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
    await HiveService.userSettingsBox
        .put(AppConstants.userSettingsKey, UserSettings.defaults());

    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('a .select()\'d listener on theme does NOT fire when an unrelated '
      'field (ratingPromptShown) changes', () async {
    var themeListenerCallCount = 0;
    container.listen(
      userSettingsProvider.select((s) => s.theme),
      (previous, next) => themeListenerCallCount++,
    );

    await container.read(userSettingsProvider.notifier).markRatingPromptShown();

    expect(themeListenerCallCount, 0,
        reason: 'dismissing the rating prompt must not notify a listener '
            'scoped to theme — this is the exact bug class that previously '
            'caused an unrelated settings change to rebuild the whole app '
            'shell');
  });

  test('a .select()\'d listener on theme DOES fire when theme actually '
      'changes', () async {
    var themeListenerCallCount = 0;
    container.listen(
      userSettingsProvider.select((s) => s.theme),
      (previous, next) => themeListenerCallCount++,
    );

    await container.read(userSettingsProvider.notifier).setTheme(AppThemeEnum.dark);

    expect(themeListenerCallCount, 1,
        reason: 'a listener scoped to theme must still fire when theme '
            'itself changes — select() narrows scope, it must not silently '
            'break real updates');
  });

  test('the underlying provider itself still notifies unconditionally on '
      'every mutation (documents why updateShouldNotify is hardcoded true, '
      'and why select() — not a smarter updateShouldNotify — is the fix)',
      () async {
    var rawListenerCallCount = 0;
    container.listen(
      userSettingsProvider,
      (previous, next) => rawListenerCallCount++,
    );

    await container.read(userSettingsProvider.notifier).markRatingPromptShown();
    await container.read(userSettingsProvider.notifier).setTheme(AppThemeEnum.dark);

    expect(rawListenerCallCount, 2,
        reason: 'an unscoped watch of userSettingsProvider itself still '
            'sees every mutation — this is expected and is exactly why '
            'call sites that only care about specific fields must use '
            'select(), not rely on the provider narrowing itself');
  });
}
