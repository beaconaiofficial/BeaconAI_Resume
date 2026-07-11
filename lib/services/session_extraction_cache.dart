import 'dart:collection';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../utils/app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SessionExtractionCache — always-on, in-memory-only protection against
// re-billing an extraction call for content that was already successfully
// extracted earlier in the same app session. Distinct from
// DevExtractionCache (that one is dev-only, Hive-backed, and gated behind a
// hardcoded-off flag; this one is production-safe and always active).
//
// Covers:
//   - retry after a downstream (parsing/sanitization/UI) failure, where the
//     extraction call itself already succeeded
//   - backing out of the upload flow and re-uploading the same file
//   - rapid double-tap firing two calls before the first resolves (via the
//     in-flight Future dedup below — this is a distinct problem from
//     caching, since both taps can check the cache before either result is
//     stored)
//
// Deliberately NOT here: no persistence (plain in-memory Map, empty by
// construction on every app launch — not an explicit clear-on-launch step),
// no cross-session/cross-device sharing, no staleness/versioning (nothing
// survives past the current process, so there's no scenario where a cached
// entry reflects stale prompt logic), no caching of failed/errored calls.
// ─────────────────────────────────────────────────────────────────────────────

class SessionExtractionCache {
  SessionExtractionCache._();

  static const int _maxEntries = 20;

  // Insertion order = recency order: a cache hit re-inserts its key at the
  // end, so the key at the front is always the least-recently-used one —
  // that's what gets evicted when the cap is exceeded.
  static final LinkedHashMap<String, String> _cache =
      LinkedHashMap<String, String>();

  // A second identical request (e.g. a double-tap) awaits the same Future
  // instead of firing a new network call. Removed once the call settles,
  // success or failure.
  static final Map<String, Future<String>> _inFlight = {};

  static String _hashOf(List<int> content) => sha256.convert(content).toString();

  static String _keyFor(String label, String contentHash) =>
      '$label:$contentHash';

  /// Runs [call] and returns its result, reusing a prior successful result
  /// for identical [content] + [label] within this app session, and
  /// collapsing concurrent identical requests into a single in-flight call.
  /// A failed/errored [call] is never cached — the next call for the same
  /// content hits the network again.
  static Future<String> cachedOrCall({
    required String label,
    required List<int> content,
    required Future<String> Function() call,
  }) async {
    final hash = _hashOf(content);
    final key = _keyFor(label, hash);

    final cached = _cache[key];
    if (cached != null) {
      // Touch: re-insert at the end so this stays the most-recently-used
      // entry, per the LRU eviction order documented on _cache above.
      _cache.remove(key);
      _cache[key] = cached;
      devLog('[SESSION CACHE] Reused extraction for '
          '${hash.substring(0, 8)}… — no API call made');
      return cached;
    }

    final inFlight = _inFlight[key];
    if (inFlight != null) {
      devLog('[SESSION CACHE] Request already in flight for '
          '${hash.substring(0, 8)}… — awaiting it instead of firing a new call');
      return inFlight;
    }

    final future = _runAndCache(key, call);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<String> _runAndCache(
      String key, Future<String> Function() call) async {
    // If call() throws, this line never completes and _store is never
    // reached — the exception propagates to cachedOrCall's caller normally,
    // and nothing gets cached for a failed/errored request.
    final result = await call();
    _store(key, result);
    return result;
  }

  static void _store(String key, String result) {
    _cache.remove(key); // drop any stale position before re-inserting
    _cache[key] = result;
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first); // oldest = least-recently-used
    }
  }

  /// Test-only: reset all in-memory state between tests. Never call this
  /// from production code — the whole point of this cache is that it's
  /// never cleared except by the app process ending.
  @visibleForTesting
  static void resetForTesting() {
    _cache.clear();
    _inFlight.clear();
  }
}
