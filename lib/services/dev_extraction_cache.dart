import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:hive_ce/hive.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DevExtractionCache — dev-only local cache for Claude document-extraction
// calls, keyed on a hash of the source document's raw content plus which
// extraction function was called. Re-uploading the same test document across
// iteration cycles hits this cache instead of billing another real API call.
//
// NEVER active outside local development. Two independent gates:
//   1. _enabled — a hardcoded `false` compile-time constant. Flip it to
//      `true` only in an uncommitted local change; never commit it as `true`.
//   2. kDebugMode — derived by the Flutter toolchain from the actual build
//      mode (dart.vm.product/dart.vm.profile), not something a developer can
//      forget to unset. Verified directly against the Flutter SDK source
//      (packages/flutter/lib/src/foundation/constants.dart): it is
//      unconditionally false in the output of every `flutter build
//      --release` / `--profile` command, regardless of what _enabled is set
//      to. Both must be true for the cache to activate — see [isActive].
// ─────────────────────────────────────────────────────────────────────────────

class DevExtractionCache {
  DevExtractionCache._();

  static const bool _enabled = false;

  /// True only in a local debug run with [_enabled] manually flipped to
  /// true. Every call site should route through [cachedOrCall] rather than
  /// checking this directly, but it's exposed for the debug-menu clear
  /// action to decide whether to show itself at all.
  static bool get isActive => _enabled && kDebugMode;

  static const String _boxName = 'dev_extraction_cache';

  static Future<Box<String>> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<String>(_boxName);
    }
    return Hive.openBox<String>(_boxName);
  }

  static String _hashOf(List<int> content) => sha256.convert(content).toString();

  static String _keyFor(String label, String contentHash) =>
      '$label:$contentHash';

  /// Runs [call] and returns its result, transparently caching by content
  /// hash + [label] when the dev cache is active. A cache hit never invokes
  /// [call] — no network request happens, no cost is billed. Inactive
  /// (production/non-debug/flag-off) short-circuits directly to `call()`
  /// with no Hive access at all, so there's no overhead or behavior change
  /// outside local development.
  static Future<String> cachedOrCall({
    required String label,
    required List<int> content,
    required Future<String> Function() call,
  }) async {
    if (!isActive) return call();

    final box = await _openBox();
    final hash = _hashOf(content);
    final key = _keyFor(label, hash);
    final cached = box.get(key);
    if (cached != null) {
      debugPrint('[DEV CACHE] Skipped API call — using cached extraction '
          'for $label (${hash.substring(0, 8)}…)');
      return cached;
    }

    final result = await call();
    await box.put(key, result);
    return result;
  }

  /// Clears every cached extraction. Wire to a debug-only menu action —
  /// never expose this in a release build. No-ops when the cache isn't
  /// active.
  static Future<void> clear() async {
    if (!isActive) return;
    final box = await _openBox();
    final count = box.length;
    await box.clear();
    debugPrint('[DEV CACHE] Cleared ($count entries removed)');
  }
}
