import 'package:flutter/material.dart';
import '../models/resume_sections.dart';
import '../theme/app_colors.dart';
import 'resume_template_renderer.dart' show ResumeRenderData, kResumePageWidth;
import 'phase2_templates.dart' show TapFieldFn;

// ─────────────────────────────────────────────────────────────────────────────
// Phase 3 Templates: Technical, Horizon, Sidebar, Pillar
//
// Same architecture as phase2_templates.dart — stateless widgets rendering
// from the shared ResumeRenderData, fixed-width canvas at kResumePageWidth,
// tappable() helper for inline edit support.
//
// Design intent (from Template Picker "best for" labels + spec §11):
//   Technical — Software/IT/Engineering: skills ABOVE experience, monospace
//               accents on dates/labels for a developer-tool feel
//   Horizon   — Business/Sales: full-width color band header, user-selectable
//               accent color (6 presets, stored on Resume.templateAccentColor)
//   Sidebar   — IT/Marketing: 25% contact/skills sidebar + 75% main column.
//               ATS EXPORT RULE (spec §11): sidebar content is duplicated
//               into the main column for PDF/DOCX export — this widget is
//               the SCREEN PREVIEW only; the renderer's two-column layout
//               here is never what gets exported, exports always flatten
//               to single-column via the existing ATS export path.
//   Pillar    — Creative/PR/Media: vertical accent rule beside the name block
// ─────────────────────────────────────────────────────────────────────────────

const double _pageWidth = kResumePageWidth;
const double _pagePaddingH = 48.0;
const double _pagePaddingV = 48.0;

Widget _tappable({
  required TapFieldFn? onTapField,
  required String fieldId,
  required String value,
  required Widget child,
  bool isAIPrefilled = false,
}) {
  if (onTapField == null) return child;
  final Widget core =
      GestureDetector(onTap: () => onTapField(fieldId, value), child: child);
  if (!isAIPrefilled) return core;
  return Stack(
    clipBehavior: Clip.none,
    children: [
      core,
      Positioned(
        top: -3,
        right: -3,
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
              color: Color(0xFF7C3AED), shape: BoxShape.circle),
        ),
      ),
    ],
  );
}

/// Contact line: individually tappable fields in edit mode.
Widget _contactLineWidget(
  ContactInfo c,
  TextStyle style,
  TapFieldFn? onTapField, {
  bool centered = false,
}) {
  if (onTapField == null) {
    final parts = [c.cityState, c.phone, c.email, c.linkedInUrl]
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .toList();
    return Text(parts.join('   |   '),
        style: style,
        textAlign: centered ? TextAlign.center : TextAlign.start);
  }
  final fields = <({String id, String value})>[];
  if (c.cityState.isNotEmpty) fields.add((id: 'contact.cityState', value: c.cityState));
  if (c.phone.isNotEmpty) fields.add((id: 'contact.phone', value: c.phone));
  if (c.email.isNotEmpty) fields.add((id: 'contact.email', value: c.email));
  if (c.linkedInUrl != null && c.linkedInUrl!.isNotEmpty) {
    fields.add((id: 'contact.linkedInUrl', value: c.linkedInUrl!));
  }
  if (c.websiteUrl != null && c.websiteUrl!.isNotEmpty) {
    fields.add((id: 'contact.websiteUrl', value: c.websiteUrl!));
  }
  if (c.gitHubUrl != null && c.gitHubUrl!.isNotEmpty) {
    fields.add((id: 'contact.gitHubUrl', value: c.gitHubUrl!));
  }
  final children = <Widget>[];
  for (int i = 0; i < fields.length; i++) {
    children.add(_tappable(
        onTapField: onTapField,
        fieldId: fields[i].id,
        value: fields[i].value,
        child: Text(fields[i].value, style: style)));
    if (i < fields.length - 1) children.add(Text('   |   ', style: style));
  }
  return Wrap(
    alignment: centered ? WrapAlignment.center : WrapAlignment.start,
    children: children,
  );
}

/// Single certification row with tappable name, issuer, and date.
Widget _certEntryWidget(
  CertificationEntry c,
  int index,
  TextStyle titleStyle,
  TextStyle metaStyle,
  TapFieldFn? onTapField,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Wrap(
            children: [
              _tappable(
                  onTapField: onTapField,
                  fieldId: 'certifications[$index].name',
                  value: c.name,
                  isAIPrefilled: c.isAIPrefilled,
                  child: Text(c.name, style: titleStyle)),
              Text(' — ', style: titleStyle),
              _tappable(
                  onTapField: onTapField,
                  fieldId: 'certifications[$index].issuer',
                  value: c.issuer,
                  isAIPrefilled: c.isAIPrefilled,
                  child: Text(c.issuer, style: titleStyle)),
            ],
          ),
        ),
        _tappable(
            onTapField: onTapField,
            fieldId: 'certifications[$index].dateEarned',
            value: c.dateEarned,
            isAIPrefilled: c.isAIPrefilled,
            child: Text(c.dateEarned, style: metaStyle)),
      ],
    ),
  );
}

/// Skills with individually tappable names in edit mode.
Widget _skillsWidget(
    List<SkillEntry> skills, TextStyle style, TapFieldFn? onTapField) {
  if (onTapField == null) {
    return Text(skills.map((s) => s.name).join('   ·   '), style: style);
  }
  final children = <Widget>[];
  for (int i = 0; i < skills.length; i++) {
    children.add(_tappable(
        onTapField: onTapField,
        fieldId: 'skills[$i]',
        value: skills[i].name,
        isAIPrefilled: skills[i].isAIPrefilled,
        child: Text(skills[i].name, style: style)));
    if (i < skills.length - 1) children.add(Text('   ·   ', style: style));
  }
  return Wrap(children: children);
}

/// Skill chips with individually tappable names in edit mode.
Widget _skillChipsWidget(
  List<SkillEntry> skills,
  TextStyle style,
  TapFieldFn? onTapField,
  Color borderColor, {
  Color? bgColor,
  BorderRadius? radius,
}) {
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: skills.asMap().entries.map((entry) {
      final i = entry.key;
      final s = entry.value;
      final chip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: radius ?? BorderRadius.circular(14),
        ),
        child: Text(s.name, style: style),
      );
      return _tappable(
          onTapField: onTapField,
          fieldId: 'skills[$i]',
          value: s.name,
          isAIPrefilled: s.isAIPrefilled,
          child: chip);
    }).toList(),
  );
}

/// Education row with all fields tappable.
Widget _eduEntryWidget(
  EducationEntry e,
  int index,
  TextStyle titleStyle,
  TextStyle metaStyle,
  TapFieldFn? onTapField,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _tappable(
                  onTapField: onTapField,
                  fieldId: 'education[$index].institution',
                  value: e.institution,
                  isAIPrefilled: e.isAIPrefilled,
                  child: Text(e.institution, style: titleStyle)),
              if (e.degree.isNotEmpty || e.fieldOfStudy.isNotEmpty)
                onTapField != null
                    ? Wrap(
                        children: [
                          if (e.degree.isNotEmpty)
                            _tappable(
                                onTapField: onTapField,
                                fieldId: 'education[$index].degree',
                                value: e.degree,
                                isAIPrefilled: e.isAIPrefilled,
                                child: Text(e.degree, style: metaStyle)),
                          if (e.degree.isNotEmpty && e.fieldOfStudy.isNotEmpty)
                            Text(', ', style: metaStyle),
                          if (e.fieldOfStudy.isNotEmpty)
                            _tappable(
                                onTapField: onTapField,
                                fieldId: 'education[$index].fieldOfStudy',
                                value: e.fieldOfStudy,
                                isAIPrefilled: e.isAIPrefilled,
                                child: Text(e.fieldOfStudy, style: metaStyle)),
                        ],
                      )
                    : Text(
                        [e.degree, e.fieldOfStudy]
                            .where((s) => s.isNotEmpty)
                            .join(', '),
                        style: metaStyle,
                      ),
              if (e.honors != null && e.honors!.isNotEmpty)
                Text(
                  e.honors!,
                  style: metaStyle.copyWith(fontStyle: FontStyle.italic),
                ),
              if (e.gpa != null && e.gpa!.isNotEmpty)
                _tappable(
                    onTapField: onTapField,
                    fieldId: 'education[$index].gpa',
                    value: e.gpa!,
                    child: Text('GPA: ${e.gpa}', style: metaStyle)),
            ],
          ),
        ),
        _tappable(
            onTapField: onTapField,
            fieldId: 'education[$index].graduationYear',
            value: e.graduationYear,
            isAIPrefilled: e.isAIPrefilled,
            child: Text(e.graduationYear, style: metaStyle)),
      ],
    ),
  );
}

/// Experience entry with tappable title/company/location/dates/bullets.
Widget _expEntryWidget(
  ExperienceEntry e,
  int index,
  TextStyle titleStyle,
  TextStyle metaStyle,
  TextStyle bodyStyle,
  Color bulletChar,
  String bulletCharStr,
  TapFieldFn? onTapField, {
  String separator = '  |  ',
  bool locationOnNewLine = false,
}) {
  final Widget titleArea = onTapField != null
      ? Wrap(
          children: [
            if (e.title.isNotEmpty)
              _tappable(
                  onTapField: onTapField,
                  fieldId: 'experience[$index].title',
                  value: e.title,
                  isAIPrefilled: e.isAIPrefilled,
                  child: Text(e.title, style: titleStyle)),
            if (e.title.isNotEmpty &&
                (e.company.isNotEmpty || (!locationOnNewLine && e.location.isNotEmpty)))
              Text(separator, style: titleStyle),
            if (e.company.isNotEmpty)
              _tappable(
                  onTapField: onTapField,
                  fieldId: 'experience[$index].company',
                  value: e.company,
                  isAIPrefilled: e.isAIPrefilled,
                  child: Text(e.company, style: titleStyle)),
            if (!locationOnNewLine && e.company.isNotEmpty && e.location.isNotEmpty)
              Text(separator, style: titleStyle),
            if (!locationOnNewLine && e.location.isNotEmpty)
              _tappable(
                  onTapField: onTapField,
                  fieldId: 'experience[$index].location',
                  value: e.location,
                  isAIPrefilled: e.isAIPrefilled,
                  child: Text(e.location, style: titleStyle)),
          ],
        )
      : Text(
          locationOnNewLine
              ? [e.title, e.company].where((s) => s.isNotEmpty).join(separator)
              : [e.title, e.company, e.location]
                  .where((s) => s.isNotEmpty)
                  .join(separator),
          style: titleStyle,
        );

  final Widget dateArea = onTapField != null
      ? Wrap(children: [
          _tappable(
              onTapField: onTapField,
              fieldId: 'experience[$index].startDate',
              value: e.startDate,
              child: Text(e.startDate, style: metaStyle)),
          Text(' – ', style: metaStyle),
          _tappable(
              onTapField: onTapField,
              fieldId: 'experience[$index].endDate',
              value: e.isCurrent ? 'Present' : (e.endDate ?? ''),
              child: Text(e.isCurrent ? 'Present' : (e.endDate ?? ''),
                  style: metaStyle)),
        ])
      : Text(e.dateRange, style: metaStyle);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: titleArea),
          const SizedBox(width: 8),
          dateArea,
        ],
      ),
      if (locationOnNewLine && e.location.isNotEmpty)
        _tappable(
            onTapField: onTapField,
            fieldId: 'experience[$index].location',
            value: e.location,
            isAIPrefilled: e.isAIPrefilled,
            child: Text(e.location, style: metaStyle)),
      const SizedBox(height: 3),
      ...e.bullets.where((b) => b.isNotEmpty).map((b) => Padding(
            padding: const EdgeInsets.only(top: 3, left: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bulletCharStr,
                    style: bodyStyle.copyWith(color: bulletChar)),
                Expanded(
                  child: _tappable(
                      onTapField: onTapField,
                      fieldId:
                          'experience[$index].bullet.${e.bullets.indexOf(b)}',
                      value: b,
                      isAIPrefilled: e.isAIPrefilled,
                      child: Text(b, style: bodyStyle)),
                ),
              ],
            ),
          )),
    ],
  );
}

/// Horizon accent colors — must match _HorizonAccentPicker in
/// template_picker_screen.dart exactly (same hex values, same names).
const Map<String, Color> kHorizonAccentColors = {
  '#1A237E': Color(0xFF1A237E), // Navy
  '#212121': Color(0xFF212121), // Charcoal
  '#1B5E20': Color(0xFF1B5E20), // Forest
  '#455A64': Color(0xFF455A64), // Slate
  '#4A0000': Color(0xFF4A0000), // Burgundy
  '#000000': Color(0xFF000000), // Black
};

Color _resolveHorizonAccent(String? hex) {
  if (hex == null) return kHorizonAccentColors['#1A237E']!;
  return kHorizonAccentColors[hex] ?? kHorizonAccentColors['#1A237E']!;
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 9: TECHNICAL
// Skills above experience. Monospace accents on dates and category labels.
// ─────────────────────────────────────────────────────────────────────────────

class TechnicalTemplate extends StatelessWidget {
  const TechnicalTemplate({super.key, required this.data, this.onTapField});

  final ResumeRenderData data;
  final TapFieldFn? onTapField;

  static const _techAccent = Color(0xFF2D5F3F);

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 25,
      fontWeight: FontWeight.w800,
      color: AppColors.primaryTextLight,
      letterSpacing: -0.3,
    );
    const titleStyle = TextStyle(
      fontFamily: 'JetBrains Mono',
      fontSize: 12,
      color: _techAccent,
    );
    const sectionHeaderStyle = TextStyle(
      fontFamily: 'JetBrains Mono',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: _techAccent,
    );
    const bodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      height: 1.55,
      color: AppColors.primaryTextLight,
    );
    const metaStyle = TextStyle(
      fontFamily: 'JetBrains Mono',
      fontSize: 9.5,
      color: AppColors.secondaryTextLight,
    );
    const entryTitleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );

    Widget sectionHeader(String label) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(
            children: [
              const Text('// ', style: sectionHeaderStyle),
              Text(label, style: sectionHeaderStyle),
            ],
          ),
        );

    return Container(
      width: _pageWidth,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
          horizontal: _pagePaddingH, vertical: _pagePaddingV),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tappable(
            onTapField: onTapField,
            fieldId: 'contact.fullName',
            value: data.contact.fullName,
            child: Text(
              data.contact.fullName.isNotEmpty
                  ? data.contact.fullName
                  : 'Your Name',
              style: nameStyle,
            ),
          ),
          if (data.contact.professionalTitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            _tappable(
              onTapField: onTapField,
              fieldId: 'contact.professionalTitle',
              value: data.contact.professionalTitle,
              child: Text(data.contact.professionalTitle, style: titleStyle),
            ),
          ],
          const SizedBox(height: 6),
          _contactLineWidget(data.contact, metaStyle, onTapField),
          const SizedBox(height: 4),
          Container(height: 2, color: _techAccent),

          if (data.summary.isNotEmpty) ...[
            sectionHeader('summary'),
            _tappable(
              onTapField: onTapField,
              fieldId: 'summary',
              value: data.summary,
              child: Text(data.summary, style: bodyStyle),
            ),
          ],

          // Skills BEFORE experience — Technical template's defining trait
          if (data.skills.isNotEmpty) ...[
            sectionHeader('skills'),
            _skillChipsWidget(
              data.skills,
              bodyStyle.copyWith(fontFamily: 'JetBrains Mono', fontSize: 10),
              onTapField,
              _techAccent.withValues(alpha: 0.3),
              bgColor: _techAccent.withValues(alpha: 0.08),
              radius: BorderRadius.circular(4),
            ),
          ],

          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            sectionHeader('experience'),
            ...data.experience.asMap().entries
                .where((entry) => entry.value.title.isNotEmpty)
                .map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _expEntryWidget(
                        entry.value,
                        entry.key,
                        entryTitleStyle,
                        metaStyle,
                        bodyStyle,
                        _techAccent,
                        '>  ',
                        onTapField,
                        separator: ' @ ',
                        locationOnNewLine: true,
                      ),
                    )),
          ],

          if (data.education.any((e) => e.institution.isNotEmpty)) ...[
            sectionHeader('education'),
            ...data.education.asMap().entries
                .where((entry) => entry.value.institution.isNotEmpty)
                .map((entry) => _eduEntryWidget(
                      entry.value,
                      entry.key,
                      entryTitleStyle,
                      metaStyle,
                      onTapField,
                    )),
          ],

          if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
            sectionHeader('certifications'),
            ...data.certifications.asMap().entries
                .where((entry) => entry.value.name.isNotEmpty)
                .map((entry) => _certEntryWidget(
                      entry.value,
                      entry.key,
                      entryTitleStyle,
                      metaStyle,
                      onTapField,
                    )),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 10: HORIZON
// Full-width color band header. User-selectable accent (6 presets).
// ─────────────────────────────────────────────────────────────────────────────

class HorizonTemplate extends StatelessWidget {
  const HorizonTemplate({
    super.key,
    required this.data,
    this.onTapField,
    this.accentColorHex,
  });

  final ResumeRenderData data;
  final TapFieldFn? onTapField;
  final String? accentColorHex;

  @override
  Widget build(BuildContext context) {
    final accent = _resolveHorizonAccent(accentColorHex);

    const nameStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );
    final titleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 13,
      color: Colors.white.withValues(alpha: 0.85),
    );
    final metaStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10.5,
      color: Colors.white.withValues(alpha: 0.75),
    );
    final sectionHeaderStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: accent,
    );
    const bodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      height: 1.55,
      color: AppColors.primaryTextLight,
    );
    const bodyMetaStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10,
      color: AppColors.secondaryTextLight,
    );
    const entryTitleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );

    Widget sectionHeader(String label) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: sectionHeaderStyle),
              const SizedBox(height: 3),
              Container(height: 1, color: accent.withValues(alpha: 0.25)),
            ],
          ),
        );

    return Container(
      width: _pageWidth,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Full-width color band header
          Container(
            width: double.infinity,
            color: accent,
            padding: const EdgeInsets.symmetric(
                horizontal: _pagePaddingH, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _tappable(
                  onTapField: onTapField,
                  fieldId: 'contact.fullName',
                  value: data.contact.fullName,
                  child: Text(
                    data.contact.fullName.isNotEmpty
                        ? data.contact.fullName
                        : 'Your Name',
                    style: nameStyle,
                  ),
                ),
                if (data.contact.professionalTitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _tappable(
                    onTapField: onTapField,
                    fieldId: 'contact.professionalTitle',
                    value: data.contact.professionalTitle,
                    child: Text(data.contact.professionalTitle, style: titleStyle),
                  ),
                ],
                const SizedBox(height: 8),
                _contactLineWidget(data.contact, metaStyle, onTapField),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: _pagePaddingH, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.summary.isNotEmpty) ...[
                  sectionHeader('SUMMARY'),
                  _tappable(
                    onTapField: onTapField,
                    fieldId: 'summary',
                    value: data.summary,
                    child: Text(data.summary, style: bodyStyle),
                  ),
                ],
                if (data.experience.any((e) => e.title.isNotEmpty)) ...[
                  sectionHeader('EXPERIENCE'),
                  ...data.experience.asMap().entries
                      .where((entry) => entry.value.title.isNotEmpty)
                      .map((entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _expEntryWidget(
                              entry.value,
                              entry.key,
                              entryTitleStyle,
                              bodyMetaStyle,
                              bodyStyle,
                              accent,
                              '•  ',
                              onTapField,
                              separator: ' · ',
                            ),
                          )),
                ],
                if (data.education.any((e) => e.institution.isNotEmpty)) ...[
                  sectionHeader('EDUCATION'),
                  ...data.education.asMap().entries
                      .where((entry) => entry.value.institution.isNotEmpty)
                      .map((entry) => _eduEntryWidget(
                            entry.value,
                            entry.key,
                            entryTitleStyle,
                            bodyMetaStyle,
                            onTapField,
                          )),
                ],
                if (data.skills.isNotEmpty) ...[
                  sectionHeader('SKILLS'),
                  _skillChipsWidget(
                    data.skills,
                    bodyStyle.copyWith(fontSize: 10),
                    onTapField,
                    Colors.transparent,
                    bgColor: accent.withValues(alpha: 0.08),
                  ),
                ],
                if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
                  sectionHeader('CERTIFICATIONS'),
                  ...data.certifications.asMap().entries
                      .where((entry) => entry.value.name.isNotEmpty)
                      .map((entry) => _certEntryWidget(
                            entry.value,
                            entry.key,
                            entryTitleStyle,
                            bodyMetaStyle,
                            onTapField,
                          )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 11: SIDEBAR
// 25% contact/skills sidebar, 75% main column.
//
// ATS EXPORT RULE (spec §11): PDF/DOCX export is ALWAYS single-column,
// regardless of template. The export services (pdf_export_service.dart,
// docx_export_service.dart) already build their own independent single-
// column layout from ResumeRenderData and do NOT call into this widget —
// so the sidebar content (contact + skills) is naturally "duplicated" into
// the single-column export flow simply because the exporters render
// contact and skills directly from the same data, in their own order.
// This widget is therefore SCREEN-PREVIEW ONLY. No special export handling
// needed here — the existing exporters already satisfy the ATS rule.
// ─────────────────────────────────────────────────────────────────────────────

class SidebarTemplate extends StatelessWidget {
  const SidebarTemplate({super.key, required this.data, this.onTapField});

  final ResumeRenderData data;
  final TapFieldFn? onTapField;

  static const _sidebarNavy = Color(0xFF1E2A3A);

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );
    const titleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      color: Color(0xFFB8C4D4),
    );
    const sidebarHeaderStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: Color(0xFF8FA3BD),
    );
    const sidebarBodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10.5,
      height: 1.6,
      color: Color(0xFFE2E8F0),
    );
    const mainSectionHeaderStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: _sidebarNavy,
    );
    const bodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      height: 1.55,
      color: AppColors.primaryTextLight,
    );
    const metaStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10,
      color: AppColors.secondaryTextLight,
    );
    const entryTitleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );

    const sidebarWidth = _pageWidth * 0.25;
    const mainWidth = _pageWidth * 0.75;

    Widget sidebarHeader(String label) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(label, style: sidebarHeaderStyle),
        );

    Widget mainHeader(String label) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: mainSectionHeaderStyle),
              const SizedBox(height: 3),
              Container(height: 1, color: AppColors.borderLight),
            ],
          ),
        );

    return SizedBox(
      width: _pageWidth,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Sidebar (25%) ────────────────────────────────────────────
            Container(
              width: sidebarWidth,
              color: _sidebarNavy,
              padding: const EdgeInsets.fromLTRB(18, 36, 16, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tappable(
                    onTapField: onTapField,
                    fieldId: 'contact.fullName',
                    value: data.contact.fullName,
                    child: Text(
                      data.contact.fullName.isNotEmpty
                          ? data.contact.fullName
                          : 'Your Name',
                      style: nameStyle,
                    ),
                  ),
                  if (data.contact.professionalTitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _tappable(
                      onTapField: onTapField,
                      fieldId: 'contact.professionalTitle',
                      value: data.contact.professionalTitle,
                      child: Text(data.contact.professionalTitle, style: titleStyle),
                    ),
                  ],
                  sidebarHeader('CONTACT'),
                  if (data.contact.cityState.isNotEmpty)
                    _tappable(
                      onTapField: onTapField,
                      fieldId: 'contact.cityState',
                      value: data.contact.cityState,
                      child: Text(data.contact.cityState, style: sidebarBodyStyle),
                    ),
                  if (data.contact.phone.isNotEmpty)
                    _tappable(
                      onTapField: onTapField,
                      fieldId: 'contact.phone',
                      value: data.contact.phone,
                      child: Text(data.contact.phone, style: sidebarBodyStyle),
                    ),
                  if (data.contact.email.isNotEmpty)
                    _tappable(
                      onTapField: onTapField,
                      fieldId: 'contact.email',
                      value: data.contact.email,
                      child: Text(data.contact.email, style: sidebarBodyStyle),
                    ),
                  if (data.contact.linkedInUrl != null &&
                      data.contact.linkedInUrl!.isNotEmpty)
                    _tappable(
                      onTapField: onTapField,
                      fieldId: 'contact.linkedInUrl',
                      value: data.contact.linkedInUrl!,
                      child: Text(data.contact.linkedInUrl!, style: sidebarBodyStyle),
                    ),
                  if (data.skills.isNotEmpty) ...[
                    sidebarHeader('SKILLS'),
                    ...data.skills.asMap().entries.map((entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _tappable(
                            onTapField: onTapField,
                            fieldId: 'skills[${entry.key}]',
                            value: entry.value.name,
                            isAIPrefilled: entry.value.isAIPrefilled,
                            child: Text('•  ${entry.value.name}',
                                style: sidebarBodyStyle),
                          ),
                        )),
                  ],
                  if (data.education.any((e) => e.institution.isNotEmpty)) ...[
                    sidebarHeader('EDUCATION'),
                    ...data.education.asMap().entries
                        .where((entry) => entry.value.institution.isNotEmpty)
                        .map((entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _tappable(
                                    onTapField: onTapField,
                                    fieldId:
                                        'education[${entry.key}].institution',
                                    value: entry.value.institution,
                                    isAIPrefilled: entry.value.isAIPrefilled,
                                    child: Text(entry.value.institution,
                                        style: sidebarBodyStyle.copyWith(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  _tappable(
                                    onTapField: onTapField,
                                    fieldId:
                                        'education[${entry.key}].graduationYear',
                                    value: entry.value.graduationYear,
                                    isAIPrefilled: entry.value.isAIPrefilled,
                                    child: Text(entry.value.graduationYear,
                                        style: sidebarBodyStyle.copyWith(
                                            fontSize: 9.5)),
                                  ),
                                ],
                              ),
                            )),
                  ],
                ],
              ),
            ),

            // ── Main column (75%) ───────────────────────────────────────
            Container(
              width: mainWidth,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data.summary.isNotEmpty) ...[
                    mainHeader('SUMMARY'),
                    _tappable(
                      onTapField: onTapField,
                      fieldId: 'summary',
                      value: data.summary,
                      child: Text(data.summary, style: bodyStyle),
                    ),
                  ],
                  if (data.experience.any((e) => e.title.isNotEmpty)) ...[
                    mainHeader('EXPERIENCE'),
                    ...data.experience.asMap().entries
                        .where((entry) => entry.value.title.isNotEmpty)
                        .map((entry) {
                          final e = entry.value;
                          final idx = entry.key;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _tappable(
                                  onTapField: onTapField,
                                  fieldId: 'experience[$idx].title',
                                  value: e.title,
                                  isAIPrefilled: e.isAIPrefilled,
                                  child: Text(e.title, style: entryTitleStyle),
                                ),
                                if (e.company.isNotEmpty ||
                                    e.location.isNotEmpty)
                                  onTapField != null
                                      ? Wrap(children: [
                                          if (e.company.isNotEmpty)
                                            _tappable(
                                              onTapField: onTapField,
                                              fieldId:
                                                  'experience[$idx].company',
                                              value: e.company,
                                              isAIPrefilled: e.isAIPrefilled,
                                              child: Text(e.company,
                                                  style: metaStyle),
                                            ),
                                          if (e.company.isNotEmpty &&
                                              e.location.isNotEmpty)
                                            const Text(' · ', style: metaStyle),
                                          if (e.location.isNotEmpty)
                                            _tappable(
                                              onTapField: onTapField,
                                              fieldId:
                                                  'experience[$idx].location',
                                              value: e.location,
                                              isAIPrefilled: e.isAIPrefilled,
                                              child: Text(e.location,
                                                  style: metaStyle),
                                            ),
                                        ])
                                      : Text(
                                          [e.company, e.location]
                                              .where((s) => s.isNotEmpty)
                                              .join(' · '),
                                          style: metaStyle,
                                        ),
                                onTapField != null
                                    ? Wrap(children: [
                                        _tappable(
                                          onTapField: onTapField,
                                          fieldId: 'experience[$idx].startDate',
                                          value: e.startDate,
                                          child: Text(e.startDate,
                                              style: metaStyle),
                                        ),
                                        const Text(' – ', style: metaStyle),
                                        _tappable(
                                          onTapField: onTapField,
                                          fieldId: 'experience[$idx].endDate',
                                          value: e.isCurrent
                                              ? 'Present'
                                              : (e.endDate ?? ''),
                                          child: Text(
                                              e.isCurrent
                                                  ? 'Present'
                                                  : (e.endDate ?? ''),
                                              style: metaStyle),
                                        ),
                                      ])
                                    : Text(e.dateRange, style: metaStyle),
                                const SizedBox(height: 3),
                                ...e.bullets
                                    .where((b) => b.isNotEmpty)
                                    .map((b) => Padding(
                                          padding: const EdgeInsets.only(
                                              top: 3, left: 10),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text('•  ',
                                                  style: bodyStyle),
                                              Expanded(
                                                child: _tappable(
                                                  onTapField: onTapField,
                                                  fieldId:
                                                      'experience[$idx].bullet.${e.bullets.indexOf(b)}',
                                                  value: b,
                                                  isAIPrefilled: e.isAIPrefilled,
                                                  child:
                                                      Text(b, style: bodyStyle),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )),
                              ],
                            ),
                          );
                        }),
                  ],
                  if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
                    mainHeader('CERTIFICATIONS'),
                    ...data.certifications.asMap().entries
                        .where((entry) => entry.value.name.isNotEmpty)
                        .map((entry) => _certEntryWidget(
                              entry.value,
                              entry.key,
                              entryTitleStyle,
                              metaStyle,
                              onTapField,
                            )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 12: PILLAR
// Vertical accent rule beside the name block. Creative/PR/media.
// ─────────────────────────────────────────────────────────────────────────────

class PillarTemplate extends StatelessWidget {
  const PillarTemplate({super.key, required this.data, this.onTapField});

  final ResumeRenderData data;
  final TapFieldFn? onTapField;

  static const _pillarAccent = Color(0xFFA8324A);

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 28,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );
    const titleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: _pillarAccent,
      letterSpacing: 0.4,
    );
    const sectionHeaderStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
      fontStyle: FontStyle.italic,
    );
    const bodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      height: 1.6,
      color: AppColors.primaryTextLight,
    );
    const metaStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10,
      color: AppColors.secondaryTextLight,
    );
    const entryTitleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );

    Widget header(String label) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(label, style: sectionHeaderStyle),
        );

    return Container(
      width: _pageWidth,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
          horizontal: _pagePaddingH, vertical: _pagePaddingV),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vertical accent rule
            Container(width: 3, color: _pillarAccent),
            const SizedBox(width: 20),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tappable(
                    onTapField: onTapField,
                    fieldId: 'contact.fullName',
                    value: data.contact.fullName,
                    child: Text(
                      data.contact.fullName.isNotEmpty
                          ? data.contact.fullName
                          : 'Your Name',
                      style: nameStyle,
                    ),
                  ),
                  if (data.contact.professionalTitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _tappable(
                      onTapField: onTapField,
                      fieldId: 'contact.professionalTitle',
                      value: data.contact.professionalTitle,
                      child: Text(
                          data.contact.professionalTitle.toUpperCase(),
                          style: titleStyle),
                    ),
                  ],
                  const SizedBox(height: 6),
                  _contactLineWidget(data.contact, metaStyle, onTapField),
                  if (data.summary.isNotEmpty) ...[
                    header('Summary'),
                    _tappable(
                      onTapField: onTapField,
                      fieldId: 'summary',
                      value: data.summary,
                      child: Text(data.summary, style: bodyStyle),
                    ),
                  ],
                  if (data.experience.any((e) => e.title.isNotEmpty)) ...[
                    header('Experience'),
                    ...data.experience.asMap().entries
                        .where((entry) => entry.value.title.isNotEmpty)
                        .map((entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _expEntryWidget(
                                entry.value,
                                entry.key,
                                entryTitleStyle,
                                metaStyle,
                                bodyStyle,
                                _pillarAccent,
                                '—  ',
                                onTapField,
                                separator: '  —  ',
                              ),
                            )),
                  ],
                  if (data.education.any((e) => e.institution.isNotEmpty)) ...[
                    header('Education'),
                    ...data.education.asMap().entries
                        .where((entry) => entry.value.institution.isNotEmpty)
                        .map((entry) => _eduEntryWidget(
                              entry.value,
                              entry.key,
                              entryTitleStyle,
                              metaStyle,
                              onTapField,
                            )),
                  ],
                  if (data.skills.isNotEmpty) ...[
                    header('Skills'),
                    _skillsWidget(data.skills, bodyStyle, onTapField),
                  ],
                  if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
                    header('Certifications'),
                    ...data.certifications.asMap().entries
                        .where((entry) => entry.value.name.isNotEmpty)
                        .map((entry) => _certEntryWidget(
                              entry.value,
                              entry.key,
                              entryTitleStyle,
                              metaStyle,
                              onTapField,
                            )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
