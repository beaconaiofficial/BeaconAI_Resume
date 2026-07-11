import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExternalLinkService — opens a plain external URL (e.g. the website footer
// link in Settings) via url_launcher, the same package BugReportService
// uses for its mailto link — this is the app's one URL-launching mechanism,
// not a second one. launchUrlFn is a swappable static field (same pattern
// as CloudflareWorkerService.client / BugReportService.launchUrlFn) so
// tests can fake a launch failure.
// ─────────────────────────────────────────────────────────────────────────────

class ExternalLinkService {
  ExternalLinkService._();

  @visibleForTesting
  static Future<bool> Function(Uri uri) launchUrlFn =
      (uri) => launchUrl(uri, mode: LaunchMode.platformDefault);

  /// Returns true if [url] was successfully launched. False means the
  /// caller should fall back to showing it as plain, copyable text.
  static Future<bool> open(String url) async {
    try {
      return await launchUrlFn(Uri.parse(url));
    } catch (_) {
      return false;
    }
  }
}
