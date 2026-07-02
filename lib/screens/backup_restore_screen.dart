import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/app_enums.dart';
import '../models/resume.dart';
import '../models/resume_sections.dart';
import '../models/supporting_models.dart';
import '../providers/resume_provider.dart';
import '../services/hive_service.dart';
import '../theme/app_colors.dart';

const _uuid = Uuid();
const _backupFormatVersion = 1;

// ─────────────────────────────────────────────────────────────────────────────
// BackupRestoreScreen
//
// Spec §4 (Backup & Restore):
//   - Backup Now: ZIP export to share sheet.
//   - Import Backup: file picker, validation, additive merge.
//
// Rule §2: never delete user data. Import is purely additive — existing
//          resumes/documents are never overwritten or removed, only new
//          records are added (with new IDs to avoid collisions).
// ─────────────────────────────────────────────────────────────────────────────

class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  bool _isWorking = false;
  String? _statusMessage;
  bool _statusIsError = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Backup
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onBackupNow() async {
    setState(() {
      _isWorking = true;
      _statusMessage = null;
    });

    try {
      final bytes = await _buildBackupZip();
      final fileName =
          'BeaconAI_Resume_Backup_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.zip';

      await Share.shareXFiles(
        [XFile.fromData(bytes, name: fileName, mimeType: 'application/zip')],
        subject: fileName,
      );

      setState(() {
        _isWorking = false;
        _statusMessage = 'Backup created successfully.';
        _statusIsError = false;
      });
    } catch (e) {
      setState(() {
        _isWorking = false;
        _statusMessage = 'Backup failed: ${e.toString()}';
        _statusIsError = true;
      });
    }
  }

  Future<Uint8List> _buildBackupZip() async {
    final archive = Archive();

    // ── Manifest ───────────────────────────────────────────────────────────
    final manifest = {
      'formatVersion': _backupFormatVersion,
      'appVersion': '1.0.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'resumeCount': HiveService.resumeBox.length,
      'sourceDocumentCount': HiveService.sourceDocumentBox.length,
      'coverLetterCount': HiveService.coverLetterBox.length,
    };
    _addJsonFile(archive, 'manifest.json', manifest);

    // ── Resumes ───────────────────────────────────────────────────────────
    final resumes = HiveService.resumeBox.values
        .map((r) => {
              'id': r.id,
              'title': r.title,
              'createdAt': r.createdAt.toIso8601String(),
              'updatedAt': r.updatedAt.toIso8601String(),
              'isMaster': r.isMaster,
              'templateId': r.templateId,
              'templateAccentColor': r.templateAccentColor,
              'uploadCount': r.uploadCount,
              'isArchived': r.isArchived,
              'linkedJobDescription': r.linkedJobDescription,
              'companyName': r.companyName,
              'roleTitle': r.roleTitle,
            })
        .toList();
    _addJsonFile(archive, 'resumes.json', resumes);

    // ── Resume sections ───────────────────────────────────────────────────
    final sections = HiveService.resumeSectionBox.values
        .map((s) => {
              'id': s.id,
              'resumeId': s.resumeId,
              'type': s.type.name,
              'data': s.data,
              'hasUnreviewedAIContent': s.hasUnreviewedAIContent,
            })
        .toList();
    _addJsonFile(archive, 'resume_sections.json', sections);

    // ── Source documents (text only — never raw file bytes, per Rule §12) ──
    final sourceDocs = HiveService.sourceDocumentBox.values
        .map((d) => {
              'id': d.id,
              'resumeId': d.resumeId,
              'fileName': d.fileName,
              'fileType': d.fileType.name,
              'documentRole': d.documentRole.name,
              'uploadedAt': d.uploadedAt.toIso8601String(),
              'extractionStatus': d.extractionStatus.name,
              'rawExtractedText': d.rawExtractedText,
              'appliedFields': d.appliedFields,
            })
        .toList();
    _addJsonFile(archive, 'source_documents.json', sourceDocs);

    // ── Cover letters ─────────────────────────────────────────────────────
    final coverLetters = HiveService.coverLetterBox.values
        .map((c) => {
              'id': c.id,
              'resumeId': c.resumeId,
              'jobDescription': c.jobDescription,
              'content': c.content,
              'createdAt': c.createdAt.toIso8601String(),
              'updatedAt': c.updatedAt.toIso8601String(),
            })
        .toList();
    _addJsonFile(archive, 'cover_letters.json', coverLetters);

    final zipBytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipBytes!);
  }

  void _addJsonFile(Archive archive, String path, dynamic data) {
    final jsonStr = jsonEncode(data);
    final bytes = utf8.encode(jsonStr);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Restore
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onImportBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    setState(() {
      _isWorking = true;
      _statusMessage = null;
    });

    try {
      final summary = await _restoreFromZip(bytes);
      setState(() {
        _isWorking = false;
        _statusMessage =
            'Restored ${summary.resumesAdded} resume${summary.resumesAdded == 1 ? '' : 's'}, '
            '${summary.documentsAdded} document${summary.documentsAdded == 1 ? '' : 's'}, '
            '${summary.coverLettersAdded} cover letter${summary.coverLettersAdded == 1 ? '' : 's'}.';
        _statusIsError = false;
      });
      ref.invalidate(resumeListProvider);
    } on _BackupValidationException catch (e) {
      setState(() {
        _isWorking = false;
        _statusMessage = e.message;
        _statusIsError = true;
      });
    } catch (e) {
      setState(() {
        _isWorking = false;
        _statusMessage = 'Restore failed. The backup file may be corrupted.';
        _statusIsError = true;
      });
    }
  }

  Future<_RestoreSummary> _restoreFromZip(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    // ── Validate manifest first ──────────────────────────────────────────
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw const _BackupValidationException(
          'This file is not a valid BeaconAI Resume backup.');
    }

    final manifest = jsonDecode(utf8.decode(manifestFile.content as List<int>))
        as Map<String, dynamic>;
    final formatVersion = manifest['formatVersion'] as int? ?? 0;
    if (formatVersion > _backupFormatVersion) {
      throw const _BackupValidationException(
          'This backup was created with a newer version of the app. '
          'Please update BeaconAI Resume before restoring.');
    }

    // ── Map old resume IDs → new resume IDs to avoid collisions ───────────
    final idMap = <String, String>{};
    int resumesAdded = 0;
    int documentsAdded = 0;
    int coverLettersAdded = 0;

    // ── Restore resumes ─────────────────────────────────────────────────
    final resumesFile = archive.findFile('resumes.json');
    if (resumesFile != null) {
      final resumesList =
          jsonDecode(utf8.decode(resumesFile.content as List<int>))
              as List<dynamic>;

      for (final r in resumesList) {
        final map = r as Map<String, dynamic>;
        final oldId = map['id'] as String;
        final newId = _uuid.v4();
        idMap[oldId] = newId;

        final resume = Resume(
          id: newId,
          title: '${map['title'] as String} (Restored)',
          createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
              DateTime.now(),
          updatedAt: DateTime.now(),
          // Restored resumes are never auto-set as master — avoids
          // silently replacing the user's current active master.
          isMaster: false,
          templateId: map['templateId'] as String? ?? 'clean',
          templateAccentColor: map['templateAccentColor'] as String?,
          uploadCount: map['uploadCount'] as int? ?? 0,
          isArchived:
              true, // restored into archive — user reviews and un-archives
          linkedJobDescription: map['linkedJobDescription'] as String?,
          companyName: map['companyName'] as String?,
          roleTitle: map['roleTitle'] as String?,
        );
        await HiveService.resumeBox.put(newId, resume);
        resumesAdded++;
      }
    }

    // ── Restore resume sections ─────────────────────────────────────────
    final sectionsFile = archive.findFile('resume_sections.json');
    if (sectionsFile != null) {
      final sectionsList =
          jsonDecode(utf8.decode(sectionsFile.content as List<int>))
              as List<dynamic>;

      for (final s in sectionsList) {
        final map = s as Map<String, dynamic>;
        final oldResumeId = map['resumeId'] as String;
        final newResumeId = idMap[oldResumeId];
        if (newResumeId == null) continue; // orphaned section, skip

        final typeStr = map['type'] as String;
        final type = SectionTypeEnum.values.firstWhere(
          (t) => t.name == typeStr,
          orElse: () => SectionTypeEnum.contact,
        );

        final key = '${newResumeId}_${type.name}';
        final section = ResumeSection(
          id: _uuid.v4(),
          resumeId: newResumeId,
          type: type,
          data: map['data'] as String? ?? '{}',
          hasUnreviewedAIContent:
              map['hasUnreviewedAIContent'] as bool? ?? false,
        );
        await HiveService.resumeSectionBox.put(key, section);
      }
    }

    // ── Restore source documents (text only) ────────────────────────────
    final docsFile = archive.findFile('source_documents.json');
    if (docsFile != null) {
      final docsList = jsonDecode(utf8.decode(docsFile.content as List<int>))
          as List<dynamic>;

      for (final d in docsList) {
        final map = d as Map<String, dynamic>;
        final oldResumeId = map['resumeId'] as String;
        final newResumeId = idMap[oldResumeId];
        if (newResumeId == null) continue;

        final newDocId = _uuid.v4();
        final doc = SourceDocument(
          id: newDocId,
          resumeId: newResumeId,
          fileName: map['fileName'] as String? ?? 'Restored Document',
          fileType: FileTypeEnum.values.firstWhere(
            (t) => t.name == (map['fileType'] as String? ?? ''),
            orElse: () => FileTypeEnum.txt,
          ),
          documentRole: DocumentRoleEnum.values.firstWhere(
            (t) => t.name == (map['documentRole'] as String? ?? ''),
            orElse: () => DocumentRoleEnum.sourceResume,
          ),
          uploadedAt: DateTime.tryParse(map['uploadedAt'] as String? ?? '') ??
              DateTime.now(),
          extractionStatus: ExtractionStatusEnum.values.firstWhere(
            (t) => t.name == (map['extractionStatus'] as String? ?? ''),
            orElse: () => ExtractionStatusEnum.complete,
          ),
          rawExtractedText: map['rawExtractedText'] as String? ?? '',
          appliedFields: (map['appliedFields'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [],
        );
        await HiveService.sourceDocumentBox.put(newDocId, doc);
        documentsAdded++;
      }
    }

    // ── Restore cover letters ───────────────────────────────────────────
    final coverLettersFile = archive.findFile('cover_letters.json');
    if (coverLettersFile != null) {
      final clList =
          jsonDecode(utf8.decode(coverLettersFile.content as List<int>))
              as List<dynamic>;

      for (final c in clList) {
        final map = c as Map<String, dynamic>;
        final oldResumeId = map['resumeId'] as String;
        final newResumeId = idMap[oldResumeId] ?? oldResumeId;

        final newClId = _uuid.v4();
        final cl = CoverLetter(
          id: newClId,
          resumeId: newResumeId,
          jobDescription: map['jobDescription'] as String? ?? '',
          content: map['content'] as String? ?? '',
          createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
              DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await HiveService.coverLetterBox.put(newClId, cl);
        coverLettersAdded++;
      }
    }

    return _RestoreSummary(
      resumesAdded: resumesAdded,
      documentsAdded: documentsAdded,
      coverLettersAdded: coverLettersAdded,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resumeCount = HiveService.resumeBox.length;
    final docCount = HiveService.sourceDocumentBox.length;
    final clCount = HiveService.coverLetterBox.length;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Backup & Restore',
            style: GoogleFonts.playfairDisplay(
                fontSize: 20, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Current data summary ─────────────────────────────────────────
          _DataSummaryCard(
            resumeCount: resumeCount,
            docCount: docCount,
            clCount: clCount,
            isDark: isDark,
          ),
          const SizedBox(height: 20),

          // ── Backup Now ───────────────────────────────────────────────────
          _ActionCard(
            icon: Icons.backup_outlined,
            title: 'Backup Now',
            description:
                'Create a backup file containing all your resumes, documents, and cover letters. '
                'Share it to cloud storage, email, or another device.',
            buttonLabel: 'Create Backup',
            isDark: isDark,
            isLoading: _isWorking,
            onTap: _onBackupNow,
          ),
          const SizedBox(height: 16),

          // ── Import Backup ────────────────────────────────────────────────
          _ActionCard(
            icon: Icons.restore_outlined,
            title: 'Import Backup',
            description:
                'Restore from a previous backup file. Imported documents are added '
                'alongside your existing data — nothing currently on this device is '
                'ever replaced or deleted.',
            buttonLabel: 'Choose Backup File',
            isDark: isDark,
            isLoading: _isWorking,
            onTap: _onImportBackup,
          ),

          if (_statusMessage != null) ...[
            const SizedBox(height: 16),
            _StatusBanner(
                message: _statusMessage!,
                isError: _statusIsError,
                isDark: isDark),
          ],

          const SizedBox(height: 24),
          _InfoNote(isDark: isDark),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DataSummaryCard extends StatelessWidget {
  const _DataSummaryCard({
    required this.resumeCount,
    required this.docCount,
    required this.clCount,
    required this.isDark,
  });

  final int resumeCount;
  final int docCount;
  final int clCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          _SummaryStat(count: resumeCount, label: 'Resumes', accent: accent),
          _VerticalDivider(border: border),
          _SummaryStat(count: docCount, label: 'Documents', accent: accent),
          _VerticalDivider(border: border),
          _SummaryStat(count: clCount, label: 'Cover Letters', accent: accent),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat(
      {required this.count, required this.label, required this.accent});
  final int count;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text('$count',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 22, fontWeight: FontWeight.w700, color: accent)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider({required this.border});
  final Color border;
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 36, color: border);
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.isDark,
    required this.isLoading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final bool isDark;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
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
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Text(title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          Text(description,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.55,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isLoading ? null : onTap,
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
    required this.isError,
    required this.isDark,
  });
  final String message;
  final bool isError;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? (isDark ? AppColors.errorDark : AppColors.errorLight)
        : (isDark ? AppColors.successDark : AppColors.successLight);

    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.5,
                      color: Theme.of(context).colorScheme.onSurface)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Icon(Icons.info_outline,
              size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Restored resumes are added to your Archive in My Documents so you can '
              'review them before making any active. Your existing data is never modified.',
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
// Helper types
// ─────────────────────────────────────────────────────────────────────────────

class _RestoreSummary {
  const _RestoreSummary({
    required this.resumesAdded,
    required this.documentsAdded,
    required this.coverLettersAdded,
  });
  final int resumesAdded;
  final int documentsAdded;
  final int coverLettersAdded;
}

class _BackupValidationException implements Exception {
  const _BackupValidationException(this.message);
  final String message;
}
