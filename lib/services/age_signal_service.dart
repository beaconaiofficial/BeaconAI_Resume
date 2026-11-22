import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../models/app_enums.dart';
import '../utils/app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AgeSignalService
//
// Reads an age RANGE from the app store / OS (Play Age Signals on Android,
// Declared Age Range on iOS 26.2+) via the native bridges
// AgeSignalsChannel.kt / AgeSignalsChannel.swift. Web has no equivalent and
// always reports "unavailable".
//
// Privacy contract: the result is reduced to an [AgeBracketEnum] and stored
// only in on-device Hive. Nothing here — bounds, bracket, or status — may be
// sent to the Cloudflare Worker, Claude, RevenueCat, AdMob, analytics, logs
// in release builds, or backup exports.
//
// Failure contract (P0: no silent failures, never block launch):
// fetch() NEVER throws. Every exception, timeout, missing plugin or malformed
// payload becomes an [AgeSignalResult] with status error/unavailable and a
// diagnostic code logged behind kDebugMode with the [AGE SIGNAL] tag.
// ─────────────────────────────────────────────────────────────────────────────

/// What the store/OS said. Mirrors the native "status" strings.
enum AgeSignalStatus {
  /// Age range shared; see ageLower/ageUpper.
  shared,

  /// The user (or guardian) explicitly declined to share. The only status
  /// that resets a stored bracket to unknown.
  notShared,

  /// Android: mandatory sharing applies but the user must verify first.
  verificationRequired,

  /// Mandatory sharing / age features don't apply to this user, or the OS is
  /// too old to check (iOS < 26.2). No prompt was shown.
  notApplicable,

  /// API/OS/plugin not available (web, no activity, old Play Store, …).
  unavailable,

  /// Exception or timeout.
  error,
}

class AgeSignalResult {
  const AgeSignalResult({
    required this.status,
    this.ageLower,
    this.ageUpper,
    this.errorCode,
  });

  const AgeSignalResult.unavailable(String code)
      : this(status: AgeSignalStatus.unavailable, errorCode: code);

  const AgeSignalResult.error(String code)
      : this(status: AgeSignalStatus.error, errorCode: code);

  final AgeSignalStatus status;

  /// Inclusive lower bound. Only meaningful when [status] is shared.
  final int? ageLower;

  /// Inclusive upper bound; null for the open top band (e.g. 18+).
  final int? ageUpper;

  /// Diagnostic only — never persisted, never sent anywhere.
  final String? errorCode;

  /// Parses the native reply. Every field is guarded: unexpected types,
  /// unknown status strings and out-of-range numbers are tolerated, never
  /// cast blindly.
  factory AgeSignalResult.fromPlatform(Object? raw) {
    if (raw is! Map) {
      return AgeSignalResult.error(
          'MALFORMED_PAYLOAD_${raw == null ? 'null' : raw.runtimeType}');
    }
    final statusRaw = raw['status'];
    final status = _parseStatus(statusRaw);
    final errorRaw = raw['errorCode'];
    final errorCode = errorRaw is String ? errorRaw : errorRaw?.toString();
    if (status == null) {
      return AgeSignalResult(
        status: AgeSignalStatus.error,
        errorCode: 'UNKNOWN_STATUS_$statusRaw',
      );
    }
    return AgeSignalResult(
      status: status,
      ageLower: _parseAge(raw['ageLower']),
      ageUpper: _parseAge(raw['ageUpper']),
      errorCode: errorCode,
    );
  }

  static AgeSignalStatus? _parseStatus(Object? value) {
    if (value is! String) return null;
    for (final s in AgeSignalStatus.values) {
      if (s.name == value) return s;
    }
    return null;
  }

  /// Accepts int or an integral num; rejects negatives and absurd values.
  static int? _parseAge(Object? value) {
    int? n;
    if (value is int) {
      n = value;
    } else if (value is num && value.isFinite && value == value.roundToDouble()) {
      n = value.toInt();
    }
    if (n == null || n < 0 || n > 150) return null;
    return n;
  }

  /// The bracket this result implies, or null if it carries no usable range.
  AgeBracketEnum? get bracket => status == AgeSignalStatus.shared
      ? classifyAgeRange(ageLower, ageUpper)
      : null;

  @override
  String toString() =>
      'AgeSignalResult(${status.name}${errorCode != null ? ', $errorCode' : ''})';
}

/// Maps an inclusive age range to a bracket. When the range straddles
/// brackets (the OS may substitute its own regulatory gates, e.g. 13–17 or
/// 16+), the YOUNGER bracket wins. Returns null when there is no usable data
/// (both bounds null) or the range is inconsistent (upper < lower).
AgeBracketEnum? classifyAgeRange(int? lower, int? upper) {
  if (lower == null && upper == null) return null;
  final low = lower ?? 0;
  if (upper != null && upper < low) return null;
  if (low >= 18) return AgeBracketEnum.adult;
  if (low < 13) return AgeBracketEnum.under13;
  if (low < 16) return AgeBracketEnum.age13to15;
  return AgeBracketEnum.age16to17;
}

/// Decides what to store after a fetch, given the currently stored bracket.
/// Returns null when the stored bracket must be KEPT:
///   - error / timeout / unavailable → keep (a network blip must never turn a
///     known minor back into "unknown")
///   - notApplicable / verificationRequired → keep (no new information)
///   - shared but no usable range → keep
/// Only an explicit notShared resets to unknown; a shared range replaces it.
AgeBracketEnum? resolveStoredBracket(
    AgeSignalResult result, AgeBracketEnum current) {
  switch (result.status) {
    case AgeSignalStatus.shared:
      return result.bracket; // null (keep) when the range is unusable
    case AgeSignalStatus.notShared:
      return AgeBracketEnum.unknown;
    case AgeSignalStatus.verificationRequired:
    case AgeSignalStatus.notApplicable:
    case AgeSignalStatus.unavailable:
    case AgeSignalStatus.error:
      return null;
  }
}

/// True when the store/OS actually answered (worth stamping
/// ageSignalCheckedAt). Errors and unavailability don't count.
bool isDefinitiveAgeSignal(AgeSignalResult result) =>
    result.status != AgeSignalStatus.error &&
    result.status != AgeSignalStatus.unavailable;

class AgeSignalService {
  AgeSignalService({
    MethodChannel? channel,
    bool? isWeb,
    this.timeout = defaultTimeout,
  })  : _channel = channel ?? const MethodChannel(AppConstants.ageSignalsChannel),
        _isWeb = isWeb ?? kIsWeb;

  /// Dart-side ceiling. Longer than the native per-step ceilings (15 s quick
  /// steps + 180 s prompt step) so the native side normally answers first;
  /// this only catches a bridge that never replies.
  static const Duration defaultTimeout = Duration(seconds: 240);

  final MethodChannel _channel;
  final bool _isWeb;
  final Duration timeout;

  /// Never throws. See the failure contract at the top of this file.
  Future<AgeSignalResult> fetch() async {
    if (_isWeb) {
      return _log(const AgeSignalResult.unavailable('WEB'));
    }
    try {
      final raw = await _channel
          .invokeMethod<Object?>('fetch')
          .timeout(timeout);
      return _log(AgeSignalResult.fromPlatform(raw));
    } on TimeoutException {
      return _log(const AgeSignalResult.error('DART_TIMEOUT'));
    } on MissingPluginException {
      return _log(const AgeSignalResult.unavailable('MISSING_PLUGIN'));
    } on PlatformException catch (e) {
      return _log(AgeSignalResult.error('PLATFORM_${e.code}'));
    } catch (e) {
      return _log(AgeSignalResult.error('DART_${e.runtimeType}'));
    }
  }

  AgeSignalResult _log(AgeSignalResult result) {
    // Status + diagnostic code only — never the age bounds.
    devLog('[AGE SIGNAL] fetch → $result');
    return result;
  }
}
