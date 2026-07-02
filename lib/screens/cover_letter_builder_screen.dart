import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../utils/web_download.dart';
import '../models/resume_sections.dart';
import '../models/supporting_models.dart';
import '../providers/connectivity_provider.dart';
import '../services/hive_service.dart';
import '../services/pdf_export_service.dart';
import '../services/cloudflare_worker_service.dart';
import '../services/phase2_api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/resume_template_renderer.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../models/app_enums.dart';
import '../providers/user_settings_provider.dart';
import '../services/revenue_cat_service.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// CoverLetterBuilderScreen
//
// Spec §4 (Cover Letter Builder):
//   - AI drafts a full cover letter from the active resume + uploaded job posting.
//   - Editable inline.
//   - Saved to local device.
//   - Exportable and printable.
//   - Requires internet to generate.
//   - Access: Pro tier (unlimited) or any tier via $0.99 add-on.
// ─────────────────────────────────────────────────────────────────────────────

class CoverLetterBuilderScreen extends ConsumerStatefulWidget {
  const CoverLetterBuilderScreen({super.key});

  @override
  ConsumerState<CoverLetterBuilderScreen> createState() =>
      _CoverLetterBuilderScreenState();
}

class _CoverLetterBuilderScreenState
    extends ConsumerState<CoverLetterBuilderScreen> {
  bool _initialized = false;
  String? _resumeId;
  String? _effectiveResumeId;
  String? _existingCoverLetterId;

  // State machine
  _CLState _state = _CLState.input;

  // Input controllers
  final _jdController = TextEditingController();
  final _companyController = TextEditingController();
  final _hiringManagerController = TextEditingController();
  final _contentController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _hasUnsavedChanges = false;

  // Paywall / add-on state (used when _state == locked)
  StoreProduct? _addOnProduct;
  bool _loadingAddOn = false;
  bool _purchaseInFlight = false;
  String? _paywallError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _resumeId = args['resumeId'] as String?;
      _existingCoverLetterId = args['coverLetterId'] as String?;
      final jobText = args['jobPostingText'] as String?;
      if (jobText != null) _jdController.text = jobText;
      final company = args['companyName'] as String?;
      if (company != null) _companyController.text = company;
    }

    // Resolve once — used for access checks, generate, save, and PDF export.
    _effectiveResumeId = _resumeId ??
        HiveService.resumeBox.values
            .where((r) => r.isMaster && !r.isArchived)
            .firstOrNull
            ?.id;

    // Load existing cover letter if editing
    if (_existingCoverLetterId != null) {
      final existing = HiveService.coverLetterBox.get(_existingCoverLetterId);
      if (existing != null) {
        _contentController.text = existing.content;
        _jdController.text = existing.jobDescription;
        _state = _CLState.editing;
      }
    }

    _contentController.addListener(() {
      if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
    });

    // Access gate: Pro is unlimited; Free/Basic require either an unused add-on
    // or one already spent on this same resume (the latter allows editing a
    // previously saved cover letter without being re-gated).
    final tier = ref.read(currentTierProvider);
    if (AppConstants.kComboTestMode) {
      if (!_hasUsableAddOn()) {
        final purchase = AddOnPurchase(
          id: _uuid.v4(),
          purchasedAt: DateTime.now(),
          type: AddOnTypeEnum.coverLetterTailoredCombo,
          resumeId: null,
          used: false,
        );
        HiveService.addOnPurchaseBox.put(purchase.id, purchase);
      }
    } else if (!tier.isPro && !_hasUsableAddOn()) {
      _state = _CLState.locked;
      _loadingAddOn = true;
      _loadAddOnProduct();
    }
  }

  @override
  void dispose() {
    _jdController.dispose();
    _companyController.dispose();
    _hiringManagerController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ── Access helpers ────────────────────────────────────────────────────────

  // Returns true if an add-on purchase is usable for this resume:
  // either an unused purchase (can be spent) or one already consumed on
  // this exact resume (allows re-editing without buying again).
  bool _hasUsableAddOn() {
    final rid = _effectiveResumeId;
    if (rid == null) return false;
    return HiveService.addOnPurchaseBox.values.any((p) =>
        p.type == AddOnTypeEnum.coverLetterTailoredCombo &&
        (!p.used || p.resumeId == rid));
  }

  Future<void> _loadAddOnProduct() async {
    final product = await RevenueCatService.getComboAddOnProduct();
    if (!mounted) return;
    setState(() {
      _addOnProduct = product;
      _loadingAddOn = false;
    });
  }

  Future<void> _onPurchaseAddOn() async {
    final product = _addOnProduct;
    if (product == null) return;

    setState(() {
      _purchaseInFlight = true;
      _paywallError = null;
    });

    try {
      await RevenueCatService.purchaseComboAddOn(product);

      final purchase = AddOnPurchase(
        id: _uuid.v4(),
        purchasedAt: DateTime.now(),
        type: AddOnTypeEnum.coverLetterTailoredCombo,
        resumeId: null,
        used: false,
      );
      await HiveService.addOnPurchaseBox.put(purchase.id, purchase);

      if (!mounted) return;
      setState(() {
        _purchaseInFlight = false;
        _state = _CLState.input;
      });
    } on RevenueCatPurchaseCancelledException {
      if (mounted) setState(() => _purchaseInFlight = false);
    } on RevenueCatPurchaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _purchaseInFlight = false;
        _paywallError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _purchaseInFlight = false;
        _paywallError = 'Purchase failed. Please try again.';
      });
    }
  }

  // ── Generate ──────────────────────────────────────────────────────────────

  Future<void> _onGenerate() async {
    // Belt-and-suspenders: also checked at screen entry, but re-check here in
    // case a Pro subscription expired mid-session.
    final tier = ref.read(currentTierProvider);
    if (!AppConstants.kComboTestMode && !tier.isPro && !_hasUsableAddOn()) {
      setState(() {
        _state = _CLState.locked;
        _loadingAddOn = true;
      });
      _loadAddOnProduct();
      return;
    }

    final jd = _jdController.text.trim();
    if (jd.isEmpty) {
      setState(() => _errorMessage =
          'Please provide the job description to generate a cover letter.');
      return;
    }

    final isOnline = ref.read(isOnlineProvider);
    if (!isOnline) {
      setState(() => _errorMessage = AppConstants.offlineBannerMessage);
      return;
    }

    final effectiveResumeId = _effectiveResumeId;

    if (effectiveResumeId == null) {
      setState(() => _errorMessage =
          'No resume found. Complete your master resume first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _state = _CLState.generating;
    });

    try {
      final resumeData = ResumeRenderData.fromHive(effectiveResumeId);
      final content = await Phase2ApiService.generateCoverLetter(
        resumeData: resumeData,
        jobDescription: jd,
        companyName: _companyController.text.trim(),
        hiringManagerName: _hiringManagerController.text.trim(),
      );
      _contentController.text = content;
      setState(() {
        _state = _CLState.editing;
        _isLoading = false;
        _hasUnsavedChanges = true;
      });
    } on CloudflareApiException catch (e) {
      setState(() {
        _isLoading = false;
        _state = _CLState.input;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _state = _CLState.input;
        _errorMessage = 'Generation failed. Please try again.';
      });
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _onSave() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final effectiveResumeId = _effectiveResumeId ?? '';

      if (_existingCoverLetterId != null) {
        // Update existing — add-on was already consumed on the first save
        final existing = HiveService.coverLetterBox.get(_existingCoverLetterId);
        if (existing != null) {
          existing.content = content;
          existing.touch();
        }
      } else {
        // Create new
        final clId = _uuid.v4();
        final cl = CoverLetter(
          id: clId,
          resumeId: effectiveResumeId,
          jobDescription: _jdController.text,
          content: content,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await HiveService.coverLetterBox.put(clId, cl);
        _existingCoverLetterId = clId;

        // Consume the add-on on first save (Pro tier never consumes add-ons)
        final tier = ref.read(currentTierProvider);
        if (!tier.isPro) {
          final addOn = HiveService.addOnPurchaseBox.values
              .where((p) =>
                  p.type == AddOnTypeEnum.coverLetterTailoredCombo &&
                  (!p.used || p.resumeId == effectiveResumeId))
              .firstOrNull;
          if (addOn != null && !addOn.used) {
            addOn.used = true;
            addOn.resumeId = effectiveResumeId;
            await addOn.save();
          }
        }
      }

      setState(() {
        _isLoading = false;
        _hasUnsavedChanges = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cover letter saved.')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Save failed. Please try again.';
      });
    }
  }

  // ── Export / Print ────────────────────────────────────────────────────────

  Future<void> _onExport() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final bytes = await _generateCoverLetterPdf(content);
      final companyName = _companyController.text.trim();
      final fileName = companyName.isNotEmpty
          ? 'Cover_Letter_${companyName.replaceAll(' ', '_')}.pdf'
          : 'Cover_Letter.pdf';
      if (kIsWeb) {
        downloadPdfInBrowser(bytes, fileName);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onPrint() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final bytes = await _generateCoverLetterPdf(content);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Cover Letter',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Uint8List> _generateCoverLetterPdf(String content) async {
    ContactInfo senderContact = ContactInfo();
    final effectiveResumeId = _effectiveResumeId;
    if (effectiveResumeId != null) {
      senderContact = ResumeRenderData.fromHive(effectiveResumeId).contact;
    }

    return PdfExportService.generateCoverLetterPdf(
      content: content,
      senderContact: senderContact,
      companyName: _companyController.text.trim().isNotEmpty
          ? _companyController.text.trim()
          : null,
      hiringManager: _hiringManagerController.text.trim().isNotEmpty
          ? _hiringManagerController.text.trim()
          : null,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showUnsavedChangesDialog() ?? false;
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        appBar: AppBar(
          title: Text('Cover Letter',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 20, fontWeight: FontWeight.w600)),
          actions: [
            IconButton(
              icon: const Icon(Icons.home_outlined),
              tooltip: 'Home',
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context,
                AppConstants.routeDashboard,
                (route) => false,
              ),
            ),
            if (AppConstants.kComboTestMode)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Chip(
                  label: Text('TEST MODE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87)),
                  backgroundColor: Color(0xFFFFF59D),
                  side: BorderSide(color: Color(0xFFF9A825)),
                  padding: EdgeInsets.zero,
                  labelPadding: EdgeInsets.symmetric(horizontal: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (_state == _CLState.editing) ...[
              if (_hasUnsavedChanges)
                TextButton(
                  onPressed: _isLoading ? null : _onSave,
                  child: const Text('Save'),
                ),
              IconButton(
                icon: const Icon(Icons.print_outlined),
                tooltip: 'Print',
                onPressed: _isLoading ? null : _onPrint,
              ),
              IconButton(
                icon: const Icon(Icons.ios_share_outlined),
                tooltip: 'Export',
                onPressed: _isLoading ? null : _onExport,
              ),
            ],
          ],
        ),
        body: switch (_state) {
          _CLState.locked => _LockedView(
              isDark: isDark,
              addOnProduct: _addOnProduct,
              isLoading: _loadingAddOn,
              isPurchasing: _purchaseInFlight,
              errorMessage: _paywallError,
              onPurchase: _onPurchaseAddOn,
              onUpgradePro: () =>
                  Navigator.pushNamed(context, AppConstants.routePaywall),
            ),
          _CLState.input => _InputView(
              jdController: _jdController,
              companyController: _companyController,
              hiringManagerController: _hiringManagerController,
              isLoading: _isLoading,
              errorMessage: _errorMessage,
              isDark: isDark,
              onGenerate: _onGenerate,
            ),
          _CLState.generating => _GeneratingView(isDark: isDark),
          _CLState.editing => _EditingView(
              contentController: _contentController,
              isLoading: _isLoading,
              isDark: isDark,
              onRegenerate: () => setState(() {
                _state = _CLState.input;
                _contentController.clear();
              }),
              onSave: _onSave,
              onExport: _onExport,
            ),
        },
      ),
    );
  }

  Future<bool?> _showUnsavedChangesDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unsaved changes',
            style: GoogleFonts.playfairDisplay(
                fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text(
          'You have unsaved changes to your cover letter. Save before leaving?',
          style: GoogleFonts.inter(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard')),
          ElevatedButton(
            onPressed: () async {
              await _onSave();
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save & Exit'),
          ),
        ],
      ),
    );
  }
}

enum _CLState { locked, input, generating, editing }

// ─────────────────────────────────────────────────────────────────────────────
// Locked / Paywall View
// ─────────────────────────────────────────────────────────────────────────────

class _LockedView extends StatelessWidget {
  const _LockedView({
    required this.isDark,
    required this.addOnProduct,
    required this.isLoading,
    required this.isPurchasing,
    required this.errorMessage,
    required this.onPurchase,
    required this.onUpgradePro,
  });

  final bool isDark;
  final StoreProduct? addOnProduct;
  final bool isLoading;
  final bool isPurchasing;
  final String? errorMessage;
  final VoidCallback onPurchase;
  final VoidCallback onUpgradePro;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_fix_high_outlined, size: 56, color: accent),
            const SizedBox(height: 20),
            Text(
              'Unlock Your Cover Letter',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'AI drafts a tailored cover letter that matches your resume to this specific job — editable and exportable.',
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.55,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('One-time add-on',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  letterSpacing: 0.3,
                                )),
                            const SizedBox(height: 4),
                            Text('Tailored cover letter for this resume',
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                )),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (isLoading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (addOnProduct != null)
                        Text(
                          addOnProduct!.priceString,
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          (isPurchasing || isLoading || addOnProduct == null)
                              ? null
                              : onPurchase,
                      child: isPurchasing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(addOnProduct == null
                              ? 'Loading…'
                              : 'Buy for ${addOnProduct!.priceString}'),
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(errorMessage!,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.errorDark
                                : AppColors.errorLight)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onUpgradePro,
              child: Text(
                'Upgrade to Pro for unlimited cover letters →',
                style: GoogleFonts.inter(fontSize: 13, color: accent),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input View
// ─────────────────────────────────────────────────────────────────────────────

class _InputView extends StatelessWidget {
  const _InputView({
    required this.jdController,
    required this.companyController,
    required this.hiringManagerController,
    required this.isLoading,
    required this.errorMessage,
    required this.isDark,
    required this.onGenerate,
  });

  final TextEditingController jdController;
  final TextEditingController companyController;
  final TextEditingController hiringManagerController;
  final bool isLoading;
  final String? errorMessage;
  final bool isDark;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Generate your cover letter',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI will write a tailored cover letter using your resume and the job details below.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.55,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _InputField(
                label: 'Company Name',
                hint: 'e.g. Acme Corp',
                controller: companyController,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _InputField(
                label: 'Hiring Manager Name (optional)',
                hint: 'e.g. Sarah Johnson',
                controller: hiringManagerController,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _InputField(
                label: 'Job Description *',
                hint: 'Paste the full job description here…',
                controller: jdController,
                maxLines: 10,
                isDark: isDark,
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(errorMessage!,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.errorDark
                            : AppColors.errorLight)),
              ],
            ],
          ),
        ),
        _ActionBar(
          isDark: isDark,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onGenerate,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Generate Cover Letter'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generating View
// ─────────────────────────────────────────────────────────────────────────────

class _GeneratingView extends StatelessWidget {
  const _GeneratingView({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Generating cover letter, please wait',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 28),
              Text(
                'Writing your cover letter…',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'AI is crafting a letter that connects your experience directly to this role.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Editing View
// ─────────────────────────────────────────────────────────────────────────────

class _EditingView extends StatelessWidget {
  const _EditingView({
    required this.contentController,
    required this.isLoading,
    required this.isDark,
    required this.onRegenerate,
    required this.onSave,
    required this.onExport,
  });

  final TextEditingController contentController;
  final bool isLoading;
  final bool isDark;
  final VoidCallback onRegenerate;
  final VoidCallback onSave;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // AI disclosure banner
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          color: (isDark ? AppColors.aiIndicatorDark : AppColors.aiIndicator)
              .withValues(alpha: 0.08),
          child: Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 14,
                  color: isDark
                      ? AppColors.aiIndicatorDark
                      : AppColors.aiIndicator),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI-generated — edit freely before saving.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.aiIndicatorDark
                        : AppColors.aiIndicator,
                  ),
                ),
              ),
              TextButton(
                onPressed: onRegenerate,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text('Regenerate',
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.aiIndicatorDark
                            : AppColors.aiIndicator)),
              ),
            ],
          ),
        ),

        // Editable content
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight),
            ),
            child: TextField(
              controller: contentController,
              maxLines: null,
              expands: true,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.7,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  const _InputField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.isDark,
    this.maxLines = 1,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool isDark;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            )),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.isDark, required this.child});
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
            top: BorderSide(
                color: isDark ? AppColors.borderDark : AppColors.borderLight)),
      ),
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}
