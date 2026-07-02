import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../constants/app_constants.dart';
import '../models/resume.dart';
import '../providers/resume_provider.dart';
import '../services/pdf_export_service.dart';
import '../widgets/resume_template_renderer.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MyDocumentsScreen
//
// Spec §4 (My Documents):
//  - Full archive of all locally saved resumes, cover letters, study guides.
//  - Nothing is ever deleted by the app (Rule §2).
//  - Search bar at top.
//  - Filter: document type, date range, company name.
//  - Sort: newest, oldest, company A–Z.
//  - Tap to open in view/edit mode.
//  - Long-press for rename, export, print, delete options.
//  - 'Backup' button in top bar → Backup & Restore screen.
// ─────────────────────────────────────────────────────────────────────────────

class MyDocumentsScreen extends ConsumerStatefulWidget {
  const MyDocumentsScreen({super.key});

  @override
  ConsumerState<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends ConsumerState<MyDocumentsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  DocFilterType _filterType = DocFilterType.all;
  DocSortOrder _sortOrder = DocSortOrder.newest;
  bool _showArchived = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Filtering & sorting ────────────────────────────────────────────────────

  List<Resume> _applyFilters(List<Resume> all) {
    var results = all.where((r) {
      // Archived filter
      if (!_showArchived && r.isArchived) return false;

      // Type filter
      if (_filterType == DocFilterType.masterResume && !r.isMaster) {
        return false;
      }
      if (_filterType == DocFilterType.tailoredResume &&
          (r.isMaster || r.isArchived)) {
        return false;
      }

      // Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final titleMatch = r.displayTitle.toLowerCase().contains(q);
        final companyMatch = r.companyName?.toLowerCase().contains(q) ?? false;
        final roleMatch = r.roleTitle?.toLowerCase().contains(q) ?? false;
        if (!titleMatch && !companyMatch && !roleMatch) return false;
      }

      return true;
    }).toList();

    // Sort
    switch (_sortOrder) {
      case DocSortOrder.newest:
        results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case DocSortOrder.oldest:
        results.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case DocSortOrder.companyAZ:
        results.sort((a, b) =>
            (a.companyName ?? a.title).compareTo(b.companyName ?? b.title));
    }

    return results;
  }

  // ── Long-press actions ─────────────────────────────────────────────────────

  void _onLongPress(BuildContext context, Resume resume) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DocumentActionsSheet(
        resume: resume,
        onRename: () => _onRename(resume),
        onExport: () => Navigator.pushNamed(
          context,
          AppConstants.routeExport,
          arguments: {'resumeId': resume.id},
        ),
        onPrint: () async {
          try {
            final data = ResumeRenderData.fromHive(resume.id);
            final bytes = await PdfExportService.generateResumePdf(
              resume: resume,
              data: data,
            );
            await Printing.layoutPdf(
              onLayout: (_) async => bytes,
              name: resume.displayTitle,
            );
          } catch (_) {
            // Bottom sheet has already dismissed — no mounted check available here
          }
        },
        onDelete: () => _onDelete(resume),
      ),
    );
  }

  Future<void> _onRename(Resume resume) async {
    final controller = TextEditingController(text: resume.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename',
            style: GoogleFonts.playfairDisplay(
                fontSize: 18, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter new name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await ref
          .read(resumeListProvider.notifier)
          .renameResume(resume.id, result);
    }
    controller.dispose();
  }

  Future<void> _onDelete(Resume resume) async {
    // Rule §2: "delete" = archive. Confirmed via dialog.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove document?',
            style: GoogleFonts.playfairDisplay(
                fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text(
          'This document will be moved to your archive. '
          'It will never be permanently deleted.',
          style: GoogleFonts.inter(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorLight,
            ),
            child: const Text('Move to Archive'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(resumeListProvider.notifier).archiveResume(resume.id);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(resumeListProvider);
    final filtered = _applyFilters(all);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('My Documents',
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
          // Backup button
          Semantics(
            label: 'Backup and restore',
            child: IconButton(
              icon: const Icon(Icons.backup_outlined),
              tooltip: 'Backup & Restore',
              onPressed: () =>
                  Navigator.pushNamed(context, AppConstants.routeBackupRestore),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Semantics(
              label: 'Search documents',
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search by name, company, or role…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          tooltip: 'Clear search',
                        )
                      : null,
                ),
              ),
            ),
          ),

          // ── Filter / sort bar ────────────────────────────────────────────
          _FilterSortBar(
            filterType: _filterType,
            sortOrder: _sortOrder,
            showArchived: _showArchived,
            onFilterChanged: (f) => setState(() => _filterType = f),
            onSortChanged: (s) => setState(() => _sortOrder = s),
            onToggleArchived: () =>
                setState(() => _showArchived = !_showArchived),
          ),

          // ── Document count ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  '${filtered.length} document${filtered.length == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // ── Document list ────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(
                    hasSearch: _searchQuery.isNotEmpty,
                    isDark: isDark,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final resume = filtered[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _DocumentRow(
                          resume: resume,
                          isDark: isDark,
                          onTap: () => Navigator.pushNamed(
                            ctx,
                            AppConstants.routePreviewEdit,
                            arguments: {'resumeId': resume.id},
                          ),
                          onLongPress: () => _onLongPress(ctx, resume),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter / Sort Bar
// ─────────────────────────────────────────────────────────────────────────────

class _FilterSortBar extends StatelessWidget {
  const _FilterSortBar({
    required this.filterType,
    required this.sortOrder,
    required this.showArchived,
    required this.onFilterChanged,
    required this.onSortChanged,
    required this.onToggleArchived,
  });

  final DocFilterType filterType;
  final DocSortOrder sortOrder;
  final bool showArchived;
  final ValueChanged<DocFilterType> onFilterChanged;
  final ValueChanged<DocSortOrder> onSortChanged;
  final VoidCallback onToggleArchived;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          // Filter dropdown
          _FilterChip(
            icon: Icons.filter_list,
            label: filterType.label,
            isDark: isDark,
            accent: accent,
            isActive: filterType != DocFilterType.all,
            onTap: () => _showFilterSheet(context),
          ),
          const SizedBox(width: 8),

          // Sort dropdown
          _FilterChip(
            icon: Icons.sort,
            label: sortOrder.label,
            isDark: isDark,
            accent: accent,
            isActive: sortOrder != DocSortOrder.newest,
            onTap: () => _showSortSheet(context),
          ),
          const SizedBox(width: 8),

          // Archived toggle
          _FilterChip(
            icon: showArchived ? Icons.archive : Icons.archive_outlined,
            label: 'Archived',
            isDark: isDark,
            accent: accent,
            isActive: showArchived,
            onTap: onToggleArchived,
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _OptionSheet(
        title: 'Filter by type',
        options: DocFilterType.values
            .map((f) => _SheetOption(
                  label: f.label,
                  isSelected: f == filterType,
                  onTap: () {
                    onFilterChanged(f);
                    Navigator.pop(context);
                  },
                ))
            .toList(),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _OptionSheet(
        title: 'Sort by',
        options: DocSortOrder.values
            .map((s) => _SheetOption(
                  label: s.label,
                  isSelected: s == sortOrder,
                  onTap: () {
                    onSortChanged(s);
                    Navigator.pop(context);
                  },
                ))
            .toList(),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.accent,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final Color accent;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? accent.withValues(alpha: 0.1)
              : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? accent
                : (isDark ? AppColors.borderDark : AppColors.borderLight),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: isActive
                    ? accent
                    : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? accent
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Document Row
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.resume,
    required this.isDark,
    required this.onTap,
    required this.onLongPress,
  });

  final Resume resume;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  String _formatDate(DateTime dt) => DateFormat('MMM d, yyyy').format(dt);

  IconData get _icon {
    if (resume.isMaster) return Icons.description_outlined;
    return Icons.tune_outlined;
  }

  String get _typeLabel {
    if (resume.isMaster) return 'Master';
    if (resume.isArchived) return 'Archived';
    return 'Tailored';
  }

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Semantics(
      label:
          '${resume.displayTitle}, $_typeLabel, last edited ${_formatDate(resume.updatedAt)}. Long press for more options.',
      button: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: resume.isArchived
                ? (isDark
                    ? AppColors.backgroundDark
                    : AppColors.backgroundLight)
                : surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: resume.isArchived
                      ? border.withValues(alpha: 0.5)
                      : accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  _icon,
                  size: 18,
                  color: resume.isArchived
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : accent,
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resume.displayTitle,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: resume.isArchived
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _TypeBadge(
                            label: _typeLabel,
                            isArchived: resume.isArchived,
                            isDark: isDark,
                            accent: accent),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(resume.updatedAt),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Chevron
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({
    required this.label,
    required this.isArchived,
    required this.isDark,
    required this.accent,
  });

  final String label;
  final bool isArchived;
  final bool isDark;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isArchived
            ? (isDark ? AppColors.borderDark : AppColors.borderLight)
                .withValues(alpha: 0.5)
            : accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: isArchived
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : accent,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Document Actions Sheet (long-press)
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentActionsSheet extends StatelessWidget {
  const _DocumentActionsSheet({
    required this.resume,
    required this.onRename,
    required this.onExport,
    required this.onPrint,
    required this.onDelete,
  });

  final Resume resume;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onPrint;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Document name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              resume.displayTitle,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),

          _ActionTile(
            icon: Icons.drive_file_rename_outline,
            label: 'Rename',
            onTap: () {
              Navigator.pop(context);
              onRename();
            },
          ),
          _ActionTile(
            icon: Icons.ios_share_outlined,
            label: 'Export',
            onTap: () {
              Navigator.pop(context);
              onExport();
            },
          ),
          _ActionTile(
            icon: Icons.print_outlined,
            label: 'Print',
            onTap: () {
              Navigator.pop(context);
              onPrint();
            },
          ),
          _ActionTile(
            icon: Icons.archive_outlined,
            label: resume.isArchived ? 'Already archived' : 'Move to Archive',
            isDestructive: !resume.isArchived,
            enabled: !resume.isArchived,
            onTap: resume.isArchived
                ? null
                : () {
                    Navigator.pop(context);
                    onDelete();
                  },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.isDestructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : isDestructive
            ? AppColors.errorLight
            : Theme.of(context).colorScheme.onSurface;

    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(label,
          style: GoogleFonts.inter(
              fontSize: 14, fontWeight: FontWeight.w500, color: color)),
      enabled: enabled,
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable bottom sheet for filter/sort options
// ─────────────────────────────────────────────────────────────────────────────

class _OptionSheet extends StatelessWidget {
  const _OptionSheet({required this.title, required this.options});
  final String title;
  final List<_SheetOption> options;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              title,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          ...options,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ListTile(
      title: Text(label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color:
                isSelected ? accent : Theme.of(context).colorScheme.onSurface,
          )),
      trailing: isSelected ? Icon(Icons.check, color: accent, size: 18) : null,
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearch, required this.isDark});
  final bool hasSearch;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasSearch ? Icons.search_off : Icons.folder_open_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'No documents match your search' : 'No documents yet',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'Try a different search term or clear the filter.'
                : 'Documents you create will appear here.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
