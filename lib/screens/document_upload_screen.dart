import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' show min;
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../models/app_enums.dart';
import '../models/resume_sections.dart';
import '../models/supporting_models.dart';
import '../providers/connectivity_provider.dart';
import '../providers/user_settings_provider.dart';
import '../services/cloudflare_worker_service.dart';
import '../services/hive_service.dart';
import '../services/resume_sanitizer.dart';
import '../theme/app_colors.dart';
import '../widgets/pending_decision_card.dart';
import '../widgets/resume_template_renderer.dart';

const _uuid = Uuid();

// Recommended upper bound for the skills list (app targets 8-12 focused
// entries) — used only to surface a soft "consider pruning" note on the
// confirmation screen, never to silently truncate.
const _kSkillsTargetMax = 12;

// ─────────────────────────────────────────────────────────────────────────────
// DocumentUploadScreen
//
// Spec §4 (Document Upload):
//   - File picker: PDF, DOCX, TXT, image. Multiple files per session.
//   - Upload progress indicator (per-file when multiple selected).
//   - Requires internet (Claude extraction).
//   - Single confirmation screen: all suggested field mappings shown at once.
//   - User taps 'Apply All' or edits individual mappings before applying.
//   - Saved to local device on confirm.
//   - Rule §3: User always reviews and confirms — no auto-apply.
//   - Rule §12: File bytes are never stored permanently — only extracted text.
//   - Tier limits: Free=4, Basic=10, Pro=unlimited documents per resume.
// ─────────────────────────────────────────────────────────────────────────────

// Thrown when a document exceeds the tier's page limit.
// Handled by _pickFiles to show a dialog rather than silently failing.
class _PageLimitException implements Exception {
  const _PageLimitException({
    required this.fileName,
    required this.pageCount,
    required this.limit,
    required this.tierName,
  });
  final String fileName;
  final int pageCount;
  final int limit;
  final String tierName;
}

// Per-file extraction result, accumulated during the sequential extraction loop.
class _FileExtractionResult {
  const _FileExtractionResult({
    required this.fileName,
    required this.fileType,
    required this.rawText,
    required this.mappings,
    required this.pendingDecisions,
  });
  final String fileName;
  final FileTypeEnum fileType;
  final String rawText;
  final List<Map<String, dynamic>> mappings;
  final List<PendingEntryDecision> pendingDecisions;
}

class DocumentUploadScreen extends ConsumerStatefulWidget {
  const DocumentUploadScreen({super.key});

  /// Pure tier-limit arithmetic, factored out so it's independently
  /// testable without Hive/Riverpod/file-picker setup. tierLimit == -1
  /// means unlimited (Pro). Never negative.
  static int remainingUploadSlots(
      {required int uploadCount, required int tierLimit}) {
    if (tierLimit == -1) return 100;
    final remaining = tierLimit - uploadCount;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  ConsumerState<DocumentUploadScreen> createState() =>
      _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends ConsumerState<DocumentUploadScreen> {
  String? _resumeId;
  DocumentRoleEnum _documentRole = DocumentRoleEnum.sourceResume;
  // When true: no resumeId exists yet (first-time setup path). _applyAll()
  // returns the prefill map to the caller instead of writing to Hive.
  bool _firstSetupMode = false;

  // Upload state machine
  _UploadState _state = _UploadState.picking;
  String? _errorMessage;

  // Multi-file extraction tracking
  List<_FileExtractionResult> _processedFiles = [];
  List<String> _failedFiles = [];
  int _extractingIndex = 0; // 1-based for display
  int _totalFiles = 0;
  String _extractingFileName = '';
  // Updated per-chunk during chunked PDF extraction ("Analyzing pages 1–4 of 14…")
  String _extractingProgressMessage = '';
  // Set when page chunks time out; shown on confirmation screen
  String? _skippedPagesNote;

  // Merged mappings shown on confirmation screen.
  // Each map has: field, suggestedValue, confidence, accepted, sourceFile,
  // and optionally: conflict (bool), hasPossibleDuplicates (bool).
  List<Map<String, dynamic>> _mappings = [];

  // Entries the extraction model couldn't confidently classify (employment
  // vs. training, or real credential vs. compliance clutter). Ephemeral —
  // never persisted. Apply All is blocked until every card is resolved.
  List<PendingEntryDecision> _pendingDecisions = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _resumeId = args['resumeId'] as String?;
      _documentRole =
          args['role'] as DocumentRoleEnum? ?? DocumentRoleEnum.sourceResume;
      _firstSetupMode = args['firstSetupMode'] as bool? ?? false;
    }
  }

  // ── Remaining slots ────────────────────────────────────────────────────────

  int _computeRemainingSlots() {
    final tier = ref.read(userSettingsProvider).tier;
    if (tier.uploadLimit == -1) return 100;
    if (_firstSetupMode) return tier.uploadLimit; // no existing uploads yet
    if (_resumeId == null) return tier.uploadLimit;
    final resume = HiveService.resumeBox.get(_resumeId);
    if (resume == null) return tier.uploadLimit;
    return DocumentUploadScreen.remainingUploadSlots(
        uploadCount: resume.uploadCount, tierLimit: tier.uploadLimit);
  }

  // ── File picking ───────────────────────────────────────────────────────────

  Future<void> _pickFiles() async {
    final isOnline = ref.read(isOnlineProvider);
    if (!isOnline) {
      setState(() => _errorMessage =
          'An internet connection is required to extract resume content.');
      return;
    }

    final remainingSlots = _computeRemainingSlots();
    if (remainingSlots <= 0) {
      _showUploadLimitDialog(ref.read(userSettingsProvider).tier);
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'jpg', 'jpeg', 'png'],
      withData: kIsWeb,
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    // Cap to remaining slots if the user selected more than allowed.
    // file_picker has no reliable cross-platform cap, so we enforce here.
    final allSelected = result.files;
    final didTruncate = allSelected.length > remainingSlots;
    final selectedFiles =
        didTruncate ? allSelected.take(remainingSlots).toList() : allSelected;

    // Filter out unsupported extensions (should not happen given allowedExtensions,
    // but guard defensively).
    final validFiles = <PlatformFile>[];
    for (final f in selectedFiles) {
      if (_extensionToFileType((f.extension ?? '').toLowerCase()) != null) {
        validFiles.add(f);
      }
    }

    if (validFiles.isEmpty) {
      setState(() => _errorMessage =
          'Unsupported file type. Please upload PDF, DOCX, TXT, or an image.');
      return;
    }

    // Reset accumulated multi-file state.
    _processedFiles = [];
    _failedFiles = [];
    _mappings = [];
    _pendingDecisions = [];

    setState(() {
      _totalFiles = validFiles.length;
      _extractingIndex = 1;
      _extractingFileName = validFiles.first.name;
      _extractingProgressMessage = '';
      _skippedPagesNote = null;
      _state = _UploadState.extracting;
      _errorMessage = null;
    });

    if (didTruncate && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Only $remainingSlots file${remainingSlots == 1 ? '' : 's'} '
            'will be processed — you are at your upload limit.'),
        duration: const Duration(seconds: 4),
      ));
    }

    // Extract files sequentially — avoid hammering the Cloudflare Worker.
    var hadPageLimitError = false;
    var hitUploadLimitMidBatch = false;
    for (int i = 0; i < validFiles.length; i++) {
      // Defense-in-depth limit re-check, right before the costly Claude API
      // call — independent of the picker-level truncation above. Re-reads
      // the persisted count fresh each iteration rather than trusting a
      // value computed once at the top of this method, so a future bug in
      // that computation (or in what it was based on) can't by itself
      // result in unbounded extraction calls on a tier that caps uploads.
      // First-setup mode has no persisted resume/count yet to re-check
      // against — the initial remainingSlots gate above is authoritative
      // there.
      if (!_firstSetupMode && _resumeId != null) {
        final freshResume = HiveService.resumeBox.get(_resumeId);
        if (freshResume != null) {
          final tier = ref.read(userSettingsProvider).tier;
          final stillAvailable = DocumentUploadScreen.remainingUploadSlots(
              uploadCount: freshResume.uploadCount + _processedFiles.length,
              tierLimit: tier.uploadLimit);
          if (stillAvailable <= 0) {
            debugPrint('[UPLOAD LIMIT] Blocked before extraction call — '
                'uploadCount=${freshResume.uploadCount}, '
                'processedThisBatch=${_processedFiles.length}, '
                'tierLimit=${tier.uploadLimit}');
            hitUploadLimitMidBatch = true;
            break;
          }
        }
      }

      final f = validFiles[i];
      final fileType =
          _extensionToFileType((f.extension ?? '').toLowerCase())!;

      if (mounted) {
        setState(() {
          _extractingIndex = i + 1;
          _extractingFileName = f.name;
        });
      }

      // Resolve bytes.
      List<int> bytes;
      try {
        if (kIsWeb) {
          final b = f.bytes;
          if (b == null) throw Exception('Could not read file bytes.');
          bytes = b;
        } else {
          final path = f.path;
          if (path == null) throw Exception('Could not access file path.');
          bytes = await File(path).readAsBytes();
        }
      } catch (_) {
        _failedFiles.add(f.name);
        continue;
      }

      try {
        final extracted = await _extractOneFile(bytes, fileType, f.name);
        if (extracted != null) {
          _processedFiles.add(extracted);
        } else {
          _failedFiles.add(f.name);
        }
      } on _PageLimitException catch (e) {
        hadPageLimitError = true;
        _failedFiles.add(f.name);
        if (mounted) await _showPageLimitDialog(e);
      }
    }

    // Hit the upload limit mid-batch before processing anything: same
    // outcome as hitting it at the top of this method — show the limit
    // dialog and return to picking rather than a generic error.
    if (hitUploadLimitMidBatch && _processedFiles.isEmpty) {
      if (mounted) {
        setState(() => _state = _UploadState.picking);
        _showUploadLimitDialog(ref.read(userSettingsProvider).tier);
      }
      return;
    }

    // If every file failed, go to error state (or back to picker if page limit
    // dialogs already explained the rejection to the user).
    if (_processedFiles.isEmpty) {
      if (mounted) {
        setState(() {
          if (hadPageLimitError) {
            // Dialogs were shown; quietly return to picker.
            _state = _UploadState.picking;
          } else {
            _state = _UploadState.error;
            _errorMessage = _failedFiles.length == 1
                ? 'Could not extract content from the file. '
                    'It may be corrupted or in an unsupported format.'
                : 'Could not extract content from any of the selected files.';
          }
        });
      }
      return;
    }

    if (hitUploadLimitMidBatch && mounted) {
      setState(() {
        const limitNote = 'Reached your upload limit partway through — '
            'the remaining files were not processed.';
        _skippedPagesNote = _skippedPagesNote == null
            ? limitNote
            : '$_skippedPagesNote\n$limitNote';
      });
    }

    // Merge results from all successfully processed files.
    _mappings = _mergeResults(_processedFiles);
    _pendingDecisions = [
      for (final f in _processedFiles) ...f.pendingDecisions,
    ];

    // When uploading into an existing resume (not first-time setup), apply
    // pre-check strategy: auto-accept empty fields, conditionally accept
    // scalar fields with existing values, flag duplicate list entries.
    if (_resumeId != null && !_firstSetupMode) {
      _applyExistingResumePrecheck();
    }

    if (mounted) {
      setState(() => _state = _UploadState.confirming);
    }
  }

  // ── Single-file extraction ─────────────────────────────────────────────────

  Future<_FileExtractionResult?> _extractOneFile(
      List<int> bytes, FileTypeEnum fileType, String fileName) async {
    try {
      // PDF takes a two-stage pipeline: Option 1 (layout text) with
      // automatic fallback to Option 3 (native PDF bytes) on timeout.
      if (fileType == FileTypeEnum.pdf) {
        final (rawText, json) = await _extractPdfFields(bytes, fileName);
        final parsed = CloudflareWorkerService.parseFieldMappings(json);
        return _FileExtractionResult(
          fileName: fileName,
          fileType: fileType,
          rawText: rawText,
          mappings: parsed.mappings,
          pendingDecisions: parsed.pendingDecisions,
        );
      }

      final String rawText;
      final String json;

      if (fileType == FileTypeEnum.image) {
        json = await CloudflareWorkerService.extractResumeFieldsFromImage(
            bytes, _imageMediaType(bytes));
        rawText = '';
      } else {
        rawText = fileType == FileTypeEnum.txt
            ? utf8.decode(bytes, allowMalformed: true)
            : _extractDocxText(bytes);

        // DOCX page-limit check: ~750 chars per page as heuristic.
        if (fileType == FileTypeEnum.docx) {
          final tier = ref.read(userSettingsProvider).tier;
          final maxPages = tier.maxPagesPerDocument;
          if (maxPages != null) {
            const charsPerPage = 750;
            final estimatedPages = (rawText.length / charsPerPage).ceil();
            if (estimatedPages > maxPages) {
              throw _PageLimitException(
                fileName: fileName,
                pageCount: estimatedPages,
                limit: maxPages,
                tierName: tier.displayName,
              );
            }
          }
        }

        json = await CloudflareWorkerService.extractResumeFields(rawText);
      }

      final parsed = CloudflareWorkerService.parseFieldMappings(json);
      return _FileExtractionResult(
        fileName: fileName,
        fileType: fileType,
        rawText: rawText,
        mappings: parsed.mappings,
        pendingDecisions: parsed.pendingDecisions,
      );
    } on _PageLimitException {
      rethrow;
    } catch (e, st) {
      debugPrint('[extractOneFile] error for $fileName: ${e.runtimeType}: $e');
      debugPrint('[extractOneFile] stacktrace: $st');
      return null;
    }
  }

  /// Orchestrates the two-stage PDF extraction pipeline.
  ///
  /// Stage 1 (Option 1): SyncFusion layout-aware text → Cloudflare (30 s).
  /// Opens the PDF, checks size, and routes to chunked or single-call extraction.
  /// Returns (rawText, extractedJson). rawText is '' for chunked/bytes paths.
  Future<(String, String)> _extractPdfFields(
      List<int> bytes, String fileName) async {
    PdfDocument? document;
    try {
      try {
        document = PdfDocument(inputBytes: bytes);
      } catch (_) {
        throw const FormatException('Could not open PDF.');
      }

      final extractor = PdfTextExtractor(document);
      final pageCount = document.pages.count;

      // Page-limit check runs locally before any network call.
      final tier = ref.read(userSettingsProvider).tier;
      final maxPages = tier.maxPagesPerDocument;
      if (maxPages != null && pageCount > maxPages) {
        throw _PageLimitException(
          fileName: fileName,
          pageCount: pageCount,
          limit: maxPages,
          tierName: tier.displayName,
        );
      }

      final rawText = _extractRawPdfText(extractor, pageCount);
      // ^ throws FormatException for scanned/empty PDFs

      // If watermark noise still dominates or the font encoding is garbled,
      // the text path can't extract useful fields. Route to the multimodal
      // PDF path so Claude reads the visual rendering instead.
      if (_isLowQualityExtraction(rawText)) {
        debugPrint('[PDF] low-quality text extraction → multimodal path');
        if (mounted) {
          setState(() {
            _extractingProgressMessage =
                'Using enhanced document reading…';
          });
        }
        const maxMultimodalBytes = 5 * 1024 * 1024; // 5 MB Cloudflare body limit
        if (bytes.length > maxMultimodalBytes) {
          throw CloudflareApiException(
            'This document is too large for enhanced extraction '
            '(${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
            'Try uploading a smaller or compressed version.',
          );
        }
        final json =
            await CloudflareWorkerService.extractResumeFieldsFromPdf(bytes);
        return ('', json);
      }

      if (pageCount > 4 || rawText.length > 8000) {
        debugPrint(
            '[PDF] $pageCount pages, ${rawText.length} chars → chunked extraction');
        final json = await _extractInChunks(extractor, pageCount);
        return ('', json);
      }

      // Small PDF: single call
      try {
        final json = await CloudflareWorkerService.extractResumeFields(rawText);
        return (rawText, json);
      } on CloudflareApiException catch (e) {
        if (e.message.contains('timed out')) {
          debugPrint('[PDF] single-call timed out → PDF bytes fallback');
          final json =
              await CloudflareWorkerService.extractResumeFieldsFromPdf(bytes);
          return ('', json);
        }
        rethrow;
      }
    } on FormatException {
      debugPrint('[PDF] local extraction failed → PDF bytes fallback');
      final json =
          await CloudflareWorkerService.extractResumeFieldsFromPdf(bytes);
      return ('', json);
    } finally {
      document?.dispose();
    }
  }

  /// Extracts all pages locally via SyncFusion. Synchronous.
  /// Throws FormatException if the PDF is scanned/empty/unreadable,
  /// or if a security/signature restriction blocks text extraction
  /// (the caller catches FormatException and falls back to PDF bytes path).
  String _extractRawPdfText(PdfTextExtractor extractor, int pageCount) {
    final pages = <String>[];
    for (int i = 0; i < pageCount; i++) {
      try {
        final text = extractor
            .extractText(startPageIndex: i, endPageIndex: i, layoutText: true)
            .trim();
        if (text.isNotEmpty) pages.add(text);
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('permission') ||
            msg.contains('security') ||
            msg.contains('encrypt') ||
            msg.contains('signature') ||
            msg.contains('restrict')) {
          // Security restriction — throw so the caller falls back to
          // the multimodal PDF bytes path (Claude reads the visual rendering).
          throw FormatException('PDF security restriction on page ${i + 1}: $e');
        }
        // Non-security page error: skip and continue with remaining pages.
        debugPrint('[PDF] page ${i + 1} extraction error (skipped): $e');
      }
    }
    if (pages.isEmpty) {
      throw const FormatException(
          'Could not extract text from this PDF — it may be password-protected '
          'or a scanned image. Try uploading a text-based PDF or an image instead.');
    }
    return _removeWatermarkNoise(_normalizeWhitespace(pages.join('\n\n')));
  }

  /// Strips text-layer watermark noise that some PDFs embed hundreds of times
  /// (e.g. APUS/AMU transcripts repeat the institution name throughout the
  /// text layer). Runs after normalizeWhitespace, before Claude sees the text.
  static String _removeWatermarkNoise(String text) {
    var s = text;

    // Targeted: APUS / AMU transcript watermark — institution name + bullet,
    // repeated inline. The regex matches 2+ consecutive repetitions.
    s = s.replaceAll(
      RegExp(
        r'(AMERICAN\s+PUBLIC\s+UNIVERSITY\s+SYSTEM\s*[•·]\s*){2,}',
        caseSensitive: false,
      ),
      '',
    );
    s = s.replaceAll(
      RegExp(
        r'(AMERICAN\s+MILITARY\s+UNIVERSITY\s*[•·]\s*){2,}',
        caseSensitive: false,
      ),
      '',
    );

    // General heuristic: a line where any word (≥5 chars) accounts for
    // ≥50 % of the tokens is a watermark/stamp line — drop it.
    s = s.split('\n').where((line) {
      final trimmed = line.trim();
      if (trimmed.length < 20) return true;
      final tokens = trimmed
          .split(RegExp(r'[\s•·|]+'))
          .where((w) => w.length >= 5)
          .map((w) => w.toLowerCase())
          .toList();
      if (tokens.length < 4) return true;
      final freq = <String, int>{};
      for (final t in tokens) {
        freq[t] = (freq[t] ?? 0) + 1;
      }
      final maxFreq = freq.values.reduce((a, b) => a > b ? a : b);
      return maxFreq < tokens.length * 0.5;
    }).join('\n');

    // Collapse blank lines left by removal.
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return s;
  }

  /// Returns true when the extracted text cannot yield useful fields via the
  /// text path. Triggers a fallback to the multimodal PDF path. Two failure modes:
  ///
  /// 1. Font encoding failure: SyncFusion outputs raw glyph IDs instead of
  ///    Unicode when the PDF uses a custom ToUnicode CMap. Result is nearly
  ///    all-uppercase shifted-ASCII gibberish. Normal English text is ~75%
  ///    lowercase; anything below 40% is a clear encoding failure.
  ///
  /// 2. Watermark-dominated: institution name repeated so many times the
  ///    real content is drowned out (separate from encoding issues).
  static bool _isLowQualityExtraction(String text) {
    if (text.isEmpty) return true;

    // Check 1 — font encoding failure.
    final letters = text.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.length > 100) {
      final lowercase = text.replaceAll(RegExp(r'[^a-z]'), '');
      final lcRatio = lowercase.length / letters.length;
      if (lcRatio < 0.40) {
        debugPrint('[EXTRACT] Font encoding failure detected — '
            'lowercase ratio: ${lcRatio.toStringAsFixed(3)} → multimodal path');
        return true;
      }
    }

    // Check 2 — watermark-dominated text.
    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final total = words.length;
    if (total < 20) return true;
    const noiseTerms = {
      'american', 'public', 'university', 'system', 'apu', 'amu', 'apus',
    };
    final noiseCount =
        words.where((w) => noiseTerms.contains(w.toLowerCase())).length;
    return noiseCount / total > 0.30;
  }

  /// Splits a large PDF into 4-page chunks, sends each to Claude sequentially,
  /// and merges the results. Updates the extracting-view progress label live.
  /// Timed-out chunks are skipped; a note is shown on the confirmation screen.
  Future<String> _extractInChunks(
      PdfTextExtractor extractor, int pageCount) async {
    const chunkSize = 2;
    final chunkJsons = <String>[];
    final skippedRanges = <String>[];

    for (int startPage = 0; startPage < pageCount; startPage += chunkSize) {
      final endPage = min(startPage + chunkSize - 1, pageCount - 1);

      if (mounted) {
        setState(() {
          _extractingProgressMessage =
              'Analyzing pages ${startPage + 1}–${endPage + 1} of $pageCount…';
        });
      }

      var chunkText = extractor.extractText(
        startPageIndex: startPage,
        endPageIndex: endPage,
        layoutText: true,
      );
      // Watermark removal runs before the char cap so noise doesn't eat budget.
      var cleaned = _removeWatermarkNoise(_normalizeWhitespace(chunkText));
      // Hard cap per chunk — prevents enormous ACE table pages from
      // exceeding the 60 s response budget even at 2 pages.
      const chunkCharLimit = 8000;
      if (cleaned.length > chunkCharLimit) {
        cleaned = cleaned.substring(0, chunkCharLimit);
      }

      if (cleaned.isEmpty) {
        debugPrint('[PDF] pages ${startPage + 1}–${endPage + 1}: empty, skipping');
        continue;
      }

      final contextHeader =
          '[Pages ${startPage + 1}–${endPage + 1} of $pageCount]\n';

      try {
        final json = await CloudflareWorkerService.extractResumeFields(
          contextHeader + cleaned,
          timeout: const Duration(seconds: 60),
        );
        chunkJsons.add(json);
        debugPrint('[PDF] pages ${startPage + 1}–${endPage + 1}: OK');
      } on CloudflareApiException catch (e) {
        if (e.message.contains('timed out')) {
          debugPrint(
              '[PDF] pages ${startPage + 1}–${endPage + 1}: timed out, skipping');
          skippedRanges.add('${startPage + 1}–${endPage + 1}');
        } else {
          rethrow;
        }
      }
    }

    if (chunkJsons.isEmpty) {
      throw const CloudflareApiException(
          'No content could be extracted from this document.');
    }

    if (skippedRanges.isNotEmpty && mounted) {
      setState(() {
        _skippedPagesNote = 'Note: Pages ${skippedRanges.join(', ')} '
            'could not be analyzed due to timeout and were skipped. '
            'You may want to manually review those pages for missing information.';
      });
    }

    return _mergeChunkJsons(chunkJsons);
  }

  /// Merges JSON strings returned by individual chunk calls.
  /// Scalars: first non-empty value across chunks wins.
  /// Lists: union of all entries (deduplication is done by _mergeResults later).
  String _mergeChunkJsons(List<String> jsonStrings) {
    final chunks = <Map<String, dynamic>>[];
    for (final s in jsonStrings) {
      try {
        var cleaned = s.trim();
        if (cleaned.startsWith('```')) {
          cleaned = cleaned
              .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
              .replaceFirst(RegExp(r'\s*```$'), '')
              .trim();
        }
        chunks.add(jsonDecode(cleaned) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (chunks.isEmpty) return jsonEncode({});

    const contactSubFields = [
      'firstName', 'lastName', 'professionalTitle', 'city', 'state',
      'phone', 'email', 'linkedInUrl', 'websiteUrl', 'gitHubUrl',
    ];
    final mergedContact = <String, dynamic>{};
    for (final field in contactSubFields) {
      for (final chunk in chunks) {
        final v = (chunk['contact'] as Map<String, dynamic>?)?[field];
        if (v != null && v.toString().isNotEmpty) {
          mergedContact[field] = v;
          break; // first non-empty wins
        }
      }
    }

    final merged = <String, dynamic>{
      if (mergedContact.isNotEmpty) 'contact': mergedContact,
    };

    for (final chunk in chunks) {
      if (!merged.containsKey('summary')) {
        final v = chunk['summary'] as String?;
        if (v != null && v.isNotEmpty) merged['summary'] = v;
      }
    }

    // Collect all list-field entries across chunks.
    final allExperience = <dynamic>[];
    final allEducation = <dynamic>[];
    final allSkills = <dynamic>[];
    final allCertifications = <dynamic>[];
    for (final chunk in chunks) {
      final exp = chunk['experience'];
      if (exp is List) allExperience.addAll(exp);
      final edu = chunk['education'];
      if (edu is List) allEducation.addAll(edu);
      final sk = chunk['skills'];
      if (sk is List) allSkills.addAll(sk);
      final certs = chunk['certifications'];
      if (certs is List) allCertifications.addAll(certs);
    }

    // Deduplicate skills by normalized name.
    final seenSkillNames = <String>{};
    final dedupedSkills = allSkills.where((s) {
      final name =
          ((s as Map<String, dynamic>)['name'] as String? ?? '').toLowerCase().trim();
      return name.isNotEmpty && seenSkillNames.add(name);
    }).toList();

    // Fuzzy-deduplicate certifications collected across chunks. Employment-
    // vs-training and degree-vs-non-degree-training classification (and any
    // resulting promotion of entries into this certifications list) happens
    // once, centrally, in CloudflareWorkerService.parseFieldMappings — which
    // runs on this merged JSON next — so it applies uniformly whether the
    // source was a single-call extraction or a multi-chunk PDF like this one.
    final dedupedCerts = ResumeSanitizer.deduplicateCertifications(allCertifications);

    // Normalize experience dates — a single award/completion date shouldn't
    // duplicate as both startDate and endDate.
    final normalizedExperience = allExperience.map((e) {
      final map = Map<String, dynamic>.from(e as Map<String, dynamic>);
      final start = map['startDate'] as String? ?? '';
      final end = map['endDate'] as String? ?? '';
      if (end.isNotEmpty && end == start) {
        map['endDate'] = '';
      } else if (start.isEmpty && end.isNotEmpty) {
        map['startDate'] = end;
        map['endDate'] = '';
      }
      return map;
    }).toList();

    if (normalizedExperience.isNotEmpty) merged['experience'] = normalizedExperience;
    if (allEducation.isNotEmpty) merged['education'] = allEducation;
    if (dedupedSkills.isNotEmpty) merged['skills'] = dedupedSkills;
    if (dedupedCerts.isNotEmpty) merged['certifications'] = dedupedCerts;

    return jsonEncode(merged);
  }

  // ── Merge strategy ─────────────────────────────────────────────────────────
  //
  // Scalar fields (contact.*, summary):
  //   - All files agree on value → one row, sourceFile annotated.
  //   - Files disagree → show all distinct values with conflict: true so the
  //     user can pick. Last accepted row in list wins when writing (= last
  //     processed file is the tiebreaker, per spec).
  //
  // Skills:
  //   - Union all entries, deduplicate by name (case-insensitive). Silent.
  //
  // Experience / Education / Certifications:
  //   - Union all entries (show everything, let user remove duplicates).
  //   - Flag hasPossibleDuplicates: true if a likely-duplicate pair is detected.
  //   - Duplicate heuristics:
  //       Experience    : same normalised company name
  //       Education     : same normalised institution name
  //       Certifications: same cert name (case-insensitive)

  List<Map<String, dynamic>> _mergeResults(
      List<_FileExtractionResult> files) {
    if (files.length == 1) {
      return files.first.mappings
          .map((m) => Map<String, dynamic>.from(m)
            ..['sourceFile'] = files.first.fileName)
          .toList();
    }

    // Collect scalar and list field candidates separately.
    final scalarCandidates = <String, List<Map<String, dynamic>>>{};
    final listCandidates = <String,
        List<({List<dynamic> entries, String sourceFile, double confidence})>>{};

    for (final file in files) {
      for (final m in file.mappings) {
        final field = m['field'] as String;
        if (_isListField(field)) {
          listCandidates.putIfAbsent(field, () => []).add((
            entries: m['suggestedValue'] as List<dynamic>,
            sourceFile: file.fileName,
            confidence: m['confidence'] as double,
          ));
        } else {
          scalarCandidates
              .putIfAbsent(field, () => [])
              .add(Map<String, dynamic>.from(m)..['sourceFile'] = file.fileName);
        }
      }
    }

    final merged = <Map<String, dynamic>>[];

    // Scalar fields
    for (final field in scalarCandidates.keys) {
      final candidates = scalarCandidates[field]!;
      if (candidates.length == 1) {
        merged.add(candidates.first);
        continue;
      }
      // Check if all candidate values are equivalent.
      final firstVal = _normalizeScalar(candidates.first['suggestedValue']);
      final allSame = candidates
          .every((c) => _normalizeScalar(c['suggestedValue']) == firstVal);
      if (allSame) {
        merged.add(Map<String, dynamic>.from(candidates.first)
          ..['sourceFile'] = 'multiple files');
      } else {
        // Conflicting values: radio group — exactly one can be selected.
        // Pre-select the first candidate (first processed file = tiebreaker).
        // conflictGroupId is the field key; the state uses it to enforce
        // mutual exclusion when the user taps a row.
        for (int ci = 0; ci < candidates.length; ci++) {
          merged.add(Map<String, dynamic>.from(candidates[ci])
            ..['conflict'] = true
            ..['conflictGroupId'] = field
            ..['accepted'] = ci == 0);
        }
      }
    }

    // List fields
    for (final field in listCandidates.keys) {
      final sources = listCandidates[field]!;
      final confidence =
          sources.map((s) => s.confidence).reduce((a, b) => a > b ? a : b);
      final sourceFile =
          sources.length == 1 ? sources.first.sourceFile : 'multiple files';

      List<dynamic> mergedList;
      bool hasDuplicates;

      if (field == 'skills') {
        // Deduplicate by name (silent).
        final seen = <String>{};
        mergedList = [];
        for (final src in sources) {
          for (final entry in src.entries) {
            final map = entry as Map<String, dynamic>;
            final name = (map['name'] as String? ?? '').toLowerCase().trim();
            if (seen.add(name) && name.isNotEmpty) {
              mergedList.add(entry);
            }
          }
        }
        hasDuplicates = false;
      } else {
        mergedList = sources.expand((s) => s.entries).toList();
        hasDuplicates = _hasPossibleDuplicates(field, mergedList);
      }

      merged.add({
        'field': field,
        'suggestedValue': mergedList,
        'confidence': confidence,
        'accepted': true,
        'sourceFile': sourceFile,
        'hasPossibleDuplicates': hasDuplicates,
      });
    }

    // Sort: scalars by confidence descending, list fields appended after.
    final scalars =
        merged.where((m) => !_isListField(m['field'] as String)).toList()
          ..sort((a, b) => (b['confidence'] as double)
              .compareTo(a['confidence'] as double));
    final lists =
        merged.where((m) => _isListField(m['field'] as String)).toList();

    return [...scalars, ...lists];
  }

  // ── Pre-check against existing resume data ────────────────────────────────

  // Adjusts the accepted flag and adds annotation notes on mappings when
  // uploading into a resume that already has content. Called only when
  // _resumeId is non-null and this is not first-time setup.
  void _applyExistingResumePrecheck() {
    if (_resumeId == null) return;
    final existing = ResumeRenderData.fromHive(_resumeId!);

    for (int i = 0; i < _mappings.length; i++) {
      final m = _mappings[i];
      final field = m['field'] as String;
      final suggested = m['suggestedValue'];

      if (_isListField(field)) {
        // Combine existing + suggested entries and check for duplicates.
        final existingEntries = <dynamic>[];
        switch (field) {
          case 'experience':
            existingEntries.addAll(existing.experience.map((e) => e.toJson()));
          case 'education':
            existingEntries.addAll(existing.education.map((e) => e.toJson()));
          case 'skills':
            existingEntries.addAll(existing.skills.map((e) => e.toJson()));
          case 'certifications':
            existingEntries
                .addAll(existing.certifications.map((e) => e.toJson()));
        }
        if (existingEntries.isEmpty) continue;
        final combined = [...existingEntries, ...(suggested as List)];
        if (_hasPossibleDuplicates(field, combined)) {
          _mappings[i] = Map<String, dynamic>.from(m)
            ..['hasPossibleDuplicates'] = true;
        }
      } else {
        // Scalar field — compare against existing value.
        final existingValue = _existingFieldValue(existing, field);
        if (existingValue.isEmpty) continue; // Field empty → keep accepted

        final suggestedStr = (suggested?.toString() ?? '').trim();
        final existingNorm = existingValue.toLowerCase().trim();
        final suggestedNorm = suggestedStr.toLowerCase().trim();

        if (existingNorm == suggestedNorm) {
          _mappings[i] = Map<String, dynamic>.from(m)
            ..['accepted'] = false
            ..['existingNote'] = 'Already in resume';
        } else if (suggestedStr.length > (existingValue.length * 1.1).ceil()) {
          // Suggested is meaningfully longer → likely more detailed, keep accepted
        } else {
          _mappings[i] = Map<String, dynamic>.from(m)
            ..['accepted'] = false
            ..['existingNote'] = 'Field already has a value';
        }
      }
    }
  }

  static String _existingFieldValue(ResumeRenderData data, String field) {
    return switch (field) {
      'contact.firstName' => data.contact.firstName,
      'contact.lastName' => data.contact.lastName,
      'contact.professionalTitle' => data.contact.professionalTitle,
      'contact.city' => data.contact.city,
      'contact.state' => data.contact.state,
      'contact.phone' => data.contact.phone,
      'contact.email' => data.contact.email,
      'contact.linkedInUrl' => data.contact.linkedInUrl ?? '',
      'contact.websiteUrl' => data.contact.websiteUrl ?? '',
      'contact.gitHubUrl' => data.contact.gitHubUrl ?? '',
      'summary' => data.summary,
      _ => '',
    };
  }

  // ── Field classification ───────────────────────────────────────────────────

  static bool _isListField(String field) =>
      field == 'experience' ||
      field == 'education' ||
      field == 'skills' ||
      field == 'certifications';

  static String _normalizeScalar(dynamic v) =>
      (v?.toString() ?? '').toLowerCase().trim();

  // Cross-document duplicate detection. A user uploading multiple source
  // documents (a resume + a transcript, an old resume + a LinkedIn export,
  // a JST + a Soldier Talent Profile) can end up with the same role or
  // entry recorded twice with mismatched or incomplete dates — this applies
  // to anyone with more than one source document, not any particular kind
  // of document, so the check in ResumeSanitizer has no document-type gate.
  static bool _hasPossibleDuplicates(String field, List<dynamic> entries) {
    if (entries.length < 2) return false;
    for (int i = 0; i < entries.length; i++) {
      for (int j = i + 1; j < entries.length; j++) {
        final a = entries[i] as Map<String, dynamic>;
        final b = entries[j] as Map<String, dynamic>;
        if (field == 'experience') {
          if (ResumeSanitizer.isLikelyCrossDocumentDuplicateRole(a, b)) {
            return true;
          }
        } else if (field == 'education') {
          final an = ResumeSanitizer.normalizeInstitution(
              a['institution'] as String? ?? '');
          final bn = ResumeSanitizer.normalizeInstitution(
              b['institution'] as String? ?? '');
          if (an.isNotEmpty && an == bn) return true;
        } else if (field == 'certifications') {
          final an = (a['name'] as String? ?? '').toLowerCase().trim();
          final bn = (b['name'] as String? ?? '').toLowerCase().trim();
          if (an.isNotEmpty && an == bn) return true;
        }
      }
    }
    return false;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  FileTypeEnum? _extensionToFileType(String ext) {
    return switch (ext) {
      'pdf' => FileTypeEnum.pdf,
      'docx' => FileTypeEnum.docx,
      'txt' => FileTypeEnum.txt,
      'jpg' || 'jpeg' || 'png' => FileTypeEnum.image,
      _ => null,
    };
  }

  String _imageMediaType(List<int> bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  // ── DOCX / PDF local extraction ────────────────────────────────────────────

  String _extractDocxText(List<int> bytes) {
    final zip = ZipDecoder().decodeBytes(bytes);
    final docFile = zip.findFile('word/document.xml');
    if (docFile == null) {
      throw const FormatException(
          'Could not read this Word document — it may be corrupted or not a valid .docx file.');
    }
    final xmlString = utf8.decode(docFile.content as List<int>);
    final document = XmlDocument.parse(xmlString);

    const wNs =
        'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    final paragraphs = document.findAllElements('p', namespace: wNs);
    final lines = paragraphs.map((p) {
      return p
          .findAllElements('t', namespace: wNs)
          .map((t) => t.innerText)
          .join('');
    }).where((line) => line.isNotEmpty);

    return lines.join('\n');
  }

  // ── PDF text helpers ───────────────────────────────────────────────────────

  /// Collapses whitespace artifacts common in grid/form PDFs:
  /// 3+ consecutive spaces → one space; 3+ newlines → double newline;
  /// trailing whitespace stripped from each line.
  static String _normalizeWhitespace(String text) {
    return text
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .replaceAll(RegExp(r' {3,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Extracts text from a PDF using layout-aware ordering, then normalizes
  /// whitespace. Throws [FormatException] for scanned/encrypted documents.

  // ── Pending decision resolution ────────────────────────────────────────────

  /// Routes a resolved pending-entry decision into the right mapping row,
  /// running it through the same sanitizer path any other extracted entry
  /// takes (bullet cap when routed to experience). Removes the card once
  /// resolved. A skipped/dismissed card must resolve to
  /// [EntryDecision.exclude] — never a silent default to inclusion, since
  /// silently including or dropping an entry nobody looked at is the exact
  /// failure mode this card exists to prevent.
  void _resolvePendingDecision(String id, EntryDecision decision) {
    final index = _pendingDecisions.indexWhere((d) => d.id == id);
    if (index == -1) return;
    final pending = _pendingDecisions[index];

    setState(() {
      _pendingDecisions.removeAt(index);

      if (decision == EntryDecision.exclude) return;

      if (decision == EntryDecision.employment) {
        final entry = Map<String, dynamic>.from(pending.rawEntry)
          ..remove('entryType')
          ..remove('uncertaintyReason');
        entry['bullets'] = ResumeSanitizer.capBullets(
          (entry['bullets'] as List<dynamic>?)
                  ?.map((b) => b.toString())
                  .toList() ??
              [],
        );
        _appendToListMapping('experience', entry);
      } else if (decision == EntryDecision.certification) {
        final Map<String, dynamic> cert;
        if (pending.kind == PendingDecisionKind.employmentVsTraining) {
          // Came from an experience-shaped entry — convert to cert shape.
          cert = {
            'id': 'uuid-placeholder',
            'name': pending.rawTitle,
            'issuer': pending.rawCompany,
            'dateEarned': pending.rawEntry['startDate'] as String? ?? '',
            'expiresDate': null,
            'credentialId': null,
            'isAIPrefilled': true,
          };
        } else {
          cert = Map<String, dynamic>.from(pending.rawEntry)
            ..remove('certType')
            ..remove('certUncertaintyReason');
        }
        _appendToListMapping('certifications', cert);
      }
    });
  }

  /// Appends [entry] into the existing mapping row for [field], creating the
  /// row if this document produced no confident entries for that field.
  void _appendToListMapping(String field, Map<String, dynamic> entry) {
    final index = _mappings.indexWhere((m) => m['field'] == field);
    if (index == -1) {
      _mappings.add({
        'field': field,
        'suggestedValue': [entry],
        'confidence': 0.88,
        'accepted': true,
      });
      return;
    }
    final existing = _mappings[index];
    final list = List<dynamic>.from(existing['suggestedValue'] as List);
    list.add(entry);
    _mappings[index] = Map<String, dynamic>.from(existing)
      ..['suggestedValue'] = list;
  }

  // ── Apply mappings ─────────────────────────────────────────────────────────

  Future<void> _applyAll() async {
    setState(() => _state = _UploadState.saving);

    // ── First-setup mode: return prefill map to caller ────────────────────
    if (_firstSetupMode) {
      try {
        final prefill = _buildPrefillFromMappings();
        if (mounted) Navigator.pop(context, prefill);
      } catch (_) {
        if (mounted) {
          setState(() {
            _state = _UploadState.error;
            _errorMessage = 'Failed to process. Please try again.';
          });
        }
      }
      return;
    }

    // ── Normal mode: write to an existing resume in Hive ──────────────────
    if (_resumeId == null) return;

    try {
      // One SourceDocument record per successfully processed file.
      final acceptedFields = _mappings
          .where((m) => m['accepted'] == true)
          .map((m) => m['field'] as String)
          .toSet()
          .toList();

      for (final file in _processedFiles) {
        final docId = _uuid.v4();
        final doc = SourceDocument(
          id: docId,
          resumeId: _resumeId!,
          fileName: file.fileName,
          fileType: file.fileType,
          documentRole: _documentRole,
          uploadedAt: DateTime.now(),
          extractionStatus: ExtractionStatusEnum.complete,
          rawExtractedText: file.rawText,
          appliedFields: acceptedFields,
        );
        await HiveService.sourceDocumentBox.put(docId, doc);
      }

      // Increment uploadCount by actual file count (not 1).
      final resume = HiveService.resumeBox.get(_resumeId);
      if (resume != null) {
        resume.uploadCount += _processedFiles.length;
        await resume.save();
        final check = HiveService.resumeBox.get(_resumeId);
        debugPrint('[UPLOAD COUNT] Hive value: ${check?.uploadCount}');
        debugPrint('[UPLOAD COUNT] Source docs in box: '
            '${HiveService.sourceDocumentBox.values.where((d) => d.resumeId == _resumeId).length}');
      } else {
        debugPrint('[UPLOAD COUNT] SKIPPED — _resumeId=$_resumeId resume=null');
        debugPrint('[UPLOAD COUNT] Source docs in box: '
            '${HiveService.sourceDocumentBox.values.where((d) => d.resumeId == _resumeId).length}');
      }

      await _writeMappingsToSections();

      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _state = _UploadState.error;
          _errorMessage = 'Failed to save. Please try again.';
        });
      }
    }
  }

  // Build the prefill map for first-setup mode from accepted mappings.
  // Reconstructs structured data from the merged _mappings list so no
  // raw JSON string is needed.
  //
  // Also includes raw per-file metadata (under '_sourceDocuments') so the
  // wizard — which is where the Resume record and its id are actually
  // created — can create the matching SourceDocument records and seed
  // Resume.uploadCount correctly on first save. Document-upload mode can't
  // do this itself here: no resumeId exists yet at this point in the
  // first-setup flow. Losing this handoff is exactly what previously left
  // uploadCount stuck at 0 for every first-setup resume.
  Map<String, dynamic> _buildPrefillFromMappings() {
    final accepted = _mappings.where((m) => m['accepted'] == true).toList();
    final prefill = <String, dynamic>{};

    final acceptedFields = accepted.map((m) => m['field'] as String).toSet().toList();
    prefill['_sourceDocuments'] = _processedFiles
        .map((f) => {
              'fileName': f.fileName,
              'fileType': f.fileType.name,
              'rawExtractedText': f.rawText,
              'appliedFields': acceptedFields,
            })
        .toList();

    // Contact: assemble sub-field map; for conflicts, last-accepted wins.
    final contactMap = <String, dynamic>{};
    for (final m in accepted) {
      final field = m['field'] as String;
      if (field.startsWith('contact.')) {
        contactMap[field.substring('contact.'.length)] = m['suggestedValue'];
      }
    }
    if (contactMap.isNotEmpty) prefill['contact'] = contactMap;

    // Summary: last-accepted value wins for conflicts.
    final summaryRows =
        accepted.where((m) => m['field'] == 'summary').toList();
    if (summaryRows.isNotEmpty) {
      prefill['summary'] = summaryRows.last['suggestedValue'];
    }

    // List fields: assign fresh IDs.
    for (final field in ['experience', 'education', 'skills', 'certifications']) {
      final row =
          accepted.where((m) => m['field'] == field).firstOrNull;
      if (row != null) {
        prefill[field] = (row['suggestedValue'] as List).map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          map['id'] = _uuid.v4();
          return map;
        }).toList();
      }
    }

    return prefill;
  }

  Future<void> _writeMappingsToSections() async {
    if (_resumeId == null) return;

    final accepted = _mappings.where((m) => m['accepted'] == true).toList();

    Future<void> putSection(SectionTypeEnum type, String jsonData) async {
      final key = '${_resumeId}_${type.name}';
      final existing = HiveService.resumeSectionBox.get(key);
      if (existing != null) {
        existing.data = jsonData;
        existing.hasUnreviewedAIContent = true;
        await existing.save();
      } else {
        await HiveService.resumeSectionBox.put(
          key,
          ResumeSection(
            id: _uuid.v4(),
            resumeId: _resumeId!,
            type: type,
            data: jsonData,
            hasUnreviewedAIContent: true,
          ),
        );
      }
    }

    try {
      // Contact: assemble sub-field map; for conflicts, last-accepted wins.
      final contactMap = <String, dynamic>{};
      for (final m in accepted) {
        final field = m['field'] as String;
        if (field.startsWith('contact.')) {
          contactMap[field.substring('contact.'.length)] = m['suggestedValue'];
        }
      }
      if (contactMap.isNotEmpty) {
        await putSection(SectionTypeEnum.contact, jsonEncode(contactMap));
      }

      // Summary: last-accepted wins for conflicts.
      final summaryRows =
          accepted.where((m) => m['field'] == 'summary').toList();
      if (summaryRows.isNotEmpty) {
        await putSection(SectionTypeEnum.summary,
            jsonEncode({'text': summaryRows.last['suggestedValue']}));
      }

      // List fields
      Future<void> writeListField(String field, SectionTypeEnum type) async {
        final row =
            accepted.where((m) => m['field'] == field).firstOrNull;
        if (row == null) return;
        final entries = (row['suggestedValue'] as List).map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          map['id'] = _uuid.v4();
          return map;
        }).toList();
        await putSection(type, jsonEncode(entries));
      }

      await writeListField('experience', SectionTypeEnum.experience);
      await writeListField('education', SectionTypeEnum.education);
      await writeListField('skills', SectionTypeEnum.skills);
      await writeListField('certifications', SectionTypeEnum.certifications);
    } catch (_) {
      // Silently skip bad sections — user can review in editor.
    }
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  Future<void> _showPageLimitDialog(_PageLimitException e) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Document too long',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w600),
        ),
        content: Text(
          '"${e.fileName}" has ${e.pageCount} pages — '
          'the limit for ${e.tierName} accounts is ${e.limit} pages per document.\n\n'
          'Upgrade to Basic (50 pages) or Pro (unlimited) to upload longer documents.',
          style: GoogleFonts.inter(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, AppConstants.routePaywall);
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  void _showUploadLimitDialog(TierEnum tier) {
    final limitText =
        tier.uploadLimit == -1 ? 'unlimited' : '${tier.uploadLimit}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Upload limit reached',
            style: GoogleFonts.playfairDisplay(
                fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text(
          'You\'ve used all $limitText document uploads for this resume '
          'on your ${tier.displayName} plan. '
          'Upgrade to upload more source documents.',
          style: GoogleFonts.inter(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, AppConstants.routePaywall);
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final multiFile = _processedFiles.length > 1;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Upload Document',
            style: GoogleFonts.playfairDisplay(
                fontSize: 20, fontWeight: FontWeight.w600)),
      ),
      body: switch (_state) {
        _UploadState.picking => _buildPickerView(isDark),
        _UploadState.extracting => _ExtractingView(
            fileName: _extractingFileName,
            isDark: isDark,
            currentIndex: _extractingIndex,
            total: _totalFiles,
            progressMessage: _extractingProgressMessage,
          ),
        _UploadState.confirming => ConfirmationView(
            processedFileNames:
                _processedFiles.map((f) => f.fileName).toList(),
            failedFileNames: _failedFiles,
            mappings: _mappings,
            pendingDecisions: _pendingDecisions,
            isDark: isDark,
            showSourceFile: multiFile,
            skippedPagesNote: _skippedPagesNote,
            onToggleMapping: (i, accepted) {
              setState(() {
                final groupId =
                    _mappings[i]['conflictGroupId'] as String?;
                if (groupId != null) {
                  // Radio group: can't deselect the current selection,
                  // only switch to another option in the group.
                  if (!accepted) return;
                  for (final m in _mappings) {
                    if (m['conflictGroupId'] == groupId) m['accepted'] = false;
                  }
                }
                _mappings[i]['accepted'] = accepted;
              });
            },
            onResolveDecision: _resolvePendingDecision,
            onApplyAll: _applyAll,
            onCancel: () => setState(() {
              _state = _UploadState.picking;
              _mappings = [];
              _pendingDecisions = [];
              _processedFiles = [];
              _failedFiles = [];
              _errorMessage = null;
              _skippedPagesNote = null;
            }),
          ),
        _UploadState.saving => const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Saving extracted content…'),
              ],
            ),
          ),
        _UploadState.error => _ErrorView(
            message: _errorMessage ?? 'An unknown error occurred.',
            isDark: isDark,
            onRetry: () => setState(() {
              _state = _UploadState.picking;
              _errorMessage = null;
              _skippedPagesNote = null;
            }),
          ),
      },
    );
  }

  Widget _buildPickerView(bool isDark) {
    final tier = ref.read(userSettingsProvider).tier;
    final freshResume =
        _resumeId != null ? HiveService.resumeBox.get(_resumeId) : null;
    return _PickerView(
      isDark: isDark,
      errorMessage: _errorMessage,
      onPick: _pickFiles,
      uploadCount: freshResume?.uploadCount ?? 0,
      uploadLimit: tier.uploadLimit,
      maxPagesPerDocument: tier.maxPagesPerDocument,
      tierName: tier.displayName,
    );
  }
}

enum _UploadState { picking, extracting, confirming, saving, error }

// ─────────────────────────────────────────────────────────────────────────────
// Picker View
// ─────────────────────────────────────────────────────────────────────────────

class _PickerView extends StatelessWidget {
  const _PickerView({
    required this.isDark,
    required this.errorMessage,
    required this.onPick,
    required this.uploadCount,
    required this.uploadLimit,
    required this.maxPagesPerDocument,
    required this.tierName,
  });

  final bool isDark;
  final String? errorMessage;
  final VoidCallback onPick;
  final int uploadCount;
  final int uploadLimit; // -1 = unlimited
  final int? maxPagesPerDocument; // null = unlimited
  final String tierName;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    final bool isUnlimitedDocs = uploadLimit == -1;
    final String docsLabel = isUnlimitedDocs
        ? 'Documents: $uploadCount uploaded'
        : 'Documents: $uploadCount of $uploadLimit used';
    final String pagesLabel = maxPagesPerDocument != null
        ? 'Max $maxPagesPerDocument pages per document'
        : 'Unlimited pages';
    final double? docProgress = isUnlimitedDocs || uploadLimit == 0
        ? null
        : (uploadCount / uploadLimit).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upload your documents',
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select one or more files. AI will extract your information '
            'and suggest field mappings — you review everything before it\'s applied.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.55,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),

          // Capacity card
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$docsLabel  ·  $pagesLabel',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (docProgress != null) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: docProgress,
                      minHeight: 4,
                      backgroundColor: border,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Upload drop zone
          GestureDetector(
            onTap: onPick,
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: accent.withValues(alpha: 0.4),
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.upload_file_outlined, size: 52, color: accent),
                  const SizedBox(height: 16),
                  Text(
                    'Tap to select files',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PDF  ·  Word (.docx)  ·  Text (.txt)  ·  Images',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorChip(message: errorMessage!, isDark: isDark),
          ],

          const Spacer(),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.security_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your files are processed by AI and then discarded. '
                    'Only the extracted text is saved to your device.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
// Extracting View — shows per-file progress when multiple files selected
// ─────────────────────────────────────────────────────────────────────────────

class _ExtractingView extends StatelessWidget {
  const _ExtractingView({
    required this.fileName,
    required this.isDark,
    this.currentIndex = 1,
    this.total = 1,
    this.progressMessage = '',
  });
  final String fileName;
  final bool isDark;
  final int currentIndex;
  final int total;
  final String progressMessage;

  @override
  Widget build(BuildContext context) {
    final progressText = total > 1
        ? 'Extracting file $currentIndex of $total…'
        : 'Reading your document…';

    return Semantics(
      liveRegion: true,
      label: progressMessage.isNotEmpty
          ? '$progressText $fileName — $progressMessage'
          : '$progressText $fileName',
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 28),
            Text(
              progressText,
              style: GoogleFonts.playfairDisplay(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              fileName,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (progressMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                progressMessage,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (total > 1) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: (currentIndex - 1) / total),
            ],
            const SizedBox(height: 16),
            Text(
              'AI is extracting your experience, education, and skills. '
              'This usually takes 10–20 seconds per file.',
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Confirmation View
// Rule §3: User always reviews and confirms before any data is applied.
// ─────────────────────────────────────────────────────────────────────────────

class ConfirmationView extends StatelessWidget {
  const ConfirmationView({
    super.key,
    required this.processedFileNames,
    required this.failedFileNames,
    required this.mappings,
    required this.pendingDecisions,
    required this.isDark,
    required this.showSourceFile,
    required this.onToggleMapping,
    required this.onResolveDecision,
    required this.onApplyAll,
    required this.onCancel,
    this.skippedPagesNote,
  });

  final List<String> processedFileNames;
  final List<String> failedFileNames;
  final List<Map<String, dynamic>> mappings;
  final List<PendingEntryDecision> pendingDecisions;
  final bool isDark;
  final bool showSourceFile;
  final void Function(int index, bool accepted) onToggleMapping;
  final void Function(String id, EntryDecision decision) onResolveDecision;
  final VoidCallback onApplyAll;
  final VoidCallback onCancel;
  final String? skippedPagesNote;

  String _fieldLabel(String field) {
    return switch (field) {
      'contact.firstName' => 'First Name',
      'contact.lastName' => 'Last Name',
      'contact.professionalTitle' => 'Professional Title',
      'contact.city' => 'City',
      'contact.state' => 'State',
      'contact.phone' => 'Phone',
      'contact.email' => 'Email',
      'contact.linkedInUrl' => 'LinkedIn URL',
      'contact.websiteUrl' => 'Website',
      'contact.gitHubUrl' => 'GitHub',
      'summary' => 'Professional Summary',
      'experience' => 'Work Experience',
      'education' => 'Education',
      'skills' => 'Skills',
      'certifications' => 'Certifications',
      _ => field,
    };
  }

  String _valuePreview(dynamic value) {
    if (value is String) {
      return value.length > 80 ? '${value.substring(0, 80)}…' : value;
    }
    if (value is List) {
      return '${value.length} item${value.length == 1 ? '' : 's'} found';
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final acceptedCount = mappings.where((m) => m['accepted'] == true).length;
    final filesSummary = processedFileNames.length == 1
        ? processedFileNames.first
        : '${processedFileNames.length} files';

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 18,
                      color: isDark
                          ? AppColors.successDark
                          : AppColors.successLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Extracted from $filesSummary — review before applying',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$acceptedCount of ${mappings.length} fields selected',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (pendingDecisions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 15,
                        color: isDark
                            ? AppColors.warningDark
                            : AppColors.warningLight),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${pendingDecisions.length} '
                        'entr${pendingDecisions.length == 1 ? 'y needs' : 'ies need'} '
                        'your input before you can apply',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.warningDark
                              : AppColors.warningLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // Warn about files that failed extraction
              if (failedFileNames.isNotEmpty) ...[
                const SizedBox(height: 6),
                _ErrorChip(
                  message:
                      'Could not extract: ${failedFileNames.join(', ')}',
                  isDark: isDark,
                ),
              ],
              if (skippedPagesNote != null) ...[
                const SizedBox(height: 6),
                _ErrorChip(
                  message: skippedPagesNote!,
                  isDark: isDark,
                ),
              ],
            ],
          ),
        ),

        // Field mapping list
        Expanded(
          child: mappings.isEmpty && pendingDecisions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off,
                          size: 48,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(
                        'No fields could be extracted',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The document may be image-based or in an unsupported format.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: pendingDecisions.length + mappings.length,
                  itemBuilder: (ctx, i) {
                    if (i < pendingDecisions.length) {
                      final decision = pendingDecisions[i];
                      return PendingDecisionCard(
                        decision: decision,
                        isDark: isDark,
                        onResolve: (choice) =>
                            onResolveDecision(decision.id, choice),
                      );
                    }

                    final m = mappings[i - pendingDecisions.length];
                    final accepted = m['accepted'] as bool;
                    final field = m['field'] as String;
                    final value = m['suggestedValue'];
                    final confidence =
                        ((m['confidence'] as double) * 100).round();
                    final sourceFile =
                        showSourceFile ? m['sourceFile'] as String? : null;
                    final isConflict = m['conflict'] == true;
                    final hasDuplicates = m['hasPossibleDuplicates'] == true;
                    final existingNote = m['existingNote'] as String?;
                    // Soft count guidance: the app targets a focused 8-12
                    // skill list — flag (never silently truncate) when the
                    // suggestion runs well past that, so the user can prune
                    // during Apply All instead of the list silently
                    // exploding into the resume unseen.
                    final countNote = (field == 'skills' &&
                            value is List &&
                            value.length > _kSkillsTargetMax)
                        ? '${value.length} skills suggested — recommended '
                            'range is 8-12. Consider removing the less '
                            'relevant ones before applying.'
                        : null;

                    return _MappingRow(
                      fieldLabel: _fieldLabel(field),
                      valuePreview: _valuePreview(value),
                      confidence: confidence,
                      accepted: accepted,
                      isDark: isDark,
                      accent: accent,
                      sourceFile: sourceFile,
                      isConflict: isConflict,
                      hasPossibleDuplicates: hasDuplicates,
                      existingNote: existingNote,
                      countNote: countNote,
                      onToggle: (v) => onToggleMapping(
                          i - pendingDecisions.length, v),
                    );
                  },
                ),
        ),

        // Bottom actions
        Container(
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
                    color:
                        isDark ? AppColors.borderDark : AppColors.borderLight)),
          ),
          child: Column(
            children: [
              if (pendingDecisions.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Resolve ${pendingDecisions.length} pending '
                    'decision${pendingDecisions.length == 1 ? '' : 's'} above '
                    'before applying.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.warningDark
                          : AppColors.warningLight,
                    ),
                  ),
                ),
              ],
              Row(
                children: [
                  OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: acceptedCount > 0 && pendingDecisions.isEmpty
                          ? onApplyAll
                          : null,
                      child: Text(
                          'Apply $acceptedCount Field${acceptedCount == 1 ? '' : 's'}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MappingRow extends StatelessWidget {
  const _MappingRow({
    required this.fieldLabel,
    required this.valuePreview,
    required this.confidence,
    required this.accepted,
    required this.isDark,
    required this.accent,
    required this.onToggle,
    this.sourceFile,
    this.isConflict = false,
    this.hasPossibleDuplicates = false,
    this.existingNote,
    this.countNote,
  });

  final String fieldLabel;
  final String valuePreview;
  final int confidence;
  final bool accepted;
  final bool isDark;
  final Color accent;
  final ValueChanged<bool> onToggle;
  final String? sourceFile;
  final bool isConflict;
  final bool hasPossibleDuplicates;
  final String? existingNote;
  final String? countNote;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final warningColor =
        isDark ? AppColors.warningDark : AppColors.warningLight;

    return Semantics(
      label: isConflict
          ? '$fieldLabel: $valuePreview. ${accepted ? 'Selected' : 'Not selected'}. '
              'Conflict — tap to choose this value.'
          : '$fieldLabel: $valuePreview. ${accepted ? 'Selected' : 'Not selected'}. Tap to toggle.',
      child: GestureDetector(
        // Conflict rows act as radio buttons: tapping always "selects" this
        // option. Tapping the already-selected option is a no-op (enforced
        // in the parent's onToggleMapping via the conflictGroupId check).
        onTap: () => onToggle(isConflict ? true : !accepted),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: accepted ? accent.withValues(alpha: 0.06) : surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isConflict
                  ? (accepted
                      ? accent
                      : warningColor.withValues(alpha: 0.5))
                  : (accepted ? accent : border),
              width: accepted || isConflict ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Radio indicator for conflict groups; checkbox for independent fields.
              // Using a custom circle rather than Radio widget to avoid the
              // deprecated groupValue/onChanged API (deprecated in Flutter 3.32).
              SizedBox(
                width: 24,
                height: 24,
                child: isConflict
                    ? Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accepted ? accent : border,
                              width: 2,
                            ),
                          ),
                          child: accepted
                              ? Center(
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: accent,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      )
                    : Checkbox(
                        value: accepted,
                        activeColor: accent,
                        onChanged: (v) => onToggle(v ?? false),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
              ),
              const SizedBox(width: 10),

              // Field info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          fieldLabel,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Confidence badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _confidenceColor(confidence, isDark)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$confidence%',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: _confidenceColor(confidence, isDark),
                            ),
                          ),
                        ),
                        if (sourceFile != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                sourceFile!,
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      valuePreview,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isConflict) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Conflict with another file — choose one',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: warningColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (hasPossibleDuplicates) ...[
                      const SizedBox(height: 4),
                      Text(
                        'May contain duplicates from multiple files — review before applying',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: warningColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (existingNote != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        existingNote!,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (countNote != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        countNote!,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: warningColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // AI badge
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: (isDark
                          ? AppColors.aiIndicatorDark
                          : AppColors.aiIndicator)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'AI',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.aiIndicatorDark
                        : AppColors.aiIndicator,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _confidenceColor(int confidence, bool isDark) {
    if (confidence >= 85) {
      return isDark ? AppColors.successDark : AppColors.successLight;
    }
    if (confidence >= 70) {
      return isDark ? AppColors.warningDark : AppColors.warningLight;
    }
    return isDark ? AppColors.errorDark : AppColors.errorLight;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error View
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.isDark,
    required this.onRetry,
  });
  final String message;
  final bool isDark;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 24),
          Text(
            'Extraction failed',
            style: GoogleFonts.playfairDisplay(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.55,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}

class _ErrorChip extends StatelessWidget {
  const _ErrorChip({required this.message, required this.isDark});
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
        children: [
          Icon(Icons.error_outline, size: 16, color: errorColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
