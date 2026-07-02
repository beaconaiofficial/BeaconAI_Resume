import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';
import '../providers/user_settings_provider.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PrivacyPolicyScreen
//
// Spec:
//  - Shown as the very first screen on first launch, before onboarding.
//  - Policy text is embedded at build time — no network dependency.
//  - 'I Agree' button required to proceed — app is fully blocked until tapped.
//  - UserSettings.privacyAccepted must be true before any other screen renders.
//  - Never shown again after acceptance.
// ─────────────────────────────────────────────────────────────────────────────

const _kPolicyText = '''
BeaconAI Resume — Privacy Policy

Last Updated: October 2024

This Privacy Policy explains how Beacon AI Inc. ("Beacon AI," "we," or "us") collects, uses, and discloses information about you. This Privacy Policy applies when you use our websites, Beacon AI Inc web application, Beacon AI Inc downloadable software application, and any other online products and services that link to this Privacy Policy (collectively, our "Services"), contact our customer service team, engage with us on social media or other online forums, or otherwise interact with us.

We may change this Privacy Policy from time to time. If we make changes, we will notify you by revising the date at the top of this policy and, in some cases, we may provide you with additional notice (such as adding a statement to our website or sending you a notification). We encourage you to review this Privacy Policy regularly to stay informed about our information practices and the choices available to you.


COLLECTION OF INFORMATION

Information You Provide to Us

We collect information you provide directly to us. For example, you may share information directly with us when you register for an account, fill out a form, submit or post content through our Services, make a purchase, communicate with us via third-party platforms, including by email, participate in a contest or promotion, contact us through our Services, or otherwise communicate with us. The types of personal information we may collect include your name, organization name, email address, postal address, phone number, credit card and other payment information, and any other information you choose to provide.

Information We Collect Automatically When You Interact with Us

When you access or use our Services or otherwise transact business with us, we automatically collect certain information, including:

• Activity Information: We collect information about your activity on our Services, such as your download activity and how you interact with other users on the Services.

• Transactional Information: When you make a purchase, we collect information about the transaction, such as product or plan details, purchase price, and the date and location of the transaction.

• Device and Usage Information: We collect information about how you access our Services, including data about the device and network you use, such as your hardware model, operating system version, mobile network, IP address, unique device identifiers, browser type, and app version. We also collect information about your activity on our Services, such as access times, pages viewed, links clicked, and the page you visited before navigating to our Services.

• Information Collected by Cookies and Similar Tracking Technologies: We (and our service providers) use tracking technologies, such as cookies and web beacons, to collect information about you. Cookies are small data files stored on your hard drive or in device memory that help us improve our Services and your experience, see which areas and features of our Services are popular, and count visits. Web beacons (also known as "pixel tags" or "clear GIFs") are electronic images that we use on our Services and in our emails to help deliver cookies, count visits, and understand usage and campaign effectiveness.

Information We Collect from Other Sources

We obtain information from third-party sources. For example, we may collect information about you from data analytics providers. Additionally, if you create or log into your Beacon AI account through a third-party platform (such as Google or Microsoft), we will have access to certain information from that platform, such as your name, email address, and profile picture, in accordance with the authorization procedures determined by such platform.

Information We Derive

We may derive information or draw inferences about you based on the information we collect. For example, we may make inferences about your location based on your IP address.


USE OF INFORMATION

We use the information we collect to provide the products and services you requested and to administer your account. We also use the information we collect to:

• Maintain and improve our products and services;
• Process transactions and send you related information, including confirmations, receipts, and invoices;
• Personalize and improve your experience on our Services;
• Send you technical notices, security alerts, and support and administrative messages;
• Respond to your comments and questions and provide customer service;
• Communicate with you about products, services, and events offered by Beacon AI and others;
• Monitor and analyze trends, usage, and activities in connection with our Services;
• Detect, investigate, and prevent security incidents and other malicious, deceptive, fraudulent, or illegal activity;
• Debug to identify and repair errors in our Services;
• Comply with our legal and financial obligations.


SHARING OF INFORMATION

We share personal information in the following circumstances:

• We share personal information with vendors, service providers, and consultants that need access to personal information in order to perform services for us, such as companies that assist us with web hosting, payment processing, fraud prevention, customer service, and marketing and advertising.
• We may disclose personal information if we believe that disclosure is in accordance with, or required by, any applicable law or legal process, including lawful requests by public authorities to meet national security or law enforcement requirements.
• We may share personal information if we believe that your actions are inconsistent with our user agreements or policies, if we believe that you have violated the law, or if we believe it is necessary to protect the rights, property, and safety of Beacon AI, our users, the public, or others.
• We share personal information with our lawyers and other professional advisors where necessary to obtain advice or otherwise protect and manage our business interests.
• We may share personal information in connection with, or during negotiations concerning, any merger, sale of company assets, financing, or acquisition of all or a portion of our business by another company.
• We share personal information with your consent or at your direction.

We may also share aggregated or de-identified information that cannot reasonably be used to identify you.


ANALYTICS

We allow others to provide analytics services on our behalf with respect to the Services. These entities may use cookies, web beacons, device identifiers, and other technologies to collect information about your use of our Services and other websites and applications, including your IP address, operating system, web browser, mobile network information, pages viewed, time spent on pages or in apps, links clicked, and conversion information.


TRANSFER OF INFORMATION TO THE UNITED STATES AND OTHER COUNTRIES

Beacon AI Inc is headquartered in the United States, and we have operations and service providers in the United States or other countries. Therefore, we and our service providers may transfer your personal information to, or store or access it in, jurisdictions that may not provide levels of data protection that are equivalent to those of your home jurisdiction. We will take steps to ensure that your personal information receives an adequate level of protection in the jurisdictions in which we process it.


YOUR CHOICES

Account Information: If you register for an account with us, you may update and correct certain account information at any time by logging into your account. If you wish to deactivate your account, please email us at support@beaconai.co.

Cookies: Most web browsers are set to accept cookies by default. If you prefer, you can usually adjust your browser settings to remove or reject browser cookies.

Communications Preferences: You may opt out of receiving promotional or newsletter emails from Beacon AI Inc. by following the instructions in those communications.


CONTACT US

If you have any questions about this Privacy Policy, please contact us at support@beaconai.co.
''';

class PrivacyPolicyScreen extends ConsumerStatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  ConsumerState<PrivacyPolicyScreen> createState() =>
      _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends ConsumerState<PrivacyPolicyScreen> {
  bool _isAgreeing = false;
  bool _isReview = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    _isReview = args is Map && args['isReview'] == true;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Agreement ───────────────────────────────────────────────────────────────

  Future<void> _onAgree() async {
    if (_isAgreeing) return;
    setState(() => _isAgreeing = true);

    await ref.read(userSettingsProvider.notifier).acceptPrivacyPolicy();

    if (mounted) {
      if (_isReview) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, AppConstants.routeOnboarding);
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────────
            _PolicyHeader(isDark: isDark),

            // ── Content area ──────────────────────────────────────────────────
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Semantics(
                    label: 'Privacy policy content',
                    child: Text(
                      _kPolicyText,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        height: 1.7,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── I Agree footer ────────────────────────────────────────────────
            _AgreeFooter(
              isAgreeing: _isAgreeing,
              onAgree: _onAgree,
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _PolicyHeader extends StatelessWidget {
  const _PolicyHeader({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BeaconAI',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.accentDark : AppColors.accentLightColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Privacy Policy',
            style: GoogleFonts.playfairDisplay(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Please read and agree to continue using the app.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// I Agree Footer
// ─────────────────────────────────────────────────────────────────────────────

class _AgreeFooter extends StatelessWidget {
  const _AgreeFooter({
    required this.isAgreeing,
    required this.onAgree,
    required this.isDark,
  });

  final bool isAgreeing;
  final VoidCallback onAgree;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'By tapping "I Agree" you confirm you have read and accept this policy.',
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: Semantics(
              label: 'I agree to the privacy policy',
              button: true,
              child: ElevatedButton(
                onPressed: isAgreeing ? null : onAgree,
                child: isAgreeing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('I Agree'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
