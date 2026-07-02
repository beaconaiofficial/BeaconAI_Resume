import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';
import 'dart:convert';

import '../constants/app_constants.dart';
import '../utils/web_download.dart';
import '../models/app_enums.dart';
import '../providers/user_settings_provider.dart';
import '../services/hive_service.dart';
import '../services/pdf_export_service.dart';
import '../services/docx_export_service.dart';
import '../theme/app_colors.dart';
import '../widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExportScreen
//
// Spec §4 (Export / Share / Print):
//  - Format picker based on tier (PDF / DOCX / TXT).
//  - Final preview before export.
//  - Share sheet for file export.
//  - Print option sends to any printer via native print dialog
//    (iOS AirPrint / Android Print Service).
//  - Works offline for previously generated content.
// ─────────────────────────────────────────────────────────────────────────────

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  String? _resumeId;
  ResumeRenderData? _renderData;
  ExportFormatEnum _selectedFormat = ExportFormatEnum.pdf;
  bool _isExporting = false;
  bool _isLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _resumeId = args['resumeId'] as String?;
    }
    if (_resumeId != null && _isLoading) {
      _load();
    }
  }

  Future<void> _load() async {
    final data =
        _resumeId != null ? ResumeRenderData.fromHive(_resumeId!) : null;
    if (mounted) {
      setState(() {
        _renderData = data;
        _isLoading = false;
      });
    }
  }

  // ── Export actions ─────────────────────────────────────────────────────────

  Future<void> _onExport() async {
    if (_resumeId == null || _renderData == null) return;
    final resume = HiveService.resumeBox.get(_resumeId);
    if (resume == null) return;

    setState(() => _isExporting = true);

    try {
      switch (_selectedFormat) {
        case ExportFormatEnum.pdf:
          final bytes = await PdfExportService.generateResumePdf(
            resume: resume,
            data: _renderData!,
          );
          final fileName =
              '${resume.displayTitle.replaceAll(' ', '_')}_Resume.pdf';
          if (kIsWeb) {
            downloadPdfInBrowser(bytes, fileName);
          } else {
            await Printing.sharePdf(bytes: bytes, filename: fileName);
          }

        case ExportFormatEnum.docx:
          final bytes = await DocxExportService.generateResumeDocx(
            resume: resume,
            data: _renderData!,
          );
          final fileName =
              '${resume.displayTitle.replaceAll(' ', '_')}_Resume.docx';
          await Share.shareXFiles(
            [
              XFile.fromData(bytes,
                  name: fileName,
                  mimeType:
                      'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
            ],
            subject: fileName,
          );

        case ExportFormatEnum.plainText:
          final text = _generatePlainText(_renderData!);
          final bytes = Uint8List.fromList(utf8.encode(text));
          final fileName =
              '${resume.displayTitle.replaceAll(' ', '_')}_Resume.txt';
          await Share.shareXFiles(
            [XFile.fromData(bytes, name: fileName, mimeType: 'text/plain')],
            subject: fileName,
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            backgroundColor: AppColors.errorLight,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ── Plain text generator ───────────────────────────────────────────────────
  // Spec: maximum ATS compatibility — no formatting, no tables, no bullets.
  String _generatePlainText(ResumeRenderData data) {
    final buffer = StringBuffer();

    if (data.contact.fullName.isNotEmpty) {
      buffer.writeln(data.contact.fullName);
    }
    if (data.contact.professionalTitle.isNotEmpty) {
      buffer.writeln(data.contact.professionalTitle);
    }
    final contactLine = [
      data.contact.cityState,
      data.contact.phone,
      data.contact.email,
      data.contact.linkedInUrl,
    ].where((s) => s != null && s.isNotEmpty).join(' | ');
    if (contactLine.isNotEmpty) buffer.writeln(contactLine);
    buffer.writeln();

    if (data.summary.isNotEmpty) {
      buffer.writeln('SUMMARY');
      buffer.writeln(data.summary);
      buffer.writeln();
    }

    final exp = data.experience.where((e) => e.title.isNotEmpty).toList();
    if (exp.isNotEmpty) {
      buffer.writeln('EXPERIENCE');
      for (final e in exp) {
        final titleLine = [e.title, e.company, e.location]
            .where((s) => s.isNotEmpty)
            .join(' | ');
        buffer.writeln('$titleLine - ${e.dateRange}');
        for (final b in e.bullets.where((b) => b.isNotEmpty)) {
          buffer.writeln('- $b');
        }
        buffer.writeln();
      }
    }

    final edu = data.education.where((e) => e.institution.isNotEmpty).toList();
    if (edu.isNotEmpty) {
      buffer.writeln('EDUCATION');
      for (final e in edu) {
        buffer.writeln('${e.institution} - ${e.graduationYear}');
        final degreeLine =
            [e.degree, e.fieldOfStudy].where((s) => s.isNotEmpty).join(', ');
        if (degreeLine.isNotEmpty) buffer.writeln(degreeLine);
        if (e.gpa != null && e.gpa!.isNotEmpty) buffer.writeln('GPA: ${e.gpa}');
        buffer.writeln();
      }
    }

    if (data.skills.isNotEmpty) {
      buffer.writeln('SKILLS');
      buffer.writeln(data.skills.map((s) => s.name).join(', '));
      buffer.writeln();
    }

    final certs = data.certifications.where((c) => c.name.isNotEmpty).toList();
    if (certs.isNotEmpty) {
      buffer.writeln('CERTIFICATIONS');
      for (final c in certs) {
        buffer.writeln('${c.name} - ${c.issuer} - ${c.dateEarned}');
      }
    }

    return buffer.toString();
  }

  Future<void> _onPrint() async {
    if (_resumeId == null || _renderData == null) return;
    final resume = HiveService.resumeBox.get(_resumeId);
    if (resume == null) return;

    setState(() => _isExporting = true);

    try {
      final bytes = await PdfExportService.generateResumePdf(
        resume: resume,
        data: _renderData!,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: resume.displayTitle,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: ${e.toString()}'),
            backgroundColor: AppColors.errorLight,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tier = ref.watch(currentTierProvider);
    final resume =
        _resumeId != null ? HiveService.resumeBox.get(_resumeId) : null;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Export',
            style: GoogleFonts.playfairDisplay(
                fontSize: 20, fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Resume name
                      if (resume != null) ...[
                        Text(
                          resume.displayTitle,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          resume.isMaster ? 'Master Resume' : 'Tailored Resume',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Format picker ──────────────────────────────────────
                      Text(
                        'Export format',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),

                      _FormatOption(
                        format: ExportFormatEnum.pdf,
                        selected: _selectedFormat == ExportFormatEnum.pdf,
                        isLocked: false,
                        isDark: isDark,
                        onTap: () => setState(
                            () => _selectedFormat = ExportFormatEnum.pdf),
                      ),
                      const SizedBox(height: 8),
                      _FormatOption(
                        format: ExportFormatEnum.docx,
                        selected: _selectedFormat == ExportFormatEnum.docx,
                        isLocked: !tier.isBasic && !tier.isPro,
                        isDark: isDark,
                        onTap: tier.isBasic || tier.isPro
                            ? () => setState(
                                () => _selectedFormat = ExportFormatEnum.docx)
                            : () => Navigator.pushNamed(
                                context, AppConstants.routePaywall),
                      ),
                      const SizedBox(height: 8),
                      _FormatOption(
                        format: ExportFormatEnum.plainText,
                        selected: _selectedFormat == ExportFormatEnum.plainText,
                        isLocked: !tier.isPro,
                        isDark: isDark,
                        onTap: tier.isPro
                            ? () => setState(() =>
                                _selectedFormat = ExportFormatEnum.plainText)
                            : () => Navigator.pushNamed(
                                context, AppConstants.routePaywall),
                      ),

                      const SizedBox(height: 24),

                      // ── ATS note ───────────────────────────────────────────
                      _AtsExportNote(isDark: isDark),
                    ],
                  ),
                ),

                // ── Bottom actions ───────────────────────────────────────────
                _ExportActionBar(
                  isDark: isDark,
                  isExporting: _isExporting,
                  onExport: _onExport,
                  onPrint: _onPrint,
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Format Option Card
// ─────────────────────────────────────────────────────────────────────────────

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.format,
    required this.selected,
    required this.isLocked,
    required this.isDark,
    required this.onTap,
  });

  final ExportFormatEnum format;
  final bool selected;
  final bool isLocked;
  final bool isDark;
  final VoidCallback onTap;

  String get _description {
    return switch (format) {
      ExportFormatEnum.pdf =>
        'Best for emailing directly to employers. ATS-safe single-column layout.',
      ExportFormatEnum.docx =>
        'Editable Word file — recruiters often prefer this format. Basic+',
      ExportFormatEnum.plainText =>
        'Maximum ATS compatibility. Plain text with no formatting. Pro only.',
    };
  }

  IconData get _icon {
    return switch (format) {
      ExportFormatEnum.pdf => Icons.picture_as_pdf_outlined,
      ExportFormatEnum.docx => Icons.description_outlined,
      ExportFormatEnum.plainText => Icons.text_snippet_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Semantics(
      label:
          '${format.displayName}${isLocked ? ', requires upgrade' : ''}${selected ? ', selected' : ''}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.08) : surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _icon,
                size: 22,
                color: isLocked
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : selected
                        ? accent
                        : Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      format.displayName,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isLocked
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _description,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isLocked)
                Icon(Icons.lock_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)
              else if (selected)
                Icon(Icons.check_circle, size: 20, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ATS Export Note
// ─────────────────────────────────────────────────────────────────────────────

class _AtsExportNote extends StatelessWidget {
  const _AtsExportNote({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final success = isDark ? AppColors.successDark : AppColors.successLight;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: success.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, size: 16, color: success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'All exports are ATS-safe. PDF is generated from single-column '
              'content regardless of the template you selected for display.',
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Export Action Bar
// ─────────────────────────────────────────────────────────────────────────────

class _ExportActionBar extends StatelessWidget {
  const _ExportActionBar({
    required this.isDark,
    required this.isExporting,
    required this.onExport,
    required this.onPrint,
  });

  final bool isDark;
  final bool isExporting;
  final VoidCallback onExport;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          // Print button
          OutlinedButton.icon(
            onPressed: isExporting ? null : onPrint,
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Print'),
          ),
          const SizedBox(width: 12),

          // Export / Share button
          Expanded(
            child: ElevatedButton.icon(
              onPressed: isExporting ? null : onExport,
              icon: isExporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.ios_share_outlined, size: 18),
              label: Text(isExporting ? 'Preparing…' : 'Export & Share'),
            ),
          ),
        ],
      ),
    );
  }
}
