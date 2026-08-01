import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';
import '../providers/user_settings_provider.dart';
import '../services/external_link_service.dart';

/// One-time consent gate shown before the FIRST document (resume, job
/// posting, or certificate) is ever sent to Anthropic's Claude API for
/// extraction/generation. Apple 5.1.1(i)/5.1.2(i): third-party data sharing
/// must be explicitly named and consented to, not just implied by a general
/// privacy policy.
///
/// Call [ensureConsent] immediately before any such upload/extraction call.
/// It does nothing (returns true) once the user has already allowed it.
/// Manual (non-AI) resume entry must never call this — it never sends data
/// to Claude, so it stays fully usable even if the user chooses "Don't Allow".
class AiConsentDialog {
  AiConsentDialog._();

  static Future<bool> ensureConsent(BuildContext context, WidgetRef ref) async {
    if (ref.read(userSettingsProvider).aiDataSharingAccepted) return true;

    final allowed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Share with Anthropic\'s Claude AI?',
          style: GoogleFonts.playfairDisplay(
              fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To extract and generate resume content, the content of '
              'documents you upload (such as resumes, job postings, and '
              'certificates) is sent to Anthropic\'s Claude API for '
              'processing, so it can extract and generate resume content '
              'for you.',
              style: GoogleFonts.inter(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () =>
                  ExternalLinkService.open(AppConstants.privacyPolicyUrl),
              child: Text(
                'Privacy Policy',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Don\'t Allow'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (allowed != true) return false;

    await ref.read(userSettingsProvider.notifier).acceptAiDataSharing();
    return true;
  }
}
