import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

// debugPrint is NOT stripped in release builds — per the Flutter SDK's own
// docs on debugPrint, it "logs to console even in release mode" and is
// readable via `adb logcat` on a production device. devLog is the only
// sanctioned way to log from this codebase: it gates on kDebugMode once,
// here, so call sites never need to repeat the check.
void devLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
