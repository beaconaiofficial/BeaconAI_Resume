import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../constants/app_constants.dart';
import '../models/app_enums.dart';
import '../models/resume.dart';
import '../models/resume_sections.dart';
import '../models/supporting_models.dart';
import '../providers/connectivity_provider.dart';
import '../providers/user_settings_provider.dart';
import '../services/hive_service.dart';
import '../services/cloudflare_worker_service.dart';
import '../services/phase2_api_service.dart';
import '../services/revenue_cat_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_logger.dart';
import '../widgets/resume_template_renderer.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// CreateTailoredResumeScreen
//
// Spec §4 (Create Tailored Resume):
//   - Gated to Basic+. Requires internet.
//   - Step 1: upload or paste job posting.
//   - Step 2: Claude extracts role title, skills, keywords. User confirms.
//   - Step 3: Claude generates tailored draft from master. User reviews.
//   - Saved to local device on confirm.
//   - Rule §3: User always reviews before saving.
//   - Counts against Basic tier's 2/month slot limit.
// ─────────────────────────────────────────────────────────────────────────────

class CreateTailoredResumeScreen extends ConsumerStatefulWidget {
  const CreateTailoredResumeScreen({super.key});

  @override
  ConsumerState<CreateTailoredResumeScreen> createState() =>
      _CreateTailoredResumeScreenState();
}

class _CreateTailoredResumeScreenState
    extends ConsumerState<CreateTailoredResumeScreen> {
  _TailoredStep _step = _TailoredStep.jobPosting;
  final _pasteController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  JobPostingData? _jobPostingData;
  String? _tailoredResumeJson;
  ResumeRenderData? _masterData;
  String? _masterResumeId;
  String _generatingMessage = 'Analyzing job requirements...';

  // Call 1's (relevance scoring) result, cached so a retry after a Call
  // 2-specific failure re-invokes only Call 2 rather than re-scoring
  // relevance (and re-billing Haiku) from scratch. Invalidated whenever
  // _jobPostingData changes, since a cached score set is only valid for the
  // job posting it was scored against.
  List<ExperienceEntry>? _cachedTop3Entries;

  // Cover letter upsell state
  bool _addCoverLetter = false;
  StoreProduct? _addOnProduct;
  bool _loadingAddOn = true;
  bool _addOnPurchaseInFlight = false;
  String? _addOnError;

  @override
  void initState() {
    super.initState();
    _loadMaster();
    _loadAddOnProduct();
  }

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  void _loadMaster() {
    final resumes = HiveService.resumeBox.values;
    final master =
        resumes.where((r) => r.isMaster && !r.isArchived).firstOrNull;
    if (master != null) {
      _masterResumeId = master.id;
      _masterData = ResumeRenderData.fromHive(master.id);
    }
    setState(() {});
  }

  bool _hasUnusedAddOn() => HiveService.addOnPurchaseBox.values
      .any((p) => p.type == AddOnTypeEnum.coverLetterTailoredCombo && !p.used);

  Future<void> _loadAddOnProduct() async {
    final product = await RevenueCatService.getComboAddOnProduct();
    if (!mounted) return;
    setState(() {
      _addOnProduct = product;
      _loadingAddOn = false;
    });
  }

  Future<void> _onCoverLetterToggle() async {
    if (_addCoverLetter) {
      setState(() => _addCoverLetter = false);
      return;
    }
    final settings = ref.read(userSettingsProvider);
    if (settings.tier.isPro || _hasUnusedAddOn()) {
      setState(() => _addCoverLetter = true);
      return;
    }
    // Not entitled — bypass in test mode or trigger purchase
    if (AppConstants.kComboTestMode) {
      if (!_hasUnusedAddOn()) {
        final purchase = AddOnPurchase(
          id: _uuid.v4(),
          purchasedAt: DateTime.now(),
          type: AddOnTypeEnum.coverLetterTailoredCombo,
          resumeId: null,
          used: false,
        );
        await HiveService.addOnPurchaseBox.put(purchase.id, purchase);
      }
      if (!mounted) return;
      setState(() => _addCoverLetter = true);
      return;
    }
    final product = _addOnProduct;
    if (product == null) return;
    setState(() {
      _addOnPurchaseInFlight = true;
      _addOnError = null;
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
        _addOnPurchaseInFlight = false;
        _addCoverLetter = true;
      });
    } on RevenueCatPurchaseCancelledException {
      if (mounted) setState(() => _addOnPurchaseInFlight = false);
    } on RevenueCatPurchaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _addOnPurchaseInFlight = false;
        _addOnError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addOnPurchaseInFlight = false;
        _addOnError = 'Purchase failed. Please try again.';
      });
    }
  }

  // ── Step 1: Job posting input ──────────────────────────────────────────────

  Future<void> _onUploadJobPosting() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    final text = String.fromCharCodes(bytes.take(20000));
    _pasteController.text = text;
  }

  Future<void> _onExtractJobPosting() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Please paste or upload a job posting.');
      return;
    }

    if (_masterData == null) {
      setState(() => _errorMessage =
          'No master resume found. Complete your master resume first.');
      return;
    }

    final isOnline = ref.read(isOnlineProvider);
    if (!isOnline) {
      setState(() =>
          _errorMessage = 'Internet connection required for AI processing.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await Phase2ApiService.extractJobPosting(text);
      setState(() {
        _jobPostingData = data;
        // A cached Call 1 result only applies to the job posting it was
        // scored against — a new/re-extracted posting invalidates it.
        _cachedTop3Entries = null;
        _step = _TailoredStep.confirmation;
        _isLoading = false;
      });
    } on CloudflareApiException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Extraction failed. Please try again.';
      });
    }
  }

  // ── Step 2: Generate tailored draft ───────────────────────────────────────

  Future<void> _onGenerateDraft() async {
    if (_jobPostingData == null || _masterData == null) return;

    setState(() {
      _isLoading = true;
      _step = _TailoredStep.generating;
      _errorMessage = null;
      _generatingMessage = 'Analyzing job requirements...';
    });

    try {
      final json = await Phase2ApiService.generateTailoredResume(
        masterData: _masterData!,
        jobPosting: _jobPostingData!,
        cachedTop3: _cachedTop3Entries,
        onEntriesSelected: (entries) => _cachedTop3Entries = entries,
        onProgress: (msg) {
          if (mounted) setState(() => _generatingMessage = msg);
        },
      );
      setState(() {
        _tailoredResumeJson = json;
        _step = _TailoredStep.review;
        _isLoading = false;
      });
    } on CloudflareApiException catch (e) {
      setState(() {
        _isLoading = false;
        _step = _TailoredStep.confirmation;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _step = _TailoredStep.confirmation;
        _errorMessage = 'Generation failed. Please try again.';
      });
    }
  }

  // ── Step 3: Save tailored resume ──────────────────────────────────────────

  Future<void> _onSave() async {
    if (_tailoredResumeJson == null || _jobPostingData == null) return;

    setState(() => _isLoading = true);

    // Tracked so the catch block can clean up whatever was already written
    // before a failure, rather than leaving an orphaned Resume/SourceDocument
    // record with no (or partial) sections for the user to stumble into
    // later from Home/My Documents.
    String? createdResumeId;
    String? createdDocId;

    try {
      final resumeId = _uuid.v4();
      createdResumeId = resumeId;
      final now = DateTime.now();

      // Create Resume object
      final tailored = Resume(
        id: resumeId,
        title: _jobPostingData!.roleTitle.isNotEmpty
            ? _jobPostingData!.roleTitle
            : 'Tailored Resume',
        createdAt: now,
        updatedAt: now,
        isMaster: false,
        templateId: HiveService.resumeBox.get(_masterResumeId)?.templateId ??
            AppConstants.defaultTemplateId,
        linkedJobDescription: _pasteController.text,
        companyName: _jobPostingData!.companyName.isNotEmpty
            ? _jobPostingData!.companyName
            : null,
        roleTitle: _jobPostingData!.roleTitle.isNotEmpty
            ? _jobPostingData!.roleTitle
            : null,
      );
      await HiveService.resumeBox.put(resumeId, tailored);

      // Save job posting as a SourceDocument
      final docId = _uuid.v4();
      createdDocId = docId;
      final doc = SourceDocument(
        id: docId,
        resumeId: resumeId,
        fileName: 'Job Posting — ${_jobPostingData!.roleTitle}',
        fileType: FileTypeEnum.txt,
        documentRole: DocumentRoleEnum.jobPosting,
        uploadedAt: now,
        extractionStatus: ExtractionStatusEnum.complete,
        rawExtractedText: _pasteController.text,
      );
      await HiveService.sourceDocumentBox.put(docId, doc);

      // Write tailored sections to Hive. Throws on malformed JSON — see
      // _writeTailoredSections' doc comment for why there is deliberately
      // no silent fallback here anymore.
      await _writeTailoredSections(resumeId, _tailoredResumeJson!);

      // Increment usage counter for Basic tier
      await ref
          .read(userSettingsProvider.notifier)
          .incrementTailoredResumeCount();

      if (mounted) {
        if (_addCoverLetter) {
          Navigator.pushReplacementNamed(
            context,
            AppConstants.routeCoverLetterBuilder,
            arguments: {
              'resumeId': resumeId,
              'jobPostingText': _pasteController.text,
              if (_jobPostingData!.companyName.isNotEmpty)
                'companyName': _jobPostingData!.companyName,
            },
          );
        } else {
          Navigator.pushReplacementNamed(
            context,
            AppConstants.routePreviewEdit,
            arguments: {'resumeId': resumeId},
          );
        }
      }
    } catch (e) {
      devLog('[TAILORED_SAVE] Failed to save tailored resume: $e');
      if (createdResumeId != null) {
        await HiveService.resumeBox.delete(createdResumeId);
        for (final type in SectionTypeEnum.values) {
          await HiveService.resumeSectionBox
              .delete('${createdResumeId}_${type.name}');
        }
        devLog(
            '[TAILORED_SAVE] Cleaned up orphaned resume $createdResumeId');
      }
      if (createdDocId != null) {
        await HiveService.sourceDocumentBox.delete(createdDocId);
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to save. Please try again.';
      });
    }
  }

  /// Writes each tailored section to Hive. Throws on malformed JSON rather
  /// than silently falling back to copying the master resume's sections —
  /// that fallback used to exist here and is exactly what caused the P0
  /// "tailored resume identical to master" bug: a Call 2 response that
  /// failed to parse would silently reach this function still unparseable,
  /// and the old catch-all quietly copied master's content onto the new
  /// tailored resume's id with no visible error. _onSave's catch block now
  /// cleans up the partially-created Resume/SourceDocument records and
  /// shows a real error instead.
  Future<void> _writeTailoredSections(
      String resumeId, String tailoredJson) async {
    final data = jsonDecode(tailoredJson) as Map<String, dynamic>;

    Future<void> put(SectionTypeEnum type, String jsonData) async {
      final key = '${resumeId}_${type.name}';
      await HiveService.resumeSectionBox.put(
        key,
        ResumeSection(
          id: _uuid.v4(),
          resumeId: resumeId,
          type: type,
          data: jsonData,
          hasUnreviewedAIContent: true,
        ),
      );
    }

    if (data['contact'] != null) {
      await put(SectionTypeEnum.contact, jsonEncode(data['contact']));
    }
    if (data['summary'] != null) {
      await put(
          SectionTypeEnum.summary, jsonEncode({'text': data['summary']}));
    }
    if (data['experience'] != null) {
      final exp = (data['experience'] as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        if (m['id'] == null || m['id'] == 'uuid-placeholder') {
          m['id'] = _uuid.v4();
        }
        return m;
      }).toList();
      await put(SectionTypeEnum.experience, jsonEncode(exp));
    }
    if (data['education'] != null) {
      final edu = (data['education'] as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        if (m['id'] == null || m['id'] == 'uuid-placeholder') {
          m['id'] = _uuid.v4();
        }
        return m;
      }).toList();
      await put(SectionTypeEnum.education, jsonEncode(edu));
    }
    if (data['skills'] != null) {
      final skills = (data['skills'] as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        if (m['id'] == null || m['id'] == 'uuid-placeholder') {
          m['id'] = _uuid.v4();
        }
        return m;
      }).toList();
      await put(SectionTypeEnum.skills, jsonEncode(skills));
    }
    if (data['certifications'] != null) {
      final certs = (data['certifications'] as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        if (m['id'] == null || m['id'] == 'uuid-placeholder') {
          m['id'] = _uuid.v4();
        }
        return m;
      }).toList();
      await put(SectionTypeEnum.certifications, jsonEncode(certs));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(userSettingsProvider);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Tailor Your Resume',
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
        ],
        bottom: _step != _TailoredStep.generating
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: switch (_step) {
                    _TailoredStep.jobPosting => 0.33,
                    _TailoredStep.confirmation => 0.66,
                    _TailoredStep.generating => 0.80,
                    _TailoredStep.review => 1.0,
                  },
                  backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                ),
              )
            : null,
      ),
      body: switch (_step) {
        _TailoredStep.jobPosting => _JobPostingStep(
            controller: _pasteController,
            isLoading: _isLoading,
            errorMessage: _errorMessage,
            slotsRemaining: settings.remainingTailoredSlots,
            isDark: isDark,
            onUpload: _onUploadJobPosting,
            onContinue: _onExtractJobPosting,
          ),
        _TailoredStep.confirmation => _ConfirmationStep(
            jobData: _jobPostingData!,
            isLoading: _isLoading,
            errorMessage: _errorMessage,
            isDark: isDark,
            onBack: () => setState(() => _step = _TailoredStep.jobPosting),
            onGenerate: _onGenerateDraft,
            isPro: settings.tier.isPro,
            hasUnusedAddOn: _hasUnusedAddOn(),
            isLoadingAddOn: _loadingAddOn,
            addOnProduct: _addOnProduct,
            isAddOnPurchasing: _addOnPurchaseInFlight,
            addCoverLetterChecked: _addCoverLetter,
            addOnError: _addOnError,
            onCoverLetterToggle: _onCoverLetterToggle,
          ),
        _TailoredStep.generating =>
          _GeneratingView(isDark: isDark, message: _generatingMessage),
        _TailoredStep.review => _ReviewStep(
            tailoredJson: _tailoredResumeJson!,
            jobData: _jobPostingData!,
            masterResumeId: _masterResumeId,
            isLoading: _isLoading,
            errorMessage: _errorMessage,
            isDark: isDark,
            onBack: () => setState(() => _step = _TailoredStep.confirmation),
            onSave: _onSave,
          ),
      },
    );
  }
}

enum _TailoredStep { jobPosting, confirmation, generating, review }

// ─────────────────────────────────────────────────────────────────────────────
// Step 1: Job Posting Input
// ─────────────────────────────────────────────────────────────────────────────

class _JobPostingStep extends StatelessWidget {
  const _JobPostingStep({
    required this.controller,
    required this.isLoading,
    required this.errorMessage,
    required this.slotsRemaining,
    required this.isDark,
    required this.onUpload,
    required this.onContinue,
  });

  final TextEditingController controller;
  final bool isLoading;
  final String? errorMessage;
  final int slotsRemaining;
  final bool isDark;
  final VoidCallback onUpload;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Slot counter
              if (slotsRemaining >= 0)
                _SlotBadge(remaining: slotsRemaining, isDark: isDark),

              const SizedBox(height: 16),

              Text(
                'Paste the job posting',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI will extract the role requirements and tailor your master resume to match.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.55,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),

              // Upload button
              OutlinedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Upload job posting file'),
              ),
              const SizedBox(height: 12),

              Center(
                child: Text('or paste below',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
              ),
              const SizedBox(height: 12),

              // Paste text area
              TextFormField(
                controller: controller,
                maxLines: 14,
                decoration: const InputDecoration(
                  hintText:
                      'Paste the full job description here…\n\nInclude the role title, responsibilities, requirements, and any skills listed.',
                ),
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: errorMessage!, isDark: isDark),
              ],
            ],
          ),
        ),
        _StepFooter(
          onContinue: isLoading ? null : onContinue,
          continueLabel: 'Extract Requirements',
          isLoading: isLoading,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2: Confirmation — show extracted job data
// ─────────────────────────────────────────────────────────────────────────────

class _ConfirmationStep extends StatelessWidget {
  const _ConfirmationStep({
    required this.jobData,
    required this.isLoading,
    required this.errorMessage,
    required this.isDark,
    required this.onBack,
    required this.onGenerate,
    required this.isPro,
    required this.hasUnusedAddOn,
    required this.isLoadingAddOn,
    required this.addOnProduct,
    required this.isAddOnPurchasing,
    required this.addCoverLetterChecked,
    required this.addOnError,
    required this.onCoverLetterToggle,
  });

  final JobPostingData jobData;
  final bool isLoading;
  final String? errorMessage;
  final bool isDark;
  final VoidCallback onBack;
  final VoidCallback onGenerate;
  final bool isPro;
  final bool hasUnusedAddOn;
  final bool isLoadingAddOn;
  final StoreProduct? addOnProduct;
  final bool isAddOnPurchasing;
  final bool addCoverLetterChecked;
  final String? addOnError;
  final VoidCallback onCoverLetterToggle;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Role summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.work_outline, size: 16, color: accent),
                        const SizedBox(width: 8),
                        Text('Role Identified',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: accent)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (jobData.roleTitle.isNotEmpty)
                      Text(jobData.roleTitle,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          )),
                    if (jobData.companyName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(jobData.companyName,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Required skills
              if (jobData.requiredSkills.isNotEmpty) ...[
                _ExtractedSection(
                  title: 'Required Skills',
                  items: jobData.requiredSkills,
                  color:
                      isDark ? AppColors.successDark : AppColors.successLight,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
              ],

              // Keywords
              if (jobData.keywords.isNotEmpty) ...[
                _ExtractedSection(
                  title: 'ATS Keywords',
                  items: jobData.keywords,
                  color: accent,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
              ],

              // Key responsibilities
              if (jobData.responsibilities.isNotEmpty) ...[
                _ExtractedSection(
                  title: 'Key Responsibilities',
                  items: jobData.responsibilities,
                  color:
                      isDark ? AppColors.warningDark : AppColors.warningLight,
                  isDark: isDark,
                  isList: true,
                ),
              ],

              // Cover letter upsell
              const SizedBox(height: 12),
              _CoverLetterUpsell(
                isPro: isPro,
                hasUnusedAddOn: hasUnusedAddOn,
                isLoadingAddOn: isLoadingAddOn,
                addOnProduct: addOnProduct,
                isAddOnPurchasing: isAddOnPurchasing,
                addCoverLetterChecked: addCoverLetterChecked,
                addOnError: addOnError,
                onToggle: onCoverLetterToggle,
                isDark: isDark,
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: errorMessage!, isDark: isDark),
              ],
            ],
          ),
        ),
        _StepFooter(
          onBack: onBack,
          onContinue: isLoading ? null : onGenerate,
          continueLabel: 'Generate Tailored Resume',
          isLoading: isLoading,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cover Letter Upsell row (shown inside _ConfirmationStep)
// ─────────────────────────────────────────────────────────────────────────────

class _CoverLetterUpsell extends StatelessWidget {
  const _CoverLetterUpsell({
    required this.isPro,
    required this.hasUnusedAddOn,
    required this.isLoadingAddOn,
    required this.addOnProduct,
    required this.isAddOnPurchasing,
    required this.addCoverLetterChecked,
    required this.addOnError,
    required this.onToggle,
    required this.isDark,
  });

  final bool isPro;
  final bool hasUnusedAddOn;
  final bool isLoadingAddOn;
  final StoreProduct? addOnProduct;
  final bool isAddOnPurchasing;
  final bool addCoverLetterChecked;
  final String? addOnError;
  final VoidCallback onToggle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final isEntitled = isPro || hasUnusedAddOn;

    // Don't show if not entitled and the product is unavailable (can't purchase)
    if (!isEntitled && !isLoadingAddOn && addOnProduct == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isAddOnPurchasing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Checkbox(
                  value: addCoverLetterChecked,
                  onChanged: (_) => onToggle(),
                  activeColor: accent,
                  visualDensity: VisualDensity.compact,
                ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isEntitled
                      ? 'Also generate a tailored cover letter'
                      : 'Add a tailored cover letter',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isEntitled)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Included',
                      style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: accent)),
                )
              else if (isLoadingAddOn)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (addOnProduct != null)
                Text(addOnProduct!.priceString,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: accent)),
            ],
          ),
          if (!isEntitled && addOnProduct != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Text(
                'One-time purchase — no subscription',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (AppConstants.kComboTestMode) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 40),
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
          ],
          if (addOnError != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Text(addOnError!,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color:
                          isDark ? AppColors.errorDark : AppColors.errorLight)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generating view
// ─────────────────────────────────────────────────────────────────────────────

class _GeneratingView extends StatelessWidget {
  const _GeneratingView({required this.isDark, required this.message});
  final bool isDark;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Generating your tailored resume, please wait',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 28),
              Text(
                message,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'AI is reframing your experience to match the job requirements. '
                'Your existing content is being reordered and highlighted — '
                'nothing is invented.',
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
// Step 3: Review generated draft
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.tailoredJson,
    required this.jobData,
    required this.masterResumeId,
    required this.isLoading,
    required this.errorMessage,
    required this.isDark,
    required this.onBack,
    required this.onSave,
  });

  final String tailoredJson;
  final JobPostingData jobData;
  final String? masterResumeId;
  final bool isLoading;
  final String? errorMessage;
  final bool isDark;
  final VoidCallback onBack;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // AI disclosure
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (isDark
                          ? AppColors.aiIndicatorDark
                          : AppColors.aiIndicator)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (isDark
                            ? AppColors.aiIndicatorDark
                            : AppColors.aiIndicator)
                        .withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 16,
                        color: isDark
                            ? AppColors.aiIndicatorDark
                            : AppColors.aiIndicator),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'AI has tailored your resume for ${jobData.roleTitle.isNotEmpty ? jobData.roleTitle : "this role"}. '
                        'All content is based on your master resume — nothing was invented. '
                        'Review before saving, then edit freely in the Preview screen.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.5,
                          color: isDark
                              ? AppColors.aiIndicatorDark
                              : AppColors.aiIndicator,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Tailored sections summary
              _TailoredSummaryCard(
                tailoredJson: tailoredJson,
                jobData: jobData,
                isDark: isDark,
                accent: accent,
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: errorMessage!, isDark: isDark),
              ],
            ],
          ),
        ),
        _StepFooter(
          onBack: onBack,
          onContinue: isLoading ? null : onSave,
          continueLabel: 'Save & Preview',
          isLoading: isLoading,
        ),
      ],
    );
  }
}

class _TailoredSummaryCard extends StatelessWidget {
  const _TailoredSummaryCard({
    required this.tailoredJson,
    required this.jobData,
    required this.isDark,
    required this.accent,
  });

  final String tailoredJson;
  final JobPostingData jobData;
  final bool isDark;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(tailoredJson) as Map<String, dynamic>;
    } catch (_) {}

    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

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
          Text('Tailored for: ${jobData.roleTitle}',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              )),
          if (jobData.companyName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(jobData.companyName,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
          ],
          const SizedBox(height: 12),
          Divider(
              height: 1,
              color: isDark ? AppColors.borderDark : AppColors.borderLight),
          const SizedBox(height: 12),
          if (data != null) ...[
            // Summary preview
            if (data['summary'] is String &&
                (data['summary'] as String).isNotEmpty) ...[
              _PreviewField(
                  label: 'Summary',
                  value: (data['summary'] as String).length > 200
                      ? '${(data['summary'] as String).substring(0, 200)}…'
                      : data['summary'] as String,
                  isDark: isDark),
              const SizedBox(height: 10),
            ],

            // Skills preview
            if (data['skills'] is List &&
                (data['skills'] as List).isNotEmpty) ...[
              _PreviewField(
                label: 'Skills',
                value: (data['skills'] as List)
                    .take(8)
                    .map((s) => (s as Map)['name'] ?? '')
                    .join(' · '),
                isDark: isDark,
              ),
            ],
          ] else
            Text(
              'Draft generated. Tap Save & Preview to review the full resume.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewField extends StatelessWidget {
  const _PreviewField({
    required this.label,
    required this.value,
    required this.isDark,
  });
  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            )),
        const SizedBox(height: 3),
        Text(value,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurface,
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SlotBadge extends StatelessWidget {
  const _SlotBadge({required this.remaining, required this.isDark});
  final int remaining;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = remaining > 0
        ? (isDark ? AppColors.successDark : AppColors.successLight)
        : (isDark ? AppColors.warningDark : AppColors.warningLight);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.tune_outlined, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            remaining > 0
                ? '$remaining tailored resume slot${remaining == 1 ? '' : 's'} remaining this month'
                : 'No slots remaining this month — resets on your next billing date',
            style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }
}

class _ExtractedSection extends StatelessWidget {
  const _ExtractedSection({
    required this.title,
    required this.items,
    required this.color,
    required this.isDark,
    this.isList = false,
  });

  final String title;
  final List<String> items;
  final Color color;
  final bool isDark;
  final bool isList;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: 0.3,
              )),
          const SizedBox(height: 10),
          if (isList)
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.circle, size: 5, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(item,
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface))),
                    ],
                  ),
                ))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: items
                  .map((item) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border:
                              Border.all(color: color.withValues(alpha: 0.3)),
                        ),
                        child: Text(item,
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color:
                                    Theme.of(context).colorScheme.onSurface)),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _StepFooter extends StatelessWidget {
  const _StepFooter({
    this.onBack,
    required this.onContinue,
    required this.continueLabel,
    this.isLoading = false,
  });

  final VoidCallback? onBack;
  final VoidCallback? onContinue;
  final String continueLabel;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
      child: Row(
        children: [
          if (onBack != null) ...[
            OutlinedButton(
              onPressed: onBack,
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: ElevatedButton(
              onPressed: onContinue,
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(continueLabel),
            ),
          ),
        ],
      ),
    );
  }
}

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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: errorColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: errorColor),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface))),
        ],
      ),
    );
  }
}
