import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/services/age_signal_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Age assurance — result parsing, bracket classification, the approved
// behavior matrix, and the never-throws fetch() contract against a mock
// MethodChannel.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgeSignalResult.fromPlatform (defensive parsing)', () {
    test('well-formed shared payload', () {
      final r = AgeSignalResult.fromPlatform(
          {'status': 'shared', 'ageLower': 13, 'ageUpper': 15});
      expect(r.status, AgeSignalStatus.shared);
      expect(r.ageLower, 13);
      expect(r.ageUpper, 15);
      expect(r.bracket, AgeBracketEnum.age13to15);
    });

    test('every native status string maps', () {
      for (final s in AgeSignalStatus.values) {
        expect(AgeSignalResult.fromPlatform({'status': s.name}).status, s);
      }
    });

    test('null / non-map payloads become error, never throw', () {
      for (final raw in <Object?>[null, 'shared', 42, ['shared'], true]) {
        final r = AgeSignalResult.fromPlatform(raw);
        expect(r.status, AgeSignalStatus.error, reason: '$raw');
        expect(r.errorCode, startsWith('MALFORMED_PAYLOAD_'));
      }
    });

    test('missing / unknown / non-string status becomes error', () {
      expect(AgeSignalResult.fromPlatform(<String, Object?>{}).status,
          AgeSignalStatus.error);
      expect(AgeSignalResult.fromPlatform({'status': 'SHARED'}).status,
          AgeSignalStatus.error);
      expect(AgeSignalResult.fromPlatform({'status': 1}).status,
          AgeSignalStatus.error);
    });

    test('missing age fields on shared → no bracket', () {
      final r = AgeSignalResult.fromPlatform({'status': 'shared'});
      expect(r.status, AgeSignalStatus.shared);
      expect(r.ageLower, isNull);
      expect(r.ageUpper, isNull);
      expect(r.bracket, isNull);
    });

    test('wrong-typed / out-of-range ages are dropped, not cast', () {
      final r = AgeSignalResult.fromPlatform({
        'status': 'shared',
        'ageLower': '13',
        'ageUpper': -4,
      });
      expect(r.ageLower, isNull);
      expect(r.ageUpper, isNull);

      final r2 = AgeSignalResult.fromPlatform(
          {'status': 'shared', 'ageLower': 16.5, 'ageUpper': 999});
      expect(r2.ageLower, isNull);
      expect(r2.ageUpper, isNull);
    });

    test('integral doubles are accepted', () {
      final r = AgeSignalResult.fromPlatform(
          {'status': 'shared', 'ageLower': 18.0, 'ageUpper': null});
      expect(r.ageLower, 18);
      expect(r.bracket, AgeBracketEnum.adult);
    });

    test('non-string errorCode is stringified; map with Object keys works', () {
      final r = AgeSignalResult.fromPlatform(
          <Object?, Object?>{'status': 'error', 'errorCode': -3});
      expect(r.status, AgeSignalStatus.error);
      expect(r.errorCode, '-3');
    });

    test('bounds on a non-shared status never yield a bracket', () {
      final r = AgeSignalResult.fromPlatform(
          {'status': 'notApplicable', 'ageLower': 10, 'ageUpper': 12});
      expect(r.bracket, isNull);
    });
  });

  group('classifyAgeRange (younger bracket wins)', () {
    final cases = <(int?, int?), AgeBracketEnum?>{
      (null, null): null,
      (0, 12): AgeBracketEnum.under13,
      (0, null): AgeBracketEnum.under13, // iOS nil lowerBound sent as 0
      (null, 12): AgeBracketEnum.under13,
      (13, 15): AgeBracketEnum.age13to15,
      (16, 17): AgeBracketEnum.age16to17,
      (18, null): AgeBracketEnum.adult,
      (18, 18): AgeBracketEnum.adult,
      (21, null): AgeBracketEnum.adult,
      // Straddling regulatory bands → younger bracket.
      (13, 17): AgeBracketEnum.age13to15,
      (10, 17): AgeBracketEnum.under13,
      (16, null): AgeBracketEnum.age16to17,
      (13, null): AgeBracketEnum.age13to15,
      (12, 15): AgeBracketEnum.under13,
      // Inconsistent.
      (17, 13): null,
    };
    cases.forEach((range, expected) {
      test('${range.$1}–${range.$2} → $expected', () {
        expect(classifyAgeRange(range.$1, range.$2), expected);
      });
    });
  });

  group('behavior matrix', () {
    test('restricted mode = every signaled minor; no ads for any of them', () {
      expect(AgeBracketEnum.unknown.isRestricted, isFalse);
      expect(AgeBracketEnum.adult.isRestricted, isFalse);
      expect(AgeBracketEnum.under13.isRestricted, isTrue);
      expect(AgeBracketEnum.age13to15.isRestricted, isTrue);
      expect(AgeBracketEnum.age16to17.isRestricted, isTrue);
    });

    test('AI blocked for under-13 always; teens follow the single flag', () {
      expect(AgeBracketEnum.unknown.isAiBlocked, isFalse);
      expect(AgeBracketEnum.adult.isAiBlocked, isFalse);
      expect(AgeBracketEnum.under13.isAiBlocked, isTrue);
      expect(AgeBracketEnum.age13to15.isAiBlocked,
          !AppConstants.aiEnabledForSignaledTeens);
      expect(AgeBracketEnum.age16to17.isAiBlocked,
          !AppConstants.aiEnabledForSignaledTeens);
    });

    test('shipping default: AI disabled for signaled teens', () {
      expect(AppConstants.aiEnabledForSignaledTeens, isFalse);
    });
  });

  group('resolveStoredBracket (keep-last rule)', () {
    const minor = AgeBracketEnum.age13to15;

    AgeSignalResult r(AgeSignalStatus s, [int? lo, int? hi]) =>
        AgeSignalResult(status: s, ageLower: lo, ageUpper: hi);

    test('error / unavailable / notApplicable / verificationRequired keep', () {
      for (final s in [
        AgeSignalStatus.error,
        AgeSignalStatus.unavailable,
        AgeSignalStatus.notApplicable,
        AgeSignalStatus.verificationRequired,
      ]) {
        expect(resolveStoredBracket(r(s), minor), isNull, reason: s.name);
      }
    });

    test('only explicit notShared resets to unknown', () {
      expect(resolveStoredBracket(r(AgeSignalStatus.notShared), minor),
          AgeBracketEnum.unknown);
    });

    test('shared range replaces; shared without usable range keeps', () {
      expect(resolveStoredBracket(r(AgeSignalStatus.shared, 18), minor),
          AgeBracketEnum.adult);
      expect(resolveStoredBracket(r(AgeSignalStatus.shared), minor), isNull);
    });

    test('definitive = the store/OS actually answered', () {
      expect(isDefinitiveAgeSignal(r(AgeSignalStatus.error)), isFalse);
      expect(isDefinitiveAgeSignal(r(AgeSignalStatus.unavailable)), isFalse);
      expect(isDefinitiveAgeSignal(r(AgeSignalStatus.notApplicable)), isTrue);
      expect(isDefinitiveAgeSignal(r(AgeSignalStatus.notShared)), isTrue);
      expect(isDefinitiveAgeSignal(r(AgeSignalStatus.shared, 18)), isTrue);
    });
  });

  group('AgeSignalService.fetch (mock MethodChannel, never throws)', () {
    const channel = MethodChannel('test/age_signals');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    void mock(Future<Object?>? Function(MethodCall call) handler) {
      messenger.setMockMethodCallHandler(channel, handler);
    }

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('production channel name matches the native bridges', () {
      expect(AppConstants.ageSignalsChannel, 'dev.getbeaconai/age_signals');
    });

    test('shared payload round-trips', () async {
      String? method;
      mock((call) async {
        method = call.method;
        return {'status': 'shared', 'ageLower': 16, 'ageUpper': 17};
      });
      final r = await AgeSignalService(channel: channel, isWeb: false).fetch();
      expect(method, 'fetch');
      expect(r.bracket, AgeBracketEnum.age16to17);
    });

    test('PlatformException → error', () async {
      mock((_) async => throw PlatformException(code: 'BOOM'));
      final r = await AgeSignalService(channel: channel, isWeb: false).fetch();
      expect(r.status, AgeSignalStatus.error);
      expect(r.errorCode, 'PLATFORM_BOOM');
    });

    test('no native handler (MissingPluginException) → unavailable', () async {
      final r = await AgeSignalService(channel: channel, isWeb: false).fetch();
      expect(r.status, AgeSignalStatus.unavailable);
      expect(r.errorCode, 'MISSING_PLUGIN');
    });

    test('bridge that never replies → DART_TIMEOUT error', () async {
      mock((_) => Completer<Object?>().future);
      final r = await AgeSignalService(
        channel: channel,
        isWeb: false,
        timeout: const Duration(milliseconds: 50),
      ).fetch();
      expect(r.status, AgeSignalStatus.error);
      expect(r.errorCode, 'DART_TIMEOUT');
    });

    test('malformed reply → error', () async {
      mock((_) async => 'not a map');
      final r = await AgeSignalService(channel: channel, isWeb: false).fetch();
      expect(r.status, AgeSignalStatus.error);
    });

    test('web no-ops without touching the channel', () async {
      var called = false;
      mock((_) async {
        called = true;
        return {'status': 'shared', 'ageLower': 10, 'ageUpper': 12};
      });
      final r = await AgeSignalService(channel: channel, isWeb: true).fetch();
      expect(called, isFalse);
      expect(r.status, AgeSignalStatus.unavailable);
      expect(r.errorCode, 'WEB');
    });
  });
}
