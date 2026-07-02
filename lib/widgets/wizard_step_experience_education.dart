import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../models/resume_sections.dart';
import '../../constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../utils/wizard_validator.dart';
import 'wizard_widgets.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// Step 3 — Work Experience
// ─────────────────────────────────────────────────────────────────────────────

class WizardStepExperience extends StatefulWidget {
  const WizardStepExperience({
    super.key,
    required this.entries,
    required this.isUploadPath,
    required this.formKey,
    required this.onChanged,
  });

  final List<ExperienceEntry> entries;
  final bool isUploadPath;
  final GlobalKey<FormState> formKey;
  final ValueChanged<List<ExperienceEntry>> onChanged;

  @override
  State<WizardStepExperience> createState() => _WizardStepExperienceState();
}

class _WizardStepExperienceState extends State<WizardStepExperience> {
  late List<ExperienceEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = List.from(widget.entries);
    if (_entries.isEmpty) _entries.add(_blank());
  }

  @override
  void didUpdateWidget(WizardStepExperience oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync local state when the parent passes a structurally different list
    // (e.g. after _reloadFromHive or an external delete).
    if (!_sameIds(widget.entries, _entries)) {
      setState(() {
        _entries = List.from(widget.entries);
        if (_entries.isEmpty) _entries.add(_blank());
      });
    }
  }

  static bool _sameIds(List<ExperienceEntry> a, List<ExperienceEntry> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  ExperienceEntry _blank() => ExperienceEntry(id: _uuid.v4());

  void _add() {
    setState(() => _entries.add(_blank()));
    widget.onChanged(_entries);
  }

  void _remove(int index) {
    if (_entries.length == 1) return; // keep at least one card
    setState(() => _entries.removeAt(index));
    widget.onChanged(_entries);
  }

  void _update(int index, ExperienceEntry updated) {
    _entries[index] = updated;
    widget.onChanged(_entries);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          if (!widget.isUploadPath)
            const SectionTipCard(
              tip: 'Use the STAR method for achievement bullets: '
                  'Situation → Task → Action → Result. '
                  'Quantify results wherever possible (%, \$, headcount, time saved).',
              icon: Icons.star_outline,
            ),

          // Experience cards
          for (int i = 0; i < _entries.length; i++) ...[
            _ExperienceCard(
              entry: _entries[i],
              index: i,
              canRemove: _entries.length > 1,
              onChanged: (updated) => _update(i, updated),
              onRemove: () => _remove(i),
            ),
            const SizedBox(height: 16),
          ],

          // Add another
          OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Another Position'),
          ),

          const SizedBox(height: 8),
          Center(
            child: Text(
              'Add what you have — you can complete this later.',
              style: GoogleFonts.inter(
                fontSize: 12,
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
// Experience Card
// ─────────────────────────────────────────────────────────────────────────────

class _ExperienceCard extends StatefulWidget {
  const _ExperienceCard({
    required this.entry,
    required this.index,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final ExperienceEntry entry;
  final int index;
  final bool canRemove;
  final ValueChanged<ExperienceEntry> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ExperienceCard> createState() => _ExperienceCardState();
}

class _ExperienceCardState extends State<_ExperienceCard> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _companyCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  late bool _isCurrent;
  late List<TextEditingController> _bulletCtrls;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleCtrl = TextEditingController(text: e.title);
    _companyCtrl = TextEditingController(text: e.company);
    _locationCtrl = TextEditingController(text: e.location);
    _startCtrl = TextEditingController(text: e.startDate);
    _endCtrl = TextEditingController(text: e.endDate ?? '');
    _isCurrent = e.isCurrent;
    _bulletCtrls = e.bullets.isEmpty
        ? [TextEditingController()]
        : e.bullets.map((b) => TextEditingController(text: b)).toList();

    for (final ctrl in [
      _titleCtrl,
      _companyCtrl,
      _locationCtrl,
      _startCtrl,
      _endCtrl
    ]) {
      ctrl.addListener(_notify);
    }
    for (final ctrl in _bulletCtrls) {
      ctrl.addListener(_notify);
    }
  }

  @override
  void dispose() {
    for (final ctrl in [
      _titleCtrl,
      _companyCtrl,
      _locationCtrl,
      _startCtrl,
      _endCtrl
    ]) {
      ctrl.dispose();
    }
    for (final ctrl in _bulletCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _notify() {
    widget.onChanged(ExperienceEntry(
      id: widget.entry.id,
      title: _titleCtrl.text,
      company: _companyCtrl.text,
      location: _locationCtrl.text,
      startDate: _startCtrl.text,
      endDate: _isCurrent ? null : _endCtrl.text,
      isCurrent: _isCurrent,
      bullets: _bulletCtrls.map((c) => c.text).toList(),
      isAIPrefilled: false, // cleared on any edit
    ));
  }

  void _addBullet() {
    final ctrl = TextEditingController();
    ctrl.addListener(_notify);
    setState(() => _bulletCtrls.add(ctrl));
  }

  void _removeBullet(int i) {
    if (_bulletCtrls.length == 1) return;
    _bulletCtrls[i].dispose();
    setState(() => _bulletCtrls.removeAt(i));
    _notify();
  }

  String get _cardTitle {
    final title = _titleCtrl.text.trim();
    final company = _companyCtrl.text.trim();
    if (title.isNotEmpty && company.isNotEmpty) return '$title — $company';
    if (title.isNotEmpty) return title;
    if (company.isNotEmpty) return company;
    return 'Position ${widget.index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          // Card header — tap to collapse/expand
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _cardTitle,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (widget.entry.isAIPrefilled) const AiBadge(),
                  const SizedBox(width: 4),
                  if (widget.canRemove)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Remove this position',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      onPressed: widget.onRemove,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          if (_isExpanded) ...[
            Divider(height: 1, color: border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title / Company
                  WizardTextField(
                    label: 'Job Title *',
                    hint: 'e.g. Software Engineer',
                    controller: _titleCtrl,
                    validator: WizardValidator.validateJobTitle,
                  ),
                  const SizedBox(height: 14),
                  WizardTextField(
                    label: 'Company *',
                    hint: 'e.g. Acme Corp',
                    controller: _companyCtrl,
                    validator: WizardValidator.validateCompany,
                  ),
                  const SizedBox(height: 14),
                  WizardTextField(
                    label: 'Location',
                    hint: 'Austin, TX',
                    controller: _locationCtrl,
                    validator: WizardValidator.validateCityState,
                  ),
                  const SizedBox(height: 14),

                  // Dates
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: MonthYearPickerField(
                          label: 'Start Date',
                          hint: 'Jan 2022',
                          controller: _startCtrl,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MonthYearPickerField(
                          label: 'End Date',
                          hint: 'Dec 2023',
                          controller: _endCtrl,
                          showPresentToggle: true,
                          isPresent: _isCurrent,
                          onPresentChanged: (v) {
                            setState(() => _isCurrent = v);
                            _notify();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Current role toggle
                  Row(
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: Checkbox(
                          value: _isCurrent,
                          activeColor: accent,
                          onChanged: (v) {
                            setState(() => _isCurrent = v ?? false);
                            _notify();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'I currently work here',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Bullets
                  Text(
                    'Achievement Bullets',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use the STAR method — one achievement per bullet.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),

                  for (int i = 0; i < _bulletCtrls.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Icon(Icons.circle,
                                size: 6,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _bulletCtrls[i],
                              maxLines: 2,
                              maxLength: AppConstants.maxLengthExperienceBullet,
                              buildCounter: (_,
                                      {required currentLength,
                                      required isFocused,
                                      maxLength}) =>
                                  null,
                              decoration: const InputDecoration(
                                hintText:
                                    'e.g. Reduced deployment time by 40% by automating CI/CD pipelines',
                              ),
                              validator: WizardValidator.validateBullet,
                            ),
                          ),
                          const SizedBox(width: 4),
                          if (_bulletCtrls.length > 1)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 18),
                              tooltip: 'Remove bullet',
                              onPressed: () => _removeBullet(i),
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              constraints: const BoxConstraints(
                                  minWidth: 36, minHeight: 36),
                            ),
                        ],
                      ),
                    ),

                  TextButton.icon(
                    onPressed: _addBullet,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Bullet'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 4 — Education
// ─────────────────────────────────────────────────────────────────────────────

class WizardStepEducation extends StatefulWidget {
  const WizardStepEducation({
    super.key,
    required this.entries,
    required this.isUploadPath,
    required this.formKey,
    required this.onChanged,
  });

  final List<EducationEntry> entries;
  final bool isUploadPath;
  final GlobalKey<FormState> formKey;
  final ValueChanged<List<EducationEntry>> onChanged;

  @override
  State<WizardStepEducation> createState() => _WizardStepEducationState();
}

class _WizardStepEducationState extends State<WizardStepEducation> {
  late List<EducationEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = List.from(widget.entries);
    if (_entries.isEmpty) _entries.add(_blank());
  }

  @override
  void didUpdateWidget(WizardStepEducation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameIds(widget.entries, _entries)) {
      setState(() {
        _entries = List.from(widget.entries);
        if (_entries.isEmpty) _entries.add(_blank());
      });
    }
  }

  static bool _sameIds(List<EducationEntry> a, List<EducationEntry> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  EducationEntry _blank() => EducationEntry(id: _uuid.v4());

  void _add() {
    setState(() => _entries.add(_blank()));
    widget.onChanged(_entries);
  }

  void _remove(int i) {
    if (_entries.length == 1) return;
    setState(() => _entries.removeAt(i));
    widget.onChanged(_entries);
  }

  void _update(int i, EducationEntry updated) {
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
          for (int i = 0; i < _entries.length; i++) ...[
            _EducationCard(
              entry: _entries[i],
              index: i,
              canRemove: _entries.length > 1,
              onChanged: (u) => _update(i, u),
              onRemove: () => _remove(i),
            ),
            const SizedBox(height: 16),
          ],
          OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Another Degree'),
          ),
        ],
      ),
    );
  }
}

class _EducationCard extends StatefulWidget {
  const _EducationCard({
    required this.entry,
    required this.index,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final EducationEntry entry;
  final int index;
  final bool canRemove;
  final ValueChanged<EducationEntry> onChanged;
  final VoidCallback onRemove;

  @override
  State<_EducationCard> createState() => _EducationCardState();
}

class _EducationCardState extends State<_EducationCard> {
  late final TextEditingController _degreeCtrl;
  late final TextEditingController _institutionCtrl;
  late final TextEditingController _fieldCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _gpaCtrl;
  late final TextEditingController _honorsCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _degreeCtrl = TextEditingController(text: e.degree);
    _institutionCtrl = TextEditingController(text: e.institution);
    _fieldCtrl = TextEditingController(text: e.fieldOfStudy);
    _yearCtrl = TextEditingController(text: e.graduationYear);
    _gpaCtrl = TextEditingController(text: e.gpa ?? '');
    _honorsCtrl = TextEditingController(text: e.honors ?? '');

    for (final c in [
      _degreeCtrl,
      _institutionCtrl,
      _fieldCtrl,
      _yearCtrl,
      _gpaCtrl,
      _honorsCtrl,
    ]) {
      c.addListener(_notify);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _degreeCtrl,
      _institutionCtrl,
      _fieldCtrl,
      _yearCtrl,
      _gpaCtrl,
      _honorsCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _notify() {
    widget.onChanged(EducationEntry(
      id: widget.entry.id,
      degree: _degreeCtrl.text,
      institution: _institutionCtrl.text,
      fieldOfStudy: _fieldCtrl.text,
      graduationYear: _yearCtrl.text,
      gpa: _gpaCtrl.text.isEmpty ? null : _gpaCtrl.text,
      isAIPrefilled: false,
      honors: _honorsCtrl.text.isEmpty ? null : _honorsCtrl.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    final cardLabel = _institutionCtrl.text.isNotEmpty
        ? _institutionCtrl.text
        : 'Education ${widget.index + 1}';

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
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  cardLabel,
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
              if (widget.canRemove)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Remove',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onPressed: widget.onRemove,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
            ],
          ),
          const SizedBox(height: 14),

          WizardTextField(
            label: 'Degree',
            hint: 'e.g. Bachelor of Science',
            controller: _degreeCtrl,
            validator: (v) =>
                WizardValidator.validateContentField(v, maxLength: 100),
          ),
          const SizedBox(height: 14),

          WizardTextField(
            label: 'Institution',
            hint: 'e.g. University of Texas at Austin',
            controller: _institutionCtrl,
            validator: (v) =>
                WizardValidator.validateContentField(v, maxLength: 100),
          ),
          const SizedBox(height: 14),

          WizardTextField(
            label: 'Field of Study',
            hint: 'e.g. Computer Science',
            controller: _fieldCtrl,
            validator: (v) =>
                WizardValidator.validateContentField(v, maxLength: 100),
          ),
          const SizedBox(height: 14),

          // Year + GPA row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: YearPickerField(
                  label: 'Graduation Year',
                  hint: '2022',
                  controller: _yearCtrl,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: WizardTextField(
                  label: 'GPA (optional)',
                  hint: '3.8',
                  controller: _gpaCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Include GPA only if 3.5 or above.',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),

          WizardTextField(
            label: 'Honors (optional)',
            hint: 'e.g. Summa Cum Laude, Dean\'s List, Honors Program',
            controller: _honorsCtrl,
            validator: (v) => null,
          ),
        ],
      ),
    );
  }
}
