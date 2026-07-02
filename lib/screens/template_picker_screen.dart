import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';
import '../models/resume.dart';
import '../services/hive_service.dart';
import '../theme/app_colors.dart';
import '../widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TemplatePickerScreen
//
// Spec §4 (Template Picker):
//   - Accessible from Resume Editor and Preview & Edit.
//   - Thumbnail grid of all 12 templates.
//   - Each thumbnail shows a miniature preview populated with user's own data
//     (or sample data if no content yet).
//   - Tap any thumbnail to see full-screen preview.
//   - Tap 'Use This Template' to apply.
//   - Switching is instant and non-destructive.
//   - Current template highlighted with a checkmark.
//   - Accent color picker shown inline for Horizon template (6 color options).
//   - Phase 2/3 templates shown as coming-soon (greyed out, not locked).
// ─────────────────────────────────────────────────────────────────────────────

class TemplatePickerScreen extends StatefulWidget {
  const TemplatePickerScreen({super.key});

  @override
  State<TemplatePickerScreen> createState() => _TemplatePickerScreenState();
}

class _TemplatePickerScreenState extends State<TemplatePickerScreen> {
  String? _resumeId;
  Resume? _resume;
  ResumeRenderData? _renderData;

  late String _selectedTemplateId;
  String? _selectedAccentColor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _resumeId = args['resumeId'] as String?;
    }
    _load();
  }

  void _load() {
    if (_resumeId == null) {
      _selectedTemplateId = AppConstants.defaultTemplateId;
      return;
    }
    final resume = HiveService.resumeBox.get(_resumeId);
    final data = ResumeRenderData.fromHive(_resumeId!);
    setState(() {
      _resume = resume;
      _renderData = data;
      _selectedTemplateId =
          resume?.templateId ?? AppConstants.defaultTemplateId;
      _selectedAccentColor = resume?.templateAccentColor;
    });
  }

  Future<void> _applyTemplate() async {
    if (_resumeId == null) {
      // Called from First Resume Setup — return selection via Navigator.pop
      Navigator.pop(context, {
        'templateId': _selectedTemplateId,
        'accentColor': _selectedAccentColor,
      });
      return;
    }

    final resume = HiveService.resumeBox.get(_resumeId);
    if (resume != null) {
      resume.templateId = _selectedTemplateId;
      resume.templateAccentColor = _selectedAccentColor;
      resume.updatedAt = DateTime.now();
      await resume.save();
    }
    if (mounted) Navigator.pop(context);
  }

  void _onTemplateTap(String templateId, bool isAvailable) {
    if (!isAvailable) return;
    setState(() {
      _selectedTemplateId = templateId;
      // Reset accent color when switching away from Horizon
      if (templateId != AppConstants.templateHorizon) {
        _selectedAccentColor = null;
      }
    });
  }

  void _onFullPreview(String templateId) {
    if (_renderData == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _FullPreviewSheet(
        templateId: templateId,
        resume: _resume ??
            Resume(
              id: 'preview',
              title: 'Preview',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              isMaster: true,
              templateId: templateId,
            ),
        renderData: _renderData!,
        isSelected: _selectedTemplateId == templateId,
        onSelect: () {
          Navigator.pop(context);
          _onTemplateTap(templateId, true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Templates',
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.playfairDisplay(
                fontSize: 20, fontWeight: FontWeight.w600)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              onPressed: _applyTemplate,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('Use Template'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Horizon accent color picker (shown when Horizon is selected) ──
          if (_selectedTemplateId == AppConstants.templateHorizon)
            _HorizonAccentPicker(
              selectedColor: _selectedAccentColor,
              isDark: isDark,
              onColorSelected: (color) =>
                  setState(() => _selectedAccentColor = color),
            ),

          // ── Template grid ─────────────────────────────────────────────────
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: kResumePageWidth / kResumePageHeight,
              ),
              itemCount: _allTemplates.length,
              itemBuilder: (ctx, i) {
                final t = _allTemplates[i];
                final isSelected = _selectedTemplateId == t.id;
                final isAvailable = t.phase == 1;

                return _TemplateTile(
                  info: t,
                  isSelected: isSelected,
                  isAvailable: isAvailable,
                  isDark: isDark,
                  resume: isAvailable && _resume != null
                      ? Resume(
                          id: _resume!.id,
                          title: _resume!.title,
                          createdAt: _resume!.createdAt,
                          updatedAt: _resume!.updatedAt,
                          isMaster: _resume!.isMaster,
                          templateId: t.id,
                        )
                      : null,
                  renderData: _renderData,
                  onTap: () => _onTemplateTap(t.id, isAvailable),
                  onLongPress: isAvailable ? () => _onFullPreview(t.id) : null,
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
// Template info data
// ─────────────────────────────────────────────────────────────────────────────

class _TemplateInfo {
  const _TemplateInfo({
    required this.id,
    required this.name,
    required this.phase,
    required this.bestFor,
  });

  final String id;
  final String name;
  final int phase;
  final String bestFor;
}

const List<_TemplateInfo> _allTemplates = [
  _TemplateInfo(
      id: AppConstants.templateClean,
      name: 'Clean',
      phase: 1,
      bestFor: 'Any industry'),
  _TemplateInfo(
      id: AppConstants.templateClassic,
      name: 'Classic',
      phase: 1,
      bestFor: 'Law · Finance · Government'),
  _TemplateInfo(
      id: AppConstants.templateSharp,
      name: 'Sharp',
      phase: 1,
      bestFor: 'Corporate · Banking'),
  _TemplateInfo(
      id: AppConstants.templateEntry,
      name: 'Entry',
      phase: 1,
      bestFor: 'Graduates · Interns'),
  _TemplateInfo(
      id: AppConstants.templateElevated,
      name: 'Elevated',
      phase: 1,
      bestFor: 'Marketing · HR'),
  _TemplateInfo(
      id: AppConstants.templateFederal,
      name: 'Federal',
      phase: 1,
      bestFor: 'Government · Defense'),
  _TemplateInfo(
      id: AppConstants.templateAcademic,
      name: 'Academic',
      phase: 1,
      bestFor: 'Teachers · Researchers'),
  _TemplateInfo(
      id: AppConstants.templateVeteran,
      name: 'Veteran',
      phase: 1,
      bestFor: 'Military to Civilian'),
  _TemplateInfo(
      id: AppConstants.templateTechnical,
      name: 'Technical',
      phase: 1,
      bestFor: 'Software · IT · Engineering'),
  _TemplateInfo(
      id: AppConstants.templateHorizon,
      name: 'Horizon',
      phase: 1,
      bestFor: 'Business · Sales'),
  _TemplateInfo(
      id: AppConstants.templateSidebar,
      name: 'Sidebar',
      phase: 1,
      bestFor: 'IT · Marketing'),
  _TemplateInfo(
      id: AppConstants.templatePillar,
      name: 'Pillar',
      phase: 1,
      bestFor: 'Creative · PR · Media'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Template Tile
// ─────────────────────────────────────────────────────────────────────────────

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.info,
    required this.isSelected,
    required this.isAvailable,
    required this.isDark,
    required this.resume,
    required this.renderData,
    required this.onTap,
    this.onLongPress,
  });

  final _TemplateInfo info;
  final bool isSelected;
  final bool isAvailable;
  final bool isDark;
  final Resume? resume;
  final ResumeRenderData? renderData;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Semantics(
      label: '${info.name} template${isSelected ? ', currently selected' : ''}'
          '${!isAvailable ? ', coming soon' : ''}. ${info.bestFor}.'
          '${isAvailable ? ' Long press for full preview.' : ''}',
      button: isAvailable,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? accent : border,
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Template preview (fills entire card) ─────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: isAvailable && resume != null && renderData != null
                    ? _ScaledTemplatePreview(
                        resume: resume!,
                        renderData: renderData!,
                      )
                    : _PlaceholderPreview(
                        name: info.name,
                        isDark: isDark,
                        isAvailable: isAvailable,
                      ),
              ),

              // ── Name bar (bottom overlay) ─────────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  decoration: BoxDecoration(
                    color: surface.withValues(alpha: 0.93),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(11)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.name,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isAvailable
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        isAvailable ? info.bestFor : 'Phase ${info.phase}',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Selected checkmark ────────────────────────────────────────
              if (isSelected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                    child:
                        const Icon(Icons.check, size: 14, color: Colors.white),
                  ),
                ),

              // ── Coming soon overlay ───────────────────────────────────────
              if (!isAvailable)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: (isDark
                              ? AppColors.backgroundDark
                              : AppColors.backgroundLight)
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      child: Text(
                        'Coming Soon',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scaled Template Preview
// Renders the real template at tiny scale inside the thumbnail.
// ─────────────────────────────────────────────────────────────────────────────

class _ScaledTemplatePreview extends StatelessWidget {
  const _ScaledTemplatePreview({
    required this.resume,
    required this.renderData,
  });

  final Resume resume;
  final ResumeRenderData renderData;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: kResumePageWidth,
        height: kResumePageHeight,
        child: ResumeTemplateRenderer(
          resume: resume,
          data: renderData,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder Preview (for unavailable templates)
// ─────────────────────────────────────────────────────────────────────────────

class _PlaceholderPreview extends StatelessWidget {
  const _PlaceholderPreview({
    required this.name,
    required this.isDark,
    required this.isAvailable,
  });

  final String name;
  final bool isDark;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final lineColor = isDark ? AppColors.borderDark : AppColors.borderLight;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

    return Container(
      color: bg,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Simulated resume lines
          Container(
              height: 8,
              width: 80,
              color: lineColor,
              margin: const EdgeInsets.only(bottom: 5)),
          Container(
              height: 4,
              width: 50,
              color: lineColor,
              margin: const EdgeInsets.only(bottom: 12)),
          Container(
              height: 3,
              width: double.infinity,
              color: lineColor,
              margin: const EdgeInsets.only(bottom: 8)),
          Container(
              height: 3,
              width: double.infinity,
              color: lineColor,
              margin: const EdgeInsets.only(bottom: 4)),
          Container(
              height: 3,
              width: 100,
              color: lineColor,
              margin: const EdgeInsets.only(bottom: 12)),
          Container(
              height: 3,
              width: double.infinity,
              color: lineColor,
              margin: const EdgeInsets.only(bottom: 4)),
          Container(height: 3, width: 120, color: lineColor),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Horizon Accent Color Picker
// ─────────────────────────────────────────────────────────────────────────────

class _HorizonAccentPicker extends StatelessWidget {
  const _HorizonAccentPicker({
    required this.selectedColor,
    required this.isDark,
    required this.onColorSelected,
  });

  final String? selectedColor;
  final bool isDark;
  final ValueChanged<String> onColorSelected;

  static const _colorNames = {
    '#1A237E': 'Navy',
    '#212121': 'Charcoal',
    '#1B5E20': 'Forest',
    '#455A64': 'Slate',
    '#4A0000': 'Burgundy',
    '#000000': 'Black',
  };

  Color _parse(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Horizon accent color',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: AppConstants.horizonAccentColors.map((hex) {
              final isSelected =
                  (selectedColor ?? AppConstants.horizonAccentColors.first) ==
                      hex;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Semantics(
                  label:
                      '${_colorNames[hex]} accent color${isSelected ? ', selected' : ''}',
                  button: true,
                  child: GestureDetector(
                    onTap: () => onColorSelected(hex),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _parse(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: _parse(hex).withValues(alpha: 0.5),
                                  blurRadius: 6,
                                )
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full Preview Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _FullPreviewSheet extends StatelessWidget {
  const _FullPreviewSheet({
    required this.templateId,
    required this.resume,
    required this.renderData,
    required this.isSelected,
    required this.onSelect,
  });

  final String templateId;
  final Resume resume;
  final ResumeRenderData renderData;
  final bool isSelected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Column(
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
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  templateId[0].toUpperCase() + templateId.substring(1),
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (!isSelected)
                ElevatedButton(
                  onPressed: onSelect,
                  style:
                      ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                  child: const Text('Use This Template'),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: accent),
                      const SizedBox(width: 4),
                      Text('Active',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accent)),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close preview',
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final scale = constraints.maxWidth / kResumePageWidth;
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: kResumePageHeight * scale,
                    child: FittedBox(
                      fit: BoxFit.fill,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: kResumePageWidth,
                        height: kResumePageHeight,
                        child: ResumeTemplateRenderer(
                          resume: resume,
                          data: renderData,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
