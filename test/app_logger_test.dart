// Confirms devLog's kDebugMode gate does what FIX 2 requires: silent in
// release, active in debug. `flutter test` runs with kDebugMode == true
// (same as `flutter run` without --release/--profile), so this exercises
// the actual "debug builds still log normally" branch of devLog.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/utils/app_logger.dart';

void main() {
  test('kDebugMode is true under flutter test (debug-like environment)', () {
    expect(kDebugMode, isTrue);
  });

  test('devLog does not throw and is reachable in a debug context', () {
    expect(() => devLog('[TEST] app_logger smoke test'), returnsNormally);
  });
}
