import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../models/app_enums.dart';
import '../models/supporting_models.dart';
import '../providers/user_settings_provider.dart';
import '../services/external_link_service.dart';
import '../services/hive_service.dart';
import '../services/revenue_cat_service.dart';
import '../theme/app_colors.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// PaywallScreen
//
// Spec §4 / §7 (Paywall):
//   General tier-comparison screen — every Navigator.pushNamed call site in
//   this app routes here with no arguments, so this does NOT branch its
//   initial display by entry context. Free / Basic / Pro side by side, live
//   store-localized pricing pulled from RevenueCat (NEVER hardcoded), purchase
//   + restore, plus a secondary section for the $0.99 cover-letter combo
//   add-on (a one-time non-subscription purchase, tracked locally via
//   AddOnPurchase rather than an entitlement — see RevenueCatService docs).
//
// Rule §7: tier is sourced from RevenueCat at runtime. A successful purchase
//   here updates UserSettings.tier via the provider, which itself reads the
//   real entitlement state back from the purchase result — this screen never
//   assumes/sets tier directly.
// Rule §2: user data is never deleted — a successful add-on purchase creates
//   a new AddOnPurchase Hive record, additive only.
// ─────────────────────────────────────────────────────────────────────────────

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _loadingPackages = true;
  List<Package> _packages = [];
  String? _loadError;

  bool _purchaseInFlight = false;
  bool _restoreInFlight = false;
  String? _actionError;

  // Add-on: prefer a Package from the offering (so we can call purchasePackage);
  // fall back to a standalone StoreProduct for platforms where the add-on is
  // not included in the default offering.
  Package? _addonPackage;
  StoreProduct? _addOnProduct;
  bool _loadingAddOn = true;
  bool _addOnPurchaseInFlight = false;

  @override
  void initState() {
    super.initState();
    _loadPackages();
    _loadAddOn();
  }

  Future<void> _loadPackages() async {
    setState(() {
      _loadingPackages = true;
      _loadError = null;
    });
    try {
      final packages = await RevenueCatService.getAvailablePackages();
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _loadingPackages = false;
        if (packages.isEmpty) {
          _loadError =
              'Pricing is temporarily unavailable. Please try again shortly.';
        }
        // Extract the add-on package from the offering if it's present,
        // so _onPurchaseAddOn can call purchasePackage() instead of the
        // standalone StoreProduct path.
        _addonPackage = packages
            .where((p) =>
                p.storeProduct.identifier.toLowerCase().contains('addon'))
            .firstOrNull;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingPackages = false;
        _loadError =
            'Could not load pricing. Check your connection and try again.';
      });
    }
  }

  Future<void> _loadAddOn() async {
    setState(() => _loadingAddOn = true);
    final product = await RevenueCatService.getComboAddOnProduct();
    if (!mounted) return;
    setState(() {
      _addOnProduct = product;
      _loadingAddOn = false;
    });
  }

  // ── Subscription purchase ───────────────────────────────────────────────

  Future<void> _onPurchase(Package package) async {
    setState(() {
      _purchaseInFlight = true;
      _actionError = null;
    });

    try {
      final tier = await RevenueCatService.purchasePackage(package);
      // Reflect the authoritative tier from the purchase result immediately
      // rather than waiting for the background listener to fire.
      await ref.read(userSettingsProvider.notifier).updateTier(tier);

      if (!mounted) return;
      setState(() => _purchaseInFlight = false);

      if (tier != TierEnum.free) {
        Navigator.of(context).pop();
      }
    } on RevenueCatPurchaseCancelledException {
      // Silent — user backed out, not an error.
      if (mounted) setState(() => _purchaseInFlight = false);
    } on RevenueCatPurchaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _purchaseInFlight = false;
        _actionError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _purchaseInFlight = false;
        _actionError = 'Purchase failed. Please try again.';
      });
    }
  }

  // ── Restore ──────────────────────────────────────────────────────────────

  Future<void> _onRestore() async {
    setState(() {
      _restoreInFlight = true;
      _actionError = null;
    });

    try {
      final tier = await RevenueCatService.restorePurchases();
      await ref.read(userSettingsProvider.notifier).updateTier(tier);

      if (!mounted) return;
      setState(() => _restoreInFlight = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tier == TierEnum.free
              ? 'No previous purchases found for this account.'
              : 'Purchases restored — you\'re on ${tier.displayName}.'),
        ),
      );
    } on RevenueCatPurchaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _restoreInFlight = false;
        _actionError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _restoreInFlight = false;
        _actionError = 'Restore failed. Please try again.';
      });
    }
  }

  // ── Add-on purchase ──────────────────────────────────────────────────────

  Future<void> _onPurchaseAddOn() async {
    final addonPkg = _addonPackage;
    final product = _addOnProduct;
    if (addonPkg == null && product == null) return;

    if (AppConstants.kComboTestMode) {
      final purchase = AddOnPurchase(
        id: _uuid.v4(),
        purchasedAt: DateTime.now(),
        type: AddOnTypeEnum.coverLetterTailoredCombo,
        resumeId: null,
        used: false,
      );
      await HiveService.addOnPurchaseBox.put(purchase.id, purchase);
      if (!mounted) return;
      // Combo add-on grants immediate access — go straight to the tailored
      // resume flow rather than returning to the Dashboard and re-gating.
      Navigator.of(context)
          .pushReplacementNamed(AppConstants.routeCreateTailoredResume);
      return;
    }

    setState(() {
      _addOnPurchaseInFlight = true;
      _actionError = null;
    });

    try {
      if (addonPkg != null) {
        // Preferred: purchase as a Package from the offering.
        // The returned TierEnum reflects the subscription tier only — the
        // add-on grants an 'addon' entitlement, not a tier change, so we
        // discard the result and handle everything locally below.
        await RevenueCatService.purchasePackage(addonPkg);
      } else {
        await RevenueCatService.purchaseComboAddOn(product!);
      }

      // RevenueCatService never writes app data — creating the local
      // AddOnPurchase record on success is this screen's responsibility.
      final purchase = AddOnPurchase(
        id: _uuid.v4(),
        purchasedAt: DateTime.now(),
        type: AddOnTypeEnum.coverLetterTailoredCombo,
        resumeId: null,
        used: false,
      );
      await HiveService.addOnPurchaseBox.put(purchase.id, purchase);

      if (!mounted) return;
      setState(() => _addOnPurchaseInFlight = false);

      // Combo add-on grants immediate access — go straight to the tailored
      // resume flow rather than returning to the Dashboard and re-gating.
      Navigator.of(context)
          .pushReplacementNamed(AppConstants.routeCreateTailoredResume);
    } on RevenueCatPurchaseCancelledException {
      if (mounted) setState(() => _addOnPurchaseInFlight = false);
    } on RevenueCatPurchaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _addOnPurchaseInFlight = false;
        _actionError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addOnPurchaseInFlight = false;
        _actionError = 'Purchase failed. Please try again.';
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(userSettingsProvider);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Upgrade',
            style: GoogleFonts.playfairDisplay(
                fontSize: 20, fontWeight: FontWeight.w600)),
      ),
      body: _loadingPackages
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                if (_loadError != null) ...[
                  _ErrorBanner(message: _loadError!, isDark: isDark),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _loadPackages,
                      child: const Text('Try Again'),
                    ),
                  ),
                ] else ...[
                  _TierComparisonTable(
                      currentTier: settings.tier, isDark: isDark),
                  const SizedBox(height: 20),
                  ..._buildPackageCards(settings.tier),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => ExternalLinkService.open(
                          AppConstants.privacyPolicyUrl),
                      child: Text(
                        'Privacy Policy',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_actionError != null) ...[
                    _ErrorBanner(message: _actionError!, isDark: isDark),
                    const SizedBox(height: 12),
                  ],
                  Center(
                    child: TextButton.icon(
                      onPressed: _restoreInFlight ? null : _onRestore,
                      icon: _restoreInFlight
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.restore, size: 16),
                      label: Text(_restoreInFlight
                          ? 'Restoring…'
                          : 'Restore Purchases'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 16),
                _AddOnSection(
                  product: _addonPackage?.storeProduct ?? _addOnProduct,
                  isLoading: _loadingAddOn && _addonPackage == null,
                  isPurchasing: _addOnPurchaseInFlight,
                  isDark: isDark,
                  onPurchase: _onPurchaseAddOn,
                ),
              ],
            ),
    );
  }

  List<Widget> _buildPackageCards(TierEnum currentTier) {
    // Group packages by tier (basic/pro) so monthly + annual render as a
    // pair under one heading rather than four flat unrelated cards.
    final basicPackages = _packages
        .where((p) => p.storeProduct.identifier.contains('basic'))
        .toList();
    final proPackages = _packages
        .where((p) => p.storeProduct.identifier.contains('pro'))
        .toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return [
      if (proPackages.isNotEmpty)
        _TierPackageGroup(
          tierLabel: 'Pro',
          tierDescription: 'Full AI suite, all templates, all export formats.',
          packages: proPackages,
          isCurrentTier: currentTier.isPro,
          isDark: isDark,
          isPurchasing: _purchaseInFlight,
          onSelect: _onPurchase,
          highlight: true,
        ),
      const SizedBox(height: 14),
      if (basicPackages.isNotEmpty)
        _TierPackageGroup(
          tierLabel: 'Basic',
          tierDescription: 'AI resume building, DOCX export, more templates.',
          packages: basicPackages,
          isCurrentTier: currentTier.isBasic,
          isDark: isDark,
          isPurchasing: _purchaseInFlight,
          onSelect: _onPurchase,
          highlight: false,
        ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tier Comparison Table
// ─────────────────────────────────────────────────────────────────────────────

class _TierComparisonTable extends StatelessWidget {
  const _TierComparisonTable({required this.currentTier, required this.isDark});
  final TierEnum currentTier;
  final bool isDark;

  static const _rows = [
    ('Resume uploads', '4 docs', '10 docs', 'Unlimited'),
    ('Resume templates', 'All 12', 'All 12', 'All 12'),
    ('AI bullet suggestions', '—', '—', '✓'),
    ('PDF export', '✓', '✓', '✓'),
    ('DOCX export', '—', '✓', '✓'),
    ('Plain text export', '—', '—', '✓'),
    ('Interview Prep', 'Static guide', 'Role-specific', 'Personalized + export'),
  ];

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(flex: 3, child: SizedBox()),
              Expanded(
                  flex: 2,
                  child: Text('Free',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: secondary))),
              Expanded(
                  flex: 2,
                  child: Text('Basic',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: secondary))),
              Expanded(
                  flex: 2,
                  child: Text('Pro',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: secondary))),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(row.$1,
                        style:
                            GoogleFonts.inter(fontSize: 12, color: onSurface)),
                  ),
                  Expanded(
                      flex: 2,
                      child: Text(row.$2,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              fontSize: 11.5, color: secondary))),
                  Expanded(
                      flex: 2,
                      child: Text(row.$3,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              fontSize: 11.5, color: secondary))),
                  Expanded(
                      flex: 2,
                      child: Text(row.$4,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              fontSize: 11.5, color: secondary))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tier Package Group — monthly + annual packages for one tier
// ─────────────────────────────────────────────────────────────────────────────

class _TierPackageGroup extends StatelessWidget {
  const _TierPackageGroup({
    required this.tierLabel,
    required this.tierDescription,
    required this.packages,
    required this.isCurrentTier,
    required this.isDark,
    required this.isPurchasing,
    required this.onSelect,
    required this.highlight,
  });

  final String tierLabel;
  final String tierDescription;
  final List<Package> packages;
  final bool isCurrentTier;
  final bool isDark;
  final bool isPurchasing;
  final ValueChanged<Package> onSelect;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    // Determine monthly/annual by packageType first; fall back to the
    // store product identifier for offerings that use custom package IDs
    // (where packageType == PackageType.custom regardless of billing period).
    Package? monthly;
    Package? annual;
    for (final p in packages) {
      final id = p.storeProduct.identifier.toLowerCase();
      final looksAnnual = p.packageType == PackageType.annual ||
          id.contains('annual') ||
          id.contains('yearly');
      final looksMonthly = p.packageType == PackageType.monthly ||
          id.contains('monthly');
      if (looksAnnual) {
        annual = p;
      } else if (looksMonthly) {
        monthly = p;
      } else {
        // Can't determine billing period — slot into whichever is still empty.
        monthly ??= p;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? accent : border,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(tierLabel,
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface)),
              if (highlight) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('BEST VALUE',
                      style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
              const Spacer(),
              if (isCurrentTier)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Current Plan',
                      style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: accent)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(tierDescription,
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          if (monthly != null)
            _PriceOptionButton(
              package: monthly,
              periodLabel: '/ month',
              isDisabled: isPurchasing || isCurrentTier,
              isDark: isDark,
              onTap: () => onSelect(monthly!),
            ),
          if (monthly != null && annual != null) const SizedBox(height: 8),
          if (annual != null)
            _PriceOptionButton(
              package: annual,
              periodLabel: '/ year',
              isDisabled: isPurchasing || isCurrentTier,
              isDark: isDark,
              onTap: () => onSelect(annual!),
              badge: 'Save vs. monthly',
            ),
        ],
      ),
    );
  }
}

class _PriceOptionButton extends StatelessWidget {
  const _PriceOptionButton({
    required this.package,
    required this.periodLabel,
    required this.isDisabled,
    required this.isDark,
    required this.onTap,
    this.badge,
  });

  final Package package;
  final String periodLabel;
  final bool isDisabled;
  final bool isDark;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final product = package.storeProduct;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isDisabled ? null : onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          side:
              BorderSide(color: accent.withValues(alpha: isDisabled ? 0.3 : 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(product.priceString,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDisabled
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : accent)),
                const SizedBox(width: 4),
                Text(periodLabel,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
            if (badge != null)
              Text(badge!,
                  style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.successLight)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add-on Section
// ─────────────────────────────────────────────────────────────────────────────

class _AddOnSection extends StatelessWidget {
  const _AddOnSection({
    required this.product,
    required this.isLoading,
    required this.isPurchasing,
    required this.isDark,
    required this.onPurchase,
  });

  final StoreProduct? product;
  final bool isLoading;
  final bool isPurchasing;
  final bool isDark;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const SizedBox.shrink();
    if (product == null) return const SizedBox.shrink();

    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_fix_high_outlined, size: 20, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cover Letter + Tailored Resume',
                  style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'One-time · Any tier · ${product!.priceString}',
            style: GoogleFonts.inter(fontSize: 11.5, color: accent),
          ),
          const SizedBox(height: 8),
          Text(
            'Get one AI cover letter + one tailored resume, saved permanently to your device.',
            style: GoogleFonts.inter(
                fontSize: 12, height: 1.45, color: secondary),
          ),
          const SizedBox(height: 14),
          if (AppConstants.kComboTestMode) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF59D),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFFF9A825)),
                ),
                child: Text('TEST MODE',
                    style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF795548))),
              ),
            ),
            const SizedBox(height: 6),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isPurchasing ? null : onPurchase,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: accent),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              child: isPurchasing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      AppConstants.kComboTestMode
                          ? 'Get for Free (Test Mode)'
                          : 'Get for ${product!.priceString}',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: accent),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error Banner
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.isDark});
  final String message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final errorColor = isDark ? AppColors.errorDark : AppColors.errorLight;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: errorColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: errorColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: GoogleFonts.inter(fontSize: 12.5, color: errorColor)),
          ),
        ],
      ),
    );
  }
}
