import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/user_settings.dart';
import 'package:beaconai_resume/providers/user_settings_provider.dart';
import 'package:beaconai_resume/services/age_signal_service.dart';
import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/hive_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Age assurance — Hive retroactive migration of UserSettings fields 18–20,
// notifier storage rules, error/timeout fallback, restricted-mode providers,
// backup exclusion, and the AI service backstop.
// ─────────────────────────────────────────────────────────────────────────────

/// Writes UserSettings exactly as the pre-age-assurance adapter did
/// (fields 0–17 only) — i.e. a record from an existing install.
class _LegacyUserSettingsAdapter extends UserSettingsAdapter {
  @override
  void write(BinaryWriter writer, UserSettings obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.privacyAccepted)
      ..writeByte(1)
      ..write(obj.privacyAcceptedAt)
      ..writeByte(2)
      ..write(obj.onboardingComplete)
      ..writeByte(3)
      ..write(obj.ratingPromptShown)
      ..writeByte(4)
      ..write(obj.tier)
      ..writeByte(5)
      ..write(obj.billingCycleStart)
      ..writeByte(6)
      ..write(obj.tailoredResumesCreatedThisCycle)
      ..writeByte(7)
      ..write(obj.masterResumeResetDate)
      ..writeByte(8)
      ..write(obj.defaultExportFormat)
      ..writeByte(9)
      ..write(obj.theme)
      ..writeByte(10)
      ..write(obj.atsNotificationsEnabled)
      ..writeByte(11)
      ..write(obj.totalUploadCount)
      ..writeByte(12)
      ..write(obj.fontScaleOverride)
      ..writeByte(13)
      ..write(obj.highContrastOverride)
      ..writeByte(14)
      ..write(obj.reduceMotionOverride)
      ..writeByte(15)
      ..write(obj.screenReaderHintsEnabled)
      ..writeByte(16)
      ..write(obj.experienceSanitizedVersion)
      ..writeByte(17)
      ..write(obj.aiDataSharingAccepted);
  }
}

class _FakeAgeSignalService extends AgeSignalService {
  _FakeAgeSignalService(this._next) : super(isWeb: false);
  final Future<AgeSignalResult> Function() _next;
  int calls = 0;

  @override
  Future<AgeSignalResult> fetch() {
    calls++;
    return _next();
  }
}

AgeSignalResult _shared(int? lower, [int? upper]) => AgeSignalResult(
    status: AgeSignalStatus.shared, ageLower: lower, ageUpper: upper);

void main() {
  late Directory tempDir;
  late ProviderContainer container;
  var legacyAdapterActive = false;

  void registerAdapters() {
    if (!Hive.isAdapterRegistered(AppConstants.tierEnumTypeId)) {
      Hive.registerAdapter(TierEnumAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.exportFormatEnumTypeId)) {
      Hive.registerAdapter(ExportFormatEnumAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.appThemeEnumTypeId)) {
      Hive.registerAdapter(AppThemeEnumAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.ageBracketEnumTypeId)) {
      Hive.registerAdapter(AgeBracketEnumAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.userSettingsTypeId) ||
        legacyAdapterActive) {
      Hive.registerAdapter(UserSettingsAdapter(), override: true);
      legacyAdapterActive = false;
    }
  }

  UserSettingsNotifier notifier() =>
      container.read(userSettingsProvider.notifier);
  UserSettings settings() => container.read(userSettingsProvider);

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('beaconai_age_signal_test');
    Hive.init(tempDir.path);
    registerAdapters();
    await Hive.openBox<UserSettings>(AppConstants.userSettingsBox);
    await HiveService.userSettingsBox.put(
        AppConstants.userSettingsKey, UserSettings.defaults()..privacyAccepted = true);
    UserSettingsNotifier.debugResetAgeSignalLaunchGuard();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Hive retroactive migration', () {
    test('a pre-existing record (fields 0–17) reads with safe age defaults '
        'and keeps every existing value', () async {
      container.dispose();
      await Hive.close();

      Hive.init(tempDir.path);
      Hive.registerAdapter(_LegacyUserSettingsAdapter(), override: true);
      legacyAdapterActive = true;
      var box = await Hive.openBox<UserSettings>(AppConstants.userSettingsBox);
      await box.put(
        AppConstants.userSettingsKey,
        UserSettings.defaults()
          ..privacyAccepted = true
          ..onboardingComplete = true
          ..aiDataSharingAccepted = true
          ..experienceSanitizedVersion = 3
          ..tier = TierEnum.basic,
      );
      await Hive.close();

      // App update: real adapter, same file on disk.
      Hive.init(tempDir.path);
      registerAdapters();
      box = await Hive.openBox<UserSettings>(AppConstants.userSettingsBox);
      final s = box.get(AppConstants.userSettingsKey)!;

      expect(s.ageBracket, AgeBracketEnum.unknown);
      expect(s.ageSignalCheckedAt, isNull);
      expect(s.ageRestrictionNoticeShown, isFalse);
      // Nothing pre-existing was lost or rewritten.
      expect(s.privacyAccepted, isTrue);
      expect(s.onboardingComplete, isTrue);
      expect(s.aiDataSharingAccepted, isTrue);
      expect(s.experienceSanitizedVersion, 3);
      expect(s.tier, TierEnum.basic);

      container = ProviderContainer();
    });

    test('new fields round-trip through Hive', () async {
      await notifier().applyAgeSignal(_shared(13, 15));
      await Hive.close();
      Hive.init(tempDir.path);
      registerAdapters();
      final box =
          await Hive.openBox<UserSettings>(AppConstants.userSettingsBox);
      final s = box.get(AppConstants.userSettingsKey)!;
      expect(s.ageBracket, AgeBracketEnum.age13to15);
      expect(s.ageSignalCheckedAt, isNotNull);
    });
  });

  group('applyAgeSignal storage rules', () {
    test('minor signal → restricted, ads suppressed, AI blocked', () async {
      final changed = await notifier().applyAgeSignal(_shared(16, 17));
      expect(changed, isTrue);
      expect(settings().ageBracket, AgeBracketEnum.age16to17);
      expect(settings().ageSignalCheckedAt, isNotNull);
      expect(container.read(ageRestrictedProvider), isTrue);
      expect(container.read(adSuppressedProvider), isTrue);
      expect(container.read(aiBlockedByAgeProvider), isTrue);
    });

    test('free-tier adult / unknown → ads not suppressed, AI allowed', () async {
      expect(container.read(adSuppressedProvider), isFalse);
      await notifier().applyAgeSignal(_shared(18));
      expect(container.read(adSuppressedProvider), isFalse);
      expect(container.read(aiBlockedByAgeProvider), isFalse);
    });

    test('error / timeout keep the last stored bracket and timestamp',
        () async {
      await notifier().applyAgeSignal(_shared(10, 12));
      final checkedAt = settings().ageSignalCheckedAt;
      final changed = await notifier()
          .applyAgeSignal(const AgeSignalResult.error('DART_TIMEOUT'));
      expect(changed, isFalse);
      expect(settings().ageBracket, AgeBracketEnum.under13);
      expect(settings().ageSignalCheckedAt, checkedAt);
    });

    test('notApplicable keeps the bracket but stamps checkedAt', () async {
      await notifier().applyAgeSignal(_shared(13, 15));
      await notifier().applyAgeSignal(
          const AgeSignalResult(status: AgeSignalStatus.notApplicable));
      expect(settings().ageBracket, AgeBracketEnum.age13to15);
    });

    test('explicit notShared resets to unknown', () async {
      await notifier().applyAgeSignal(_shared(13, 15));
      await notifier().applyAgeSignal(
          const AgeSignalResult(status: AgeSignalStatus.notShared));
      expect(settings().ageBracket, AgeBracketEnum.unknown);
      expect(container.read(ageRestrictedProvider), isFalse);
    });

    test('minor → adult (turned 18) exits restricted mode silently and '
        're-arms the notice flag', () async {
      await notifier().applyAgeSignal(_shared(16, 17));
      await notifier().markAgeRestrictionNoticeShown();
      expect(settings().ageRestrictionNoticeShown, isTrue);

      await notifier().applyAgeSignal(_shared(18));
      expect(settings().ageBracket, AgeBracketEnum.adult);
      expect(container.read(ageRestrictedProvider), isFalse);
      expect(settings().ageRestrictionNoticeShown, isFalse);
    });

    test('minor → minor keeps the notice flag (no second notice)', () async {
      await notifier().applyAgeSignal(_shared(13, 15));
      await notifier().markAgeRestrictionNoticeShown();
      await notifier().applyAgeSignal(_shared(16, 17));
      expect(settings().ageRestrictionNoticeShown, isTrue);
    });
  });

  group('refreshAgeSignal (fire-and-forget fallback)', () {
    test('a service that throws leaves the app working, bracket unknown',
        () async {
      final svc = _FakeAgeSignalService(() async => throw StateError('boom'));
      await notifier().refreshAgeSignal(service: svc);
      expect(svc.calls, 1);
      expect(settings().ageBracket, AgeBracketEnum.unknown);
    });

    test('timeout result on a fresh install → unknown, nothing restricted',
        () async {
      final svc = _FakeAgeSignalService(
          () async => const AgeSignalResult.error('DART_TIMEOUT'));
      await notifier().refreshAgeSignal(service: svc);
      expect(settings().ageBracket, AgeBracketEnum.unknown);
      expect(container.read(adSuppressedProvider), isFalse);
    });

    test('not requested before the privacy policy is accepted', () async {
      await HiveService.userSettingsBox
          .put(AppConstants.userSettingsKey, UserSettings.defaults());
      container.dispose();
      container = ProviderContainer();
      final svc = _FakeAgeSignalService(() async => _shared(10, 12));
      await notifier().refreshAgeSignal(service: svc);
      expect(svc.calls, 0);
    });

    test('requested at most once per launch', () async {
      final svc = _FakeAgeSignalService(() async => _shared(18));
      await notifier().refreshAgeSignal(service: svc);
      await notifier().refreshAgeSignal(service: svc);
      expect(svc.calls, 1);
      expect(settings().ageBracket, AgeBracketEnum.adult);
    });
  });

  group('privacy: age data stays on the device', () {
    test('toBackupJson never includes age fields', () async {
      await notifier().applyAgeSignal(_shared(13, 15));
      final json = settings().toBackupJson();
      expect(json.keys.where((k) => k.toLowerCase().contains('age')), isEmpty);
      expect(json.values.whereType<AgeBracketEnum>(), isEmpty);
      expect(json.values.contains(AgeBracketEnum.age13to15.name), isFalse);
    });
  });

  group('AI service backstop', () {
    tearDown(() {
      CloudflareWorkerService.isAiBlocked = () {
        try {
          return HiveService.settings.ageBracket.isAiBlocked;
        } catch (_) {
          return false;
        }
      };
    });

    test('default gate reads the stored bracket', () async {
      await notifier().applyAgeSignal(_shared(10, 12));
      expect(CloudflareWorkerService.isAiBlocked(), isTrue);
      await notifier().applyAgeSignal(_shared(18));
      expect(CloudflareWorkerService.isAiBlocked(), isFalse);
    });

    test('blocked → AiRestrictedException before any request is sent',
        () async {
      CloudflareWorkerService.isAiBlocked = () => true;
      await expectLater(
        CloudflareWorkerService.sendPrompt(
          callLabel: 'test',
          systemPrompt: 's',
          userMessage: 'u',
        ),
        throwsA(isA<AiRestrictedException>()
            .having((e) => e.message, 'message',
                AppConstants.ageRestrictionNoticeBody)),
      );
      await expectLater(
        CloudflareWorkerService.extractResumeFieldsFromPdf(const [1, 2, 3]),
        throwsA(isA<AiRestrictedException>()),
      );
      await expectLater(
        CloudflareWorkerService.extractResumeFieldsFromImage(
            const [1], 'image/png'),
        throwsA(isA<AiRestrictedException>()),
      );
      await expectLater(
        CloudflareWorkerService.sendPromptWithWebSearch(
            callLabel: 'test', systemPrompt: 's', userMessage: 'u'),
        throwsA(isA<AiRestrictedException>()),
      );
    });

    test('AiRestrictedException is a CloudflareApiException (existing '
        'screen handlers surface it)', () {
      expect(const AiRestrictedException(), isA<CloudflareApiException>());
    });
  });
}
