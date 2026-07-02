import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../constants/app_constants.dart';
import '../models/app_enums.dart';
import '../models/resume.dart';
import '../providers/resume_provider.dart';
import '../providers/user_settings_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/hive_service.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen
//
// Spec §4 (Home / Dashboard):
//  - Master resume pinned at top.
//  - Tailored resumes below, sorted by most recently edited.
//  - FAB to create new tailored resume (Basic+ only — disabled not hidden for Free).
//  - 'Interview Tips' button visible to all tiers.
//  - 'My Documents' button in app bar.
//  - 30-day reset banner shown on app open when masterResumeResetDate reached.
//  - Offline banner: creation disabled, viewing enabled.
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _resetBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    // Check and reset billing cycle on dashboard open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(userSettingsProvider.notifier)
          .checkAndResetBillingCycleIfNeeded();
      ref.read(userSettingsProvider.notifier).syncTierFromRevenueCat();
    });
  }

  // ── 30-day reset handling ──────────────────────────────────────────────────

  Future<void> _onStartNewResume(Resume archivedMaster) async {
    // Archive the old master
    await ref
        .read(resumeListProvider.notifier)
        .archiveResume(archivedMaster.id);
    // Update the reset date to null (cleared)
    final settings = ref.read(userSettingsProvider);
    settings.masterResumeResetDate = null;
    await ref
        .read(userSettingsProvider.notifier)
        .checkAndResetBillingCycleIfNeeded();

    if (mounted) {
      Navigator.pushNamed(context, AppConstants.routeFirstResumeSetup);
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _onCreateTailored() {
    final tier = ref.read(currentTierProvider);
    final isOnline = ref.read(isOnlineProvider);

    if (!isOnline) {
      _showOfflineSnack();
      return;
    }

    // Allow access via subscription (Basic/Pro) OR an unused combo add-on.
    final hasUnusedAddOn = HiveService.addOnPurchaseBox.values.any(
      (p) => p.type == AddOnTypeEnum.coverLetterTailoredCombo && !p.used,
    );

    if (tier.isFree && !hasUnusedAddOn) {
      Navigator.pushNamed(context, AppConstants.routePaywall);
      return;
    }
    Navigator.pushNamed(context, AppConstants.routeCreateTailoredResume);
  }

  void _onInterviewTips() {
    final tier = ref.read(currentTierProvider);
    final route = switch (tier) {
      _ when tier.isPro => AppConstants.routeInterviewPrepPro,
      _ when tier.isBasic => AppConstants.routeInterviewPrepBasic,
      _ => AppConstants.routeInterviewTipsFree,
    };
    Navigator.pushNamed(context, route);
  }

  void _onUpgrade() {
    Navigator.pushNamed(context, AppConstants.routePaywall);
  }

  void _onAtsAnalyzer() {
    final tier = ref.read(currentTierProvider);
    if (tier.isFree) {
      Navigator.pushNamed(context, AppConstants.routePaywall);
      return;
    }
    final master = ref.read(activeMasterResumeProvider);
    Navigator.pushNamed(
      context,
      AppConstants.routeAtsAnalyzer,
      arguments: master != null ? {'resumeId': master.id} : null,
    );
  }

  void _showOfflineSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppConstants.offlineBannerMessage,
            style: GoogleFonts.inter(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(userSettingsProvider);
    final master = ref.watch(activeMasterResumeProvider);
    final tailored = ref.watch(activeTailoredResumesProvider);
    final tier = ref.watch(currentTierProvider);
    final isOnline = ref.watch(isOnlineProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final showResetBanner = !_resetBannerDismissed &&
        settings.isMasterResumeResetDue &&
        master != null;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: _buildAppBar(context, isDark),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(resumeListProvider),
        child: CustomScrollView(
          slivers: [
            // ── 30-day reset banner ──────────────────────────────────────
            if (showResetBanner)
              SliverToBoxAdapter(
                child: _ResetBanner(
                  master: master,
                  onStartNew: () => _onStartNewResume(master),
                  onDismiss: () => setState(() => _resetBannerDismissed = true),
                ),
              ),

            // ── Master resume section ─────────────────────────────────────
            SliverToBoxAdapter(
              child: _SectionHeader(
                label: 'Master Resume',
                action: master != null
                    ? TextButton(
                        onPressed: () => Navigator.pushNamed(
                          context,
                          AppConstants.routePreviewEdit,
                          arguments: {'resumeId': master.id},
                        ),
                        child: const Text('Edit'),
                      )
                    : null,
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: master != null
                    ? _ResumeCard(
                        resume: master,
                        isMaster: true,
                        isOnline: isOnline,
                        isDark: isDark,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppConstants.routePreviewEdit,
                          arguments: {'resumeId': master.id},
                        ),
                      )
                    : _EmptyMasterCard(
                        isDark: isDark,
                        onCreate: () => Navigator.pushNamed(
                            context, AppConstants.routeFirstResumeSetup),
                      ),
              ),
            ),

            // ── Quick actions row ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: _QuickActionsRow(
                tier: tier,
                isOnline: isOnline,
                isDark: isDark,
                onInterviewTips: _onInterviewTips,
                onAtsAnalyzer: _onAtsAnalyzer,
                onUpgrade: _onUpgrade,
              ),
            ),

            // ── Tailored resumes section ──────────────────────────────────
            SliverToBoxAdapter(
              child: _SectionHeader(
                label: 'Tailored Resumes',
                subtitle: tier.isBasic
                    ? '${settings.remainingTailoredSlots} slot${settings.remainingTailoredSlots == 1 ? '' : 's'} remaining this month'
                    : tier.isFree
                        ? 'Upgrade to Basic to create tailored resumes'
                        : null,
                action: tier.isPaid
                    ? TextButton(
                        onPressed: isOnline ? _onCreateTailored : null,
                        child: const Text('+ New'),
                      )
                    : null,
              ),
            ),

            if (tailored.isEmpty)
              SliverToBoxAdapter(
                child: _EmptyTailoredState(
                  tier: tier,
                  isDark: isDark,
                  onUpgrade: () =>
                      Navigator.pushNamed(context, AppConstants.routePaywall),
                  onCreate: _onCreateTailored,
                  isOnline: isOnline,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ResumeCard(
                        resume: tailored[i],
                        isMaster: false,
                        isOnline: isOnline,
                        isDark: isDark,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppConstants.routePreviewEdit,
                          arguments: {'resumeId': tailored[i].id},
                        ),
                      ),
                    ),
                    childCount: tailored.length,
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),

      // FAB — create tailored resume
      // Spec: disabled not hidden when offline or Free tier
      floatingActionButton: Semantics(
        label: tier.isFree
            ? 'Create tailored resume — upgrade required'
            : isOnline
                ? 'Create tailored resume'
                : 'Create tailored resume — requires internet connection',
        child: FloatingActionButton.extended(
          onPressed: _onCreateTailored,
          icon: Icon(
            tier.isFree ? Icons.lock_outline : Icons.add,
            size: 20,
          ),
          label: const Text('Tailored Resume'),
          backgroundColor: tier.isFree
              ? (isDark ? AppColors.borderDark : AppColors.borderLight)
              : null,
          foregroundColor: tier.isFree
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : null,
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, bool isDark) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: Text(
        AppConstants.appName,
        style: GoogleFonts.playfairDisplay(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      actions: [
        // My Documents
        Semantics(
          label: 'My Documents',
          child: IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: 'My Documents',
            onPressed: () =>
                Navigator.pushNamed(context, AppConstants.routeMyDocuments),
          ),
        ),
        // Settings
        Semantics(
          label: 'Settings',
          child: IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () =>
                Navigator.pushNamed(context, AppConstants.routeSettings),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 30-Day Reset Banner
// Spec §13: shown on next app open when reset date reached. No push notification.
// ─────────────────────────────────────────────────────────────────────────────

class _ResetBanner extends StatelessWidget {
  const _ResetBanner({
    required this.master,
    required this.onStartNew,
    required this.onDismiss,
  });

  final Resume master;
  final VoidCallback onStartNew;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Semantics(
      liveRegion: true,
      label:
          'Your master resume is ready for a refresh. Start a new one — the old version is safely archived.',
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.accentLightTintDark
              : AppColors.accentLightTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.refresh_outlined, size: 16, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Time for a resume refresh',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: onDismiss,
                  tooltip: 'Dismiss',
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'It\'s been 30 days. Your current resume is safely archived — '
              'start fresh to keep your content current.',
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onStartNew,
                child: const Text('Start New Resume'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Resume Card
// ─────────────────────────────────────────────────────────────────────────────

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({
    required this.resume,
    required this.isMaster,
    required this.isOnline,
    required this.isDark,
    required this.onTap,
  });

  final Resume resume;
  final bool isMaster;
  final bool isOnline;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final atsScore = ref.watch(atsScoreProvider(resume.id));
    final updatedLabel = _formatDate(resume.updatedAt);

    return Semantics(
      label:
          '${resume.displayTitle}, last edited $updatedLabel, ATS score $atsScore out of 100',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isMaster ? accent.withValues(alpha: 0.4) : border,
              width: isMaster ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              // ── Card header ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Document icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isMaster
                            ? Icons.description_outlined
                            : Icons.tune_outlined,
                        size: 20,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title + meta
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isMaster)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'MASTER',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  resume.displayTitle,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 4),

                          // Company / role for tailored
                          if (!isMaster &&
                              (resume.companyName != null ||
                                  resume.roleTitle != null))
                            Text(
                              [resume.roleTitle, resume.companyName]
                                  .where((s) => s != null)
                                  .join(' · '),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),

                          const SizedBox(height: 4),
                          Text(
                            'Edited $updatedLabel',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ATS score ring
                    _AtsScoreRing(score: atsScore, isDark: isDark),
                  ],
                ),
              ),

              // ── Card footer ─────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: border)),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    _CardAction(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppConstants.routePreviewEdit,
                        arguments: {'resumeId': resume.id},
                      ),
                    ),
                    _VerticalDivider(color: border),
                    _CardAction(
                      icon: Icons.visibility_outlined,
                      label: 'Preview',
                      onTap: onTap,
                    ),
                    _VerticalDivider(color: border),
                    _CardAction(
                      icon: Icons.ios_share_outlined,
                      label: 'Export',
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppConstants.routeExport,
                        arguments: {'resumeId': resume.id},
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat('MMM d, yyyy').format(dt);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ATS Score Ring
// Spec: section completeness scoring. Color: green ≥ 70, amber 40–69, red < 40.
// ─────────────────────────────────────────────────────────────────────────────

class _AtsScoreRing extends StatelessWidget {
  const _AtsScoreRing({required this.score, required this.isDark});

  final int score;
  final bool isDark;

  Color get _color {
    if (score >= 70) {
      return isDark ? AppColors.successDark : AppColors.successLight;
    }
    if (score >= 40) {
      return isDark ? AppColors.warningDark : AppColors.warningLight;
    }
    return isDark ? AppColors.errorDark : AppColors.errorLight;
  }

  String get _label {
    if (score >= 70) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Needs work';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ATS Score: $score out of 100, rated $_label',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 4,
                  backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(_color),
                ),
                Text(
                  '$score',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _label,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Actions Row — Interview Tips + tier badge
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.tier,
    required this.isOnline,
    required this.isDark,
    required this.onInterviewTips,
    required this.onAtsAnalyzer,
    required this.onUpgrade,
  });

  final TierEnum tier;
  final bool isOnline;
  final bool isDark;
  final VoidCallback onInterviewTips;
  final VoidCallback onAtsAnalyzer;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // Interview Tips — visible to all tiers
          Expanded(
            child: _QuickActionCard(
              icon: Icons.quiz_outlined,
              label: 'Interview Tips',
              isDark: isDark,
              onTap: onInterviewTips,
            ),
          ),
          const SizedBox(width: 8),

          // ATS Keyword Scanner — Basic+; free users are routed to paywall
          Expanded(
            child: _QuickActionCard(
              icon: Icons.document_scanner_outlined,
              label: 'ATS Scanner',
              isDark: isDark,
              locked: tier.isFree,
              onTap: onAtsAnalyzer,
            ),
          ),
          const SizedBox(width: 8),

          // Tier badge — tappable for free users to open the paywall
          Expanded(
            child: _QuickActionCard(
              icon: Icons.workspace_premium_outlined,
              label: tier.displayName,
              subtitle: tier.isFree ? 'Tap to upgrade' : 'Active',
              isDark: isDark,
              onTap: tier.isFree ? onUpgrade : null,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.isDark,
    this.onTap,
    this.subtitle,
    this.locked = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool isDark;
  final VoidCallback? onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final iconColor = locked ? secondary : accent;
    final labelColor =
        locked ? secondary : Theme.of(context).colorScheme.onSurface;

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: iconColor),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: GoogleFonts.inter(fontSize: 10, color: secondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );

    return Semantics(
      label: locked ? '$label — requires upgrade' : label,
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: locked
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  card,
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(Icons.lock_outline, size: 13, color: secondary),
                  ),
                ],
              )
            : card,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty States
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyMasterCard extends StatelessWidget {
  const _EmptyMasterCard({required this.isDark, required this.onCreate});
  final bool isDark;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return InkWell(
      onTap: onCreate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accent.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.add_circle_outline, size: 40, color: accent),
            const SizedBox(height: 12),
            Text(
              'Create your master resume',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your foundation for every tailored application.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTailoredState extends StatelessWidget {
  const _EmptyTailoredState({
    required this.tier,
    required this.isDark,
    required this.onUpgrade,
    required this.onCreate,
    required this.isOnline,
  });

  final TierEnum tier;
  final bool isDark;
  final VoidCallback onUpgrade;
  final VoidCallback onCreate;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.tune_outlined,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              tier.isFree
                  ? 'Tailor your resume to any job'
                  : 'No tailored resumes yet',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              tier.isFree
                  ? 'Upgrade to Basic to create resumes targeted to specific job postings.'
                  : 'Tap + New or the button below to create your first tailored resume.',
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            tier.isFree
                ? ElevatedButton(
                    onPressed: onUpgrade,
                    child: const Text('Upgrade to Basic'),
                  )
                : ElevatedButton(
                    onPressed: isOnline ? onCreate : null,
                    child: const Text('Create Tailored Resume'),
                  ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.subtitle, this.action});
  final String label;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: color);
  }
}
