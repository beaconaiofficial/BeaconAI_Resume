import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../constants/app_constants.dart';
import '../models/app_enums.dart';
import '../models/supporting_models.dart';
import '../providers/user_settings_provider.dart';
import '../services/hive_service.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UploadManagerScreen
//
// Spec §4 (Upload Manager):
//   - List of all uploaded source documents per resume.
//   - Filename, type, upload date, extraction status.
//   - Delete option.
//   - Upload count vs. tier limit displayed.
// ─────────────────────────────────────────────────────────────────────────────

class UploadManagerScreen extends ConsumerStatefulWidget {
  const UploadManagerScreen({super.key});

  @override
  ConsumerState<UploadManagerScreen> createState() =>
      _UploadManagerScreenState();
}

class _UploadManagerScreenState extends ConsumerState<UploadManagerScreen> {
  String? _resumeId;
  List<SourceDocument> _documents = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _resumeId = args['resumeId'] as String?;
    }
    _loadDocuments();
  }

  void _loadDocuments() {
    if (_resumeId == null) return;
    final box = HiveService.sourceDocumentBox;
    final docs = box.values.where((d) => d.resumeId == _resumeId).toList()
      ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    setState(() => _documents = docs);
  }

  Future<void> _onDelete(SourceDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove document?',
            style: GoogleFonts.playfairDisplay(
                fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text(
          'This removes "${doc.fileName}" from this resume\'s source documents. '
          'Content already applied to your resume will not be affected.',
          style: GoogleFonts.inter(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.errorLight),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await HiveService.sourceDocumentBox.delete(doc.id);

    // Decrement upload count on resume
    final resume = HiveService.resumeBox.get(_resumeId);
    if (resume != null && resume.uploadCount > 0) {
      resume.uploadCount--;
      await resume.save();
    }

    _loadDocuments();
  }

  void _onAddDocument() {
    Navigator.pushNamed(
      context,
      AppConstants.routeDocumentUpload,
      arguments: {'resumeId': _resumeId},
    ).then((_) => _loadDocuments());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(userSettingsProvider);
    final tier = settings.tier;
    final resume =
        _resumeId != null ? HiveService.resumeBox.get(_resumeId) : null;
    final uploadCount = resume?.uploadCount ?? _documents.length;
    final limit = tier.uploadLimit;
    final limitLabel = limit < 0 ? 'Unlimited' : '$limit';
    final isAtLimit = limit >= 0 && uploadCount >= limit;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Source Documents',
            style: GoogleFonts.playfairDisplay(
                fontSize: 20, fontWeight: FontWeight.w600)),
        actions: [
          Semantics(
            label: 'Upload a new document',
            child: IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Upload document',
              onPressed: isAtLimit ? null : _onAddDocument,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Upload count bar ───────────────────────────────────────────────
          _UploadCountBar(
            count: uploadCount,
            limit: limit,
            limitLabel: limitLabel,
            tier: tier,
            isAtLimit: isAtLimit,
            isDark: isDark,
            onUpgrade: () =>
                Navigator.pushNamed(context, AppConstants.routePaywall),
          ),

          // ── Document list ──────────────────────────────────────────────────
          Expanded(
            child: _documents.isEmpty
                ? _EmptyState(
                    isDark: isDark,
                    isAtLimit: isAtLimit,
                    onUpload: isAtLimit ? null : _onAddDocument,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: _documents.length,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _DocumentTile(
                        doc: _documents[i],
                        isDark: isDark,
                        onDelete: () => _onDelete(_documents[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: !isAtLimit
          ? FloatingActionButton(
              onPressed: _onAddDocument,
              tooltip: 'Upload document',
              child: const Icon(Icons.upload_file_outlined),
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Upload Count Bar
// ─────────────────────────────────────────────────────────────────────────────

class _UploadCountBar extends StatelessWidget {
  const _UploadCountBar({
    required this.count,
    required this.limit,
    required this.limitLabel,
    required this.tier,
    required this.isAtLimit,
    required this.isDark,
    required this.onUpgrade,
  });

  final int count;
  final int limit;
  final String limitLabel;
  final TierEnum tier;
  final bool isAtLimit;
  final bool isDark;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final barColor = isAtLimit
        ? (isDark ? AppColors.warningDark : AppColors.warningLight)
        : accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
            bottom: BorderSide(
                color: isDark ? AppColors.borderDark : AppColors.borderLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Documents uploaded',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Semantics(
                label: '$count of $limitLabel uploads used',
                child: Text(
                  limit < 0 ? '$count  ·  Unlimited' : '$count / $limit',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: barColor,
                  ),
                ),
              ),
            ],
          ),
          if (limit > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (count / limit).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ],
          if (isAtLimit) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 13,
                    color: isDark
                        ? AppColors.warningDark
                        : AppColors.warningLight),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Upload limit reached for ${tier.displayName} tier.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.warningDark
                          : AppColors.warningLight,
                    ),
                  ),
                ),
                if (!tier.isPro)
                  TextButton(
                    onPressed: onUpgrade,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child:
                        const Text('Upgrade', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Document Tile
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.doc,
    required this.isDark,
    required this.onDelete,
  });

  final SourceDocument doc;
  final bool isDark;
  final VoidCallback onDelete;

  IconData get _icon {
    return switch (doc.fileType) {
      FileTypeEnum.pdf => Icons.picture_as_pdf_outlined,
      FileTypeEnum.docx => Icons.description_outlined,
      FileTypeEnum.txt => Icons.text_snippet_outlined,
      FileTypeEnum.image => Icons.image_outlined,
    };
  }

  Color _statusColor(bool isDark) {
    return switch (doc.extractionStatus) {
      ExtractionStatusEnum.complete =>
        isDark ? AppColors.successDark : AppColors.successLight,
      ExtractionStatusEnum.failed =>
        isDark ? AppColors.errorDark : AppColors.errorLight,
      ExtractionStatusEnum.pending =>
        isDark ? AppColors.warningDark : AppColors.warningLight,
    };
  }

  String get _statusLabel {
    return switch (doc.extractionStatus) {
      ExtractionStatusEnum.complete => 'Extracted',
      ExtractionStatusEnum.failed => 'Failed',
      ExtractionStatusEnum.pending => 'Pending',
    };
  }

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final statusColor = _statusColor(isDark);

    return Semantics(
      label: '${doc.fileName}, ${doc.fileType.displayName}, uploaded '
          '${DateFormat('MMM d').format(doc.uploadedAt)}, '
          'status: $_statusLabel',
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_icon, size: 20, color: accent),
          ),
          title: Text(
            doc.fileName,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              Text(
                DateFormat('MMM d, yyyy').format(doc.uploadedAt),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _statusLabel,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Remove document',
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            onPressed: onDelete,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isDark,
    required this.isAtLimit,
    required this.onUpload,
  });

  final bool isDark;
  final bool isAtLimit;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.upload_file_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text(
              'No documents uploaded yet',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload a PDF, Word doc, or image of your existing resume '
              'and AI will extract your information automatically.',
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.55,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onUpload != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Upload Document'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
