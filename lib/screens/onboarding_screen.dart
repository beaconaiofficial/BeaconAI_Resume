import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';
import '../providers/user_settings_provider.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OnboardingScreen
// Shown once after Privacy Policy acceptance, never again.
// Spec: 3-slide walkthrough. Skippable after slide 1.
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const int _totalPages = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _canSkip => _currentPage >= 1;
  bool get _isOnLastSlide => _currentPage == _totalPages - 1;

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish() async {
    await ref.read(userSettingsProvider.notifier).completeOnboarding();
    if (mounted) {
      Navigator.pushReplacementNamed(
          context, AppConstants.routeFirstResumeSetup);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: Skip button (hidden on slide 0) ───────────────────
            _TopBar(
              canSkip: _canSkip,
              onSkip: _finish,
            ),

            // ── Page content ───────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: const [
                  _SlideOne(),
                  _SlideTwo(),
                  _SlideThree(),
                ],
              ),
            ),

            // ── Dot indicators ─────────────────────────────────────────────
            _DotIndicator(
              total: _totalPages,
              current: _currentPage,
            ),

            const SizedBox(height: 16),

            // ── Bottom navigation ──────────────────────────────────────────
            _BottomNav(
              currentPage: _currentPage,
              totalPages: _totalPages,
              isOnLastSlide: _isOnLastSlide,
              onNext: _nextPage,
              onBack: _prevPage,
              onFinish: _finish,
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.canSkip, required this.onSkip});

  final bool canSkip;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Brand wordmark
          Text(
            'BeaconAI',
            style: GoogleFonts.playfairDisplay(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          // Skip — only visible after slide 1
          AnimatedOpacity(
            opacity: canSkip ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Semantics(
              label: 'Skip onboarding',
              excludeSemantics: !canSkip,
              child: TextButton(
                onPressed: canSkip ? onSkip : null,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slide One — Branding + value prop
// ─────────────────────────────────────────────────────────────────────────────

class _SlideOne extends StatelessWidget {
  const _SlideOne();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon illustration — parchment + quill brand icon concept
          _OnboardingIcon(
            icon: Icons.description_outlined,
            color: isDark ? AppColors.accentDark : AppColors.accentLightColor,
            backgroundColor: isDark
                ? AppColors.accentLightTintDark
                : AppColors.accentLightTint,
          ),

          const SizedBox(height: 40),

          Text(
            'BeaconAI Resume',
            style: GoogleFonts.playfairDisplay(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Text(
            'Build an ATS-optimized resume that gets past the filters and in front of the right people.',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slide Two — Upload your existing resume or start fresh
// ─────────────────────────────────────────────────────────────────────────────

class _SlideTwo extends StatelessWidget {
  const _SlideTwo();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _OnboardingIcon(
            icon: Icons.upload_file_outlined,
            color: isDark ? AppColors.accentDark : AppColors.accentLightColor,
            backgroundColor: isDark
                ? AppColors.accentLightTintDark
                : AppColors.accentLightTint,
          ),

          const SizedBox(height: 40),

          Text(
            'Start with what you have',
            style: GoogleFonts.playfairDisplay(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Text(
            'Upload your existing resume — PDF, Word, or even a photo — and AI extracts your experience automatically. Or start from scratch with guided prompts.',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Feature pills
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _FeaturePill(label: 'PDF'),
              _FeaturePill(label: 'Word'),
              _FeaturePill(label: 'Images'),
              _FeaturePill(label: 'Plain text'),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slide Three — Tailor to any job in minutes
// ─────────────────────────────────────────────────────────────────────────────

class _SlideThree extends StatelessWidget {
  const _SlideThree();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _OnboardingIcon(
            icon: Icons.track_changes_outlined,
            color: isDark ? AppColors.accentDark : AppColors.accentLightColor,
            backgroundColor: isDark
                ? AppColors.accentLightTintDark
                : AppColors.accentLightTint,
          ),

          const SizedBox(height: 40),

          Text(
            'Tailor it to any job in minutes',
            style: GoogleFonts.playfairDisplay(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Text(
            'Paste a job posting and AI rewrites your resume to match the role — reordering bullets, surfacing the right keywords, and closing skill gaps.',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // ATS score preview chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.successDark.withValues(alpha: 0.15)
                  : AppColors.successLight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? AppColors.successDark.withValues(alpha: 0.4)
                    : AppColors.successLight.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 18,
                  color:
                      isDark ? AppColors.successDark : AppColors.successLight,
                ),
                const SizedBox(width: 8),
                Text(
                  'ATS Score: 94 / 100',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color:
                        isDark ? AppColors.successDark : AppColors.successLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dot Indicator
// ─────────────────────────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.total, required this.current});

  final int total;
  final int current;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final inactive = Theme.of(context).colorScheme.outlineVariant;

    return Semantics(
      label: 'Step ${current + 1} of $total',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final isActive = i == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? accent : inactive,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Navigation
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentPage,
    required this.totalPages,
    required this.isOnLastSlide,
    required this.onNext,
    required this.onBack,
    required this.onFinish,
  });

  final int currentPage;
  final int totalPages;
  final bool isOnLastSlide;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Back button — hidden on first page
          if (currentPage > 0)
            Semantics(
              label: 'Go back',
              child: OutlinedButton(
                onPressed: onBack,
                child: const Text('Back'),
              ),
            )
          else
            const SizedBox(width: 80),

          const Spacer(),

          // Primary CTA
          if (isOnLastSlide)
            Semantics(
              label: 'Continue, set up your resume',
              child: ElevatedButton(
                onPressed: onFinish,
                child: const Text('Continue'),
              ),
            )
          else
            Semantics(
              label: 'Next',
              child: ElevatedButton(
                onPressed: onNext,
                child: const Text('Next'),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Onboarding Icon
// ─────────────────────────────────────────────────────────────────────────────

class _OnboardingIcon extends StatelessWidget {
  const _OnboardingIcon({
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });

  final IconData icon;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 48, color: color),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Feature Pill (slide 2)
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
