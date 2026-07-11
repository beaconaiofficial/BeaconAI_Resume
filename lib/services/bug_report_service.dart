import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BugReportService — builds and launches the "Report a Bug" mailto link.
//
// launchUrlFn/packageInfoFn are swappable static fields (same pattern as
// CloudflareWorkerService.client) so tests can fake a launch failure or a
// known version/build without touching url_launcher's platform interface.
// ─────────────────────────────────────────────────────────────────────────────

class BugReportService {
  BugReportService._();

  static const String supportEmail = 'beaconai.official@gmail.com';

  @visibleForTesting
  static Future<bool> Function(Uri uri) launchUrlFn =
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  @visibleForTesting
  static Future<PackageInfo> Function() packageInfoFn =
      PackageInfo.fromPlatform;

  static String get platformName {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.android:
        return 'Android';
      default:
        return 'Web';
    }
  }

  static Future<Uri> buildMailtoUri() async {
    final info = await packageInfoFn();
    final body = 'App version: ${info.version} (build ${info.buildNumber})\n'
        'Platform: $platformName\n\n'
        'Describe the issue:\n\n\n';
    return Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: {
        'subject': 'BeaconAI Resume - Bug Report',
        'body': body,
      },
    );
  }

  /// Returns true if a mail client was successfully launched. False means
  /// the caller should fall back to showing [supportEmail] as plain text.
  static Future<bool> sendBugReport() async {
    final uri = await buildMailtoUri();
    try {
      return await launchUrlFn(uri);
    } catch (_) {
      return false;
    }
  }
}
