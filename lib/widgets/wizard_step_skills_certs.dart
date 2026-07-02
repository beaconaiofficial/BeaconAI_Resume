import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../models/resume_sections.dart';
import '../../models/app_enums.dart';
import '../../constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../utils/wizard_validator.dart';
import 'wizard_widgets.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// Step 5 — Skills
// ─────────────────────────────────────────────────────────────────────────────

class WizardStepSkills extends StatefulWidget {
  const WizardStepSkills({
    super.key,
    required this.entries,
    required this.isUploadPath,
    required this.formKey,
    required this.onChanged,
  });

  final List<SkillEntry> entries;
  final bool isUploadPath;
  final GlobalKey<FormState> formKey;
  final ValueChanged<List<SkillEntry>> onChanged;

  @override
  State<WizardStepSkills> createState() => _WizardStepSkillsState();
}

class _WizardStepSkillsState extends State<WizardStepSkills> {
  late List<SkillEntry> _entries;
  final _newSkillCtrl = TextEditingController();
  final _newSkillFocus = FocusNode();
  String? _addError;
  SkillCategoryEnum _newCategory = SkillCategoryEnum.uncategorized;

  @override
  void initState() {
    super.initState();
    _entries = List.from(widget.entries);
  }

  @override
  void didUpdateWidget(WizardStepSkills oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameIds(widget.entries, _entries)) {
      setState(() => _entries = List.from(widget.entries));
    }
  }

  static bool _sameIds(List<SkillEntry> a, List<SkillEntry> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _newSkillCtrl.dispose();
    _newSkillFocus.dispose();
    super.dispose();
  }

  void _addSkill() {
    final name = _newSkillCtrl.text.trim();
    final error = WizardValidator.validateSkill(name);
    if (error != null) {
      setState(() => _addError = error);
      return;
    }
    // Deduplicate — case insensitive
    if (_entries.any((e) => e.name.toLowerCase() == name.toLowerCase())) {
      setState(() => _addError = 'This skill is already in your list.');
      return;
    }

    final entry = SkillEntry(
      id: _uuid.v4(),
      name: name,
      category: _newCategory,
    );

    setState(() {
      _entries.add(entry);
      _newSkillCtrl.clear();
      _addError = null;
      _newCategory = SkillCategoryEnum.uncategorized;
    });
    widget.onChanged(_entries);
    _newSkillFocus.requestFocus();
  }

  void _remove(int i) {
    setState(() => _entries.removeAt(i));
    widget.onChanged(_entries);
  }

  void _updateCategory(int i, SkillCategoryEnum cat) {
    final updated = SkillEntry(
      id: _entries[i].id,
      name: _entries[i].name,
      category: cat,
      isAIPrefilled: false,
    );
    setState(() => _entries[i] = updated);
    widget.onChanged(_entries);
  }

  Color _counterColor(BuildContext context, bool isDark) {
    final count = _entries.length;
    if (count >= AppConstants.skillsMinRecommended &&
        count <= AppConstants.skillsMaxRecommended) {
      return isDark ? AppColors.successDark : AppColors.successLight;
    }
    if (count > AppConstants.skillsMaxRecommended) {
      return isDark ? AppColors.warningDark : AppColors.warningLight;
    }
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = _entries.length;

    return Form(
      key: widget.formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          if (!widget.isUploadPath)
            const SectionTipCard(
              tip: 'Aim for 8–12 skills that mirror the exact language '
                  'of the job posting. Include specific software names '
                  '(e.g. Workday, Salesforce) — these are direct ATS keyword hits.',
              icon: Icons.tips_and_updates_outlined,
            ),

          // Progress counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Skills added',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Semantics(
                label:
                    '$count skills added. Target is ${AppConstants.skillsMinRecommended} to ${AppConstants.skillsMaxRecommended}.',
                child: Text(
                  '$count / ${AppConstants.skillsMaxRecommended}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _counterColor(context, isDark),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Progress bar toward 8-12 target
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:
                  (count / AppConstants.skillsMaxRecommended).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: Theme.of(context).colorScheme.outlineVariant,
              valueColor:
                  AlwaysStoppedAnimation<Color>(_counterColor(context, isDark)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Target: ${AppConstants.skillsMinRecommended}–${AppConstants.skillsMaxRecommended} skills',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // Existing skills list
          if (_entries.isNotEmpty) ...[
            for (int i = 0; i < _entries.length; i++)
              _SkillRow(
                entry: _entries[i],
                isDark: isDark,
                onRemove: () => _remove(i),
                onCategoryChanged: (cat) => _updateCategory(i, cat),
              ),
            const SizedBox(height: 16),
          ],

          // Add new skill row
          _AddSkillRow(
            controller: _newSkillCtrl,
            focusNode: _newSkillFocus,
            selectedCategory: _newCategory,
            errorText: _addError,
            onCategoryChanged: (cat) => setState(() => _newCategory = cat),
            onAdd: _addSkill,
            onChanged: (_) {
              if (_addError != null) setState(() => _addError = null);
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skill Row — existing skill with category dropdown and remove button
// ─────────────────────────────────────────────────────────────────────────────

class _SkillRow extends StatelessWidget {
  const _SkillRow({
    required this.entry,
    required this.isDark,
    required this.onRemove,
    required this.onCategoryChanged,
  });

  final SkillEntry entry;
  final bool isDark;
  final VoidCallback onRemove;
  final ValueChanged<SkillCategoryEnum> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final aiColor = isDark ? AppColors.aiIndicatorDark : AppColors.aiIndicator;

    return Semantics(
      label:
          '${entry.name}, category: ${entry.category.displayName}. Double-tap to remove.',
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                entry.isAIPrefilled ? aiColor.withValues(alpha: 0.4) : border,
            width: entry.isAIPrefilled ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // AI badge
            if (entry.isAIPrefilled) ...[
              const AiBadge(),
              const SizedBox(width: 8),
            ],

            // Skill name
            Expanded(
              child: Text(
                entry.name,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),

            // Category dropdown
            DropdownButton<SkillCategoryEnum>(
              value: entry.category,
              underline: const SizedBox.shrink(),
              isDense: true,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              items: SkillCategoryEnum.values
                  .map((cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(cat.displayName),
                      ))
                  .toList(),
              onChanged: (cat) {
                if (cat != null) onCategoryChanged(cat);
              },
            ),

            // Remove
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Remove ${entry.name}',
              onPressed: onRemove,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Skill Row
// ─────────────────────────────────────────────────────────────────────────────

class _AddSkillRow extends StatelessWidget {
  const _AddSkillRow({
    required this.controller,
    required this.focusNode,
    required this.selectedCategory,
    required this.errorText,
    required this.onCategoryChanged,
    required this.onAdd,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final SkillCategoryEnum selectedCategory;
  final String? errorText;
  final ValueChanged<SkillCategoryEnum> onCategoryChanged;
  final VoidCallback onAdd;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Skill name input
            Expanded(
              child: TextFormField(
                controller: controller,
                focusNode: focusNode,
                maxLength: AppConstants.maxLengthSkillTag,
                buildCounter: (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => onAdd(),
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: 'Add a skill…',
                  errorText: errorText,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Category picker
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              child: DropdownButton<SkillCategoryEnum>(
                value: selectedCategory,
                underline: const SizedBox.shrink(),
                isDense: true,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                items: SkillCategoryEnum.values
                    .map((cat) => DropdownMenuItem(
                          value: cat,
                          child: Text(cat.displayName),
                        ))
                    .toList(),
                onChanged: (cat) {
                  if (cat != null) onCategoryChanged(cat);
                },
              ),
            ),
            const SizedBox(width: 8),

            // Add button
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: onAdd,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Add'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 6 — Certifications (fully optional)
// ─────────────────────────────────────────────────────────────────────────────

class WizardStepCertifications extends StatefulWidget {
  const WizardStepCertifications({
    super.key,
    required this.entries,
    required this.isUploadPath,
    required this.formKey,
    required this.onChanged,
  });

  final List<CertificationEntry> entries;
  final bool isUploadPath;
  final GlobalKey<FormState> formKey;
  final ValueChanged<List<CertificationEntry>> onChanged;

  @override
  State<WizardStepCertifications> createState() =>
      _WizardStepCertificationsState();
}

class _WizardStepCertificationsState extends State<WizardStepCertifications> {
  late List<CertificationEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = List.from(widget.entries);
  }

  @override
  void didUpdateWidget(WizardStepCertifications oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameIds(widget.entries, _entries)) {
      setState(() => _entries = List.from(widget.entries));
    }
  }

  static bool _sameIds(List<CertificationEntry> a, List<CertificationEntry> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  CertificationEntry _blank() => CertificationEntry(id: _uuid.v4());

  void _add() {
    setState(() => _entries.add(_blank()));
    widget.onChanged(_entries);
  }

  void _remove(int i) {
    setState(() => _entries.removeAt(i));
    widget.onChanged(_entries);
  }

  void _update(int i, CertificationEntry updated) {
    _entries[i] = updated;
    widget.onChanged(_entries);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          // Optional notice
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'This step is optional. Skip it if you have no certifications '
              'or prefer to add them later.',
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 20),

          for (int i = 0; i < _entries.length; i++) ...[
            _CertCard(
              entry: _entries[i],
              index: i,
              onChanged: (u) => _update(i, u),
              onRemove: () => _remove(i),
            ),
            const SizedBox(height: 16),
          ],

          if (_entries.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No certifications yet',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

          OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Certification'),
          ),
        ],
      ),
    );
  }
}

class _CertCard extends StatefulWidget {
  const _CertCard({
    required this.entry,
    required this.index,
    required this.onChanged,
    required this.onRemove,
  });

  final CertificationEntry entry;
  final int index;
  final ValueChanged<CertificationEntry> onChanged;
  final VoidCallback onRemove;

  @override
  State<_CertCard> createState() => _CertCardState();
}

class _CertCardState extends State<_CertCard> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _issuerCtrl;
  late final TextEditingController _earnedCtrl;
  late final TextEditingController _expiresCtrl;
  late final TextEditingController _credentialCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _nameCtrl = TextEditingController(text: e.name);
    _issuerCtrl = TextEditingController(text: e.issuer);
    _earnedCtrl = TextEditingController(text: e.dateEarned);
    _expiresCtrl = TextEditingController(text: e.expiresDate ?? '');
    _credentialCtrl = TextEditingController(text: e.credentialId ?? '');

    for (final c in [
      _nameCtrl,
      _issuerCtrl,
      _earnedCtrl,
      _expiresCtrl,
      _credentialCtrl
    ]) {
      c.addListener(_notify);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _issuerCtrl,
      _earnedCtrl,
      _expiresCtrl,
      _credentialCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _notify() {
    widget.onChanged(CertificationEntry(
      id: widget.entry.id,
      name: _nameCtrl.text,
      issuer: _issuerCtrl.text,
      dateEarned: _earnedCtrl.text,
      expiresDate: _expiresCtrl.text.isEmpty ? null : _expiresCtrl.text,
      credentialId: _credentialCtrl.text.isEmpty ? null : _credentialCtrl.text,
      isAIPrefilled: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final label = _nameCtrl.text.isNotEmpty
        ? _nameCtrl.text
        : 'Certification ${widget.index + 1}';

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (widget.entry.isAIPrefilled) ...[
                const AiBadge(),
                const SizedBox(width: 4),
              ],
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Remove',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                onPressed: widget.onRemove,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          const SizedBox(height: 14),
          WizardTextField(
            label: 'Certification Name',
            hint: 'e.g. AWS Certified Solutions Architect',
            controller: _nameCtrl,
            validator: WizardValidator.validateCertName,
            maxLength: AppConstants.maxLengthCertName,
          ),
          const SizedBox(height: 14),
          WizardTextField(
            label: 'Issuing Organization',
            hint: 'e.g. Amazon Web Services',
            controller: _issuerCtrl,
            validator: (v) =>
                WizardValidator.validateContentField(v, maxLength: 100),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MonthYearPickerField(
                  label: 'Date Earned',
                  hint: 'Mar 2023',
                  controller: _earnedCtrl,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MonthYearPickerField(
                  label: 'Expiry Date',
                  hint: 'Mar 2026',
                  controller: _expiresCtrl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          WizardTextField(
            label: 'Credential ID (optional)',
            hint: 'e.g. AWS-123456',
            controller: _credentialCtrl,
            validator: (v) => null,
          ),
        ],
      ),
    );
  }
}
