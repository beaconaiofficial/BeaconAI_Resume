import 'package:flutter_test/flutter_test.dart';

import 'package:beaconai_resume/services/dev_extraction_cache.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIX 8 (efficiency audit) — the dev extraction cache must be verifiably off
// by default. DevExtractionCache._enabled is a hardcoded `false` compile-time
// constant; isActive is `_enabled && kDebugMode`, so with _enabled false the
// AND short-circuits to false regardless of kDebugMode's value in this test
// environment — this test doesn't depend on being run in a "debug-like" mode
// to be meaningful. Cache-hit behavior when active isn't covered here: it
// requires manually flipping the hardcoded _enabled constant, which is
// exactly the thing this test proves nobody has done.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  test('isActive is false by default (the cache is off unless a developer '
      'manually edits the source)', () {
    expect(DevExtractionCache.isActive, isFalse);
  });

  test('cachedOrCall never skips the real call while inactive — identical '
      'content, called twice, invokes call() twice', () async {
    var callCount = 0;
    Future<String> realCall() async {
      callCount++;
      return 'result-$callCount';
    }

    final content = [1, 2, 3, 4, 5];

    final first = await DevExtractionCache.cachedOrCall(
      label: 'test', content: content, call: realCall);
    final second = await DevExtractionCache.cachedOrCall(
      label: 'test', content: content, call: realCall);

    expect(callCount, 2,
        reason: 'with the cache inactive, every call must reach the real '
            'API call — no caching behavior should be observable');
    expect(first, 'result-1');
    expect(second, 'result-2');
  });

  test('clear() is a no-op while inactive (never touches Hive)', () async {
    // Must not throw even though no Hive box has been opened/initialized
    // anywhere in this test file — confirms clear() short-circuits on
    // isActive before touching storage.
    await DevExtractionCache.clear();
  });
}
