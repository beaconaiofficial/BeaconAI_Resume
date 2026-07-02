import 'package:flutter/material.dart';
import '../models/resume_sections.dart';
import '../theme/app_colors.dart';
import 'resume_template_renderer.dart' show ResumeRenderData, kResumePageWidth;

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2 Templates: Elevated, Federal, Academic, Veteran
//
// Same architecture as Phase 1 templates in resume_template_renderer.dart —
// stateless widgets rendering from the shared ResumeRenderData, fixed-width
// canvas at kResumePageWidth, tappable() helper for inline edit support.
//
// Design intent (from Template Picker "best for" labels):
//   Elevated — Marketing / HR: warm, modern, a touch of personality
//   Federal  — Government / Defense: maximally conservative, formal structure
//   Academic — Teachers / Researchers: publication-style, emphasis on
//              credentials and education ordering above experience
//   Veteran  — Military to Civilian: emphasizes rank/MOS translation context,
//              clean and authoritative without being flashy
// ─────────────────────────────────────────────────────────────────────────────

const double _pageWidth = kResumePageWidth;
const double _pagePaddingH = 48.0;
const double _pagePaddingV = 48.0;

typedef TapFieldFn = void Function(String fieldId, String currentValue);

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
          decoration:
              const BoxDecoration(color: Color(0xFF7C3AED), shape: BoxShape.circle),
        ),
      ),
    ],
  );
}

/// Returns the contact line as individually tappable fields in edit mode,
/// or a single plain-text line in view mode.
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
              Text('  —  ', style: titleStyle),
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

/// Experience entry row with separately tappable title/company/location/dates
/// and tappable bullets. Falls back to combined text in view mode.
Widget _expEntryWidget(
  ExperienceEntry e,
  int index,
  TextStyle titleStyle,
  TextStyle metaStyle,
  TextStyle bodyStyle,
  Color bulletColor,
  TapFieldFn? onTapField, {
  String separator = '  |  ',
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
                (e.company.isNotEmpty || e.location.isNotEmpty))
              Text(separator, style: titleStyle),
            if (e.company.isNotEmpty)
              _tappable(
                  onTapField: onTapField,
                  fieldId: 'experience[$index].company',
                  value: e.company,
                  isAIPrefilled: e.isAIPrefilled,
                  child: Text(e.company, style: titleStyle)),
            if (e.company.isNotEmpty && e.location.isNotEmpty)
              Text(separator, style: titleStyle),
            if (e.location.isNotEmpty)
              _tappable(
                  onTapField: onTapField,
                  fieldId: 'experience[$index].location',
                  value: e.location,
                  isAIPrefilled: e.isAIPrefilled,
                  child: Text(e.location, style: titleStyle)),
          ],
        )
      : Text(
          [e.title, e.company, e.location]
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
      const SizedBox(height: 3),
      ...e.bullets.where((b) => b.isNotEmpty).map((b) => Padding(
            padding: const EdgeInsets.only(top: 3, left: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: bodyStyle.copyWith(color: bulletColor)),
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

/// Skills list with individually tappable names in edit mode.
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

/// Skills displayed as pill chips (Elevated/Technical style).
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

// ─────────────────────────────────────────────────────────────────────────────
// Template 5: ELEVATED
// Marketing / HR. Warm accent, generous spacing, soft rounded section tags.
// ─────────────────────────────────────────────────────────────────────────────

class ElevatedTemplate extends StatelessWidget {
  const ElevatedTemplate({super.key, required this.data, this.onTapField});

  final ResumeRenderData data;
  final TapFieldFn? onTapField;

  static const _warmAccent = Color(0xFFB8754A);

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 27,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
    );
    const titleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: _warmAccent,
    );
    const sectionHeaderStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: _warmAccent,
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

    Widget sectionTag(String label) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _warmAccent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label, style: sectionHeaderStyle),
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
          const SizedBox(height: 8),
          _contactLineWidget(data.contact, metaStyle, onTapField),
          const SizedBox(height: 18),
          Container(height: 2, width: 56, color: _warmAccent),
          const SizedBox(height: 18),
          if (data.summary.isNotEmpty) ...[
            sectionTag('SUMMARY'),
            _tappable(
              onTapField: onTapField,
              fieldId: 'summary',
              value: data.summary,
              child: Text(data.summary, style: bodyStyle),
            ),
            const SizedBox(height: 18),
          ],
          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            sectionTag('EXPERIENCE'),
            ...data.experience
                .where((e) => e.title.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _expEntryWidget(
                        entry.value,
                        entry.key,
                        entryTitleStyle,
                        metaStyle,
                        bodyStyle,
                        _warmAccent,
                        onTapField,
                      ),
                    )),
            const SizedBox(height: 4),
          ],
          if (data.education.any((e) => e.institution.isNotEmpty)) ...[
            sectionTag('EDUCATION'),
            ...data.education
                .where((e) => e.institution.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => _EducationBlock(
                      e: entry.value,
                      index: entry.key,
                      titleStyle: entryTitleStyle,
                      metaStyle: metaStyle,
                      onTapField: onTapField,
                    )),
            const SizedBox(height: 4),
          ],
          if (data.skills.isNotEmpty) ...[
            sectionTag('SKILLS'),
            _skillChipsWidget(
              data.skills,
              bodyStyle,
              onTapField,
              _warmAccent.withValues(alpha: 0.35),
              radius: BorderRadius.circular(14),
            ),
            const SizedBox(height: 4),
          ],
          if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
            sectionTag('CERTIFICATIONS'),
            ...data.certifications
                .where((c) => c.name.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => _certEntryWidget(
                    entry.value, entry.key, entryTitleStyle, metaStyle, onTapField)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 6: FEDERAL
// Government / Defense. Maximally conservative — no color, formal labels,
// dense, every section explicitly labeled, double rules, serif throughout.
// ─────────────────────────────────────────────────────────────────────────────

class FederalTemplate extends StatelessWidget {
  const FederalTemplate({super.key, required this.data, this.onTapField});

  final ResumeRenderData data;
  final TapFieldFn? onTapField;

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: Colors.black,
    );
    const sectionHeaderStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Colors.black,
      letterSpacing: 0.4,
    );
    const bodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10.5,
      height: 1.5,
      color: Colors.black,
    );
    const metaStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 9.5,
      color: Color(0xFF333333),
    );
    const entryTitleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      color: Colors.black,
    );

    Widget federalHeader(String label) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: sectionHeaderStyle),
              const SizedBox(height: 3),
              Container(height: 1.5, color: Colors.black),
            ],
          ),
        );

    return Container(
      width: _pageWidth,
      color: Colors.white,
      padding:
          const EdgeInsets.symmetric(horizontal: _pagePaddingH, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                _tappable(
                  onTapField: onTapField,
                  fieldId: 'contact.fullName',
                  value: data.contact.fullName,
                  child: Text(
                    data.contact.fullName.isNotEmpty
                        ? data.contact.fullName.toUpperCase()
                        : 'YOUR NAME',
                    style: nameStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 4),
                _contactLineWidget(data.contact, metaStyle, onTapField,
                    centered: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 2, color: Colors.black),
          if (data.summary.isNotEmpty) ...[
            federalHeader('SUMMARY OF QUALIFICATIONS'),
            _tappable(
              onTapField: onTapField,
              fieldId: 'summary',
              value: data.summary,
              child: Text(data.summary, style: bodyStyle),
            ),
          ],
          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            federalHeader('PROFESSIONAL EXPERIENCE'),
            ...data.experience
                .where((e) => e.title.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _expEntryWidget(
                        entry.value,
                        entry.key,
                        entryTitleStyle,
                        metaStyle,
                        bodyStyle,
                        Colors.black,
                        onTapField,
                        separator: ', ',
                      ),
                    )),
          ],
          if (data.education.any((e) => e.institution.isNotEmpty)) ...[
            federalHeader('EDUCATION'),
            ...data.education
                .where((e) => e.institution.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) {
              final e = entry.value;
              final i = entry.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            children: [
                              _tappable(
                                  onTapField: onTapField,
                                  fieldId: 'education[$i].degree',
                                  value: e.degree,
                                  isAIPrefilled: e.isAIPrefilled,
                                  child: Text(e.degree, style: entryTitleStyle)),
                              if (e.fieldOfStudy.isNotEmpty) ...[
                                const Text(', ', style: entryTitleStyle),
                                _tappable(
                                    onTapField: onTapField,
                                    fieldId: 'education[$i].fieldOfStudy',
                                    value: e.fieldOfStudy,
                                    isAIPrefilled: e.isAIPrefilled,
                                    child: Text(e.fieldOfStudy,
                                        style: entryTitleStyle)),
                              ],
                              const Text(' — ', style: entryTitleStyle),
                              _tappable(
                                  onTapField: onTapField,
                                  fieldId: 'education[$i].institution',
                                  value: e.institution,
                                  isAIPrefilled: e.isAIPrefilled,
                                  child: Text(e.institution,
                                      style: entryTitleStyle)),
                            ],
                          ),
                          if (e.honors != null && e.honors!.isNotEmpty)
                            Text(
                              e.honors!,
                              style: metaStyle.copyWith(
                                  fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
                    _tappable(
                        onTapField: onTapField,
                        fieldId: 'education[$i].graduationYear',
                        value: e.graduationYear,
                        isAIPrefilled: e.isAIPrefilled,
                        child: Text(e.graduationYear, style: metaStyle)),
                  ],
                ),
              );
            }),
          ],
          if (data.skills.isNotEmpty) ...[
            federalHeader('SKILLS AND COMPETENCIES'),
            _skillsWidget(data.skills, bodyStyle, onTapField),
          ],
          if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
            federalHeader('CERTIFICATIONS AND CLEARANCES'),
            ...data.certifications
                .where((c) => c.name.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) {
              final c = entry.value;
              final i = entry.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  children: [
                    _tappable(
                        onTapField: onTapField,
                        fieldId: 'certifications[$i].name',
                        value: c.name,
                        isAIPrefilled: c.isAIPrefilled,
                        child: Text(c.name, style: bodyStyle)),
                    const Text(', ', style: bodyStyle),
                    _tappable(
                        onTapField: onTapField,
                        fieldId: 'certifications[$i].issuer',
                        value: c.issuer,
                        isAIPrefilled: c.isAIPrefilled,
                        child: Text(c.issuer, style: bodyStyle)),
                    const Text(', ', style: bodyStyle),
                    _tappable(
                        onTapField: onTapField,
                        fieldId: 'certifications[$i].dateEarned',
                        value: c.dateEarned,
                        isAIPrefilled: c.isAIPrefilled,
                        child: Text(c.dateEarned, style: bodyStyle)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 7: ACADEMIC
// Teachers / Researchers. Publication-style. Education appears before
// Experience. Certifications relabeled as "Credentials". Quiet, dense.
// ─────────────────────────────────────────────────────────────────────────────

class AcademicTemplate extends StatelessWidget {
  const AcademicTemplate({super.key, required this.data, this.onTapField});

  final ResumeRenderData data;
  final TapFieldFn? onTapField;

  static const _academicAccent = Color(0xFF4A5D6B);

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 26,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );
    const titleStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 13,
      fontStyle: FontStyle.italic,
      color: _academicAccent,
    );
    const sectionHeaderStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: _academicAccent,
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
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );

    Widget header(String label) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: sectionHeaderStyle),
              const SizedBox(height: 4),
              Container(height: 0.8, color: AppColors.borderLight),
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

          // Education comes FIRST — publication/academic convention
          if (data.education.any((e) => e.institution.isNotEmpty)) ...[
            header('EDUCATION'),
            ...data.education
                .where((e) => e.institution.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) {
              final e = entry.value;
              final i = entry.key;
              final italicMeta =
                  metaStyle.copyWith(fontStyle: FontStyle.italic);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            children: [
                              if (e.degree.isNotEmpty)
                                _tappable(
                                    onTapField: onTapField,
                                    fieldId: 'education[$i].degree',
                                    value: e.degree,
                                    isAIPrefilled: e.isAIPrefilled,
                                    child: Text(e.degree,
                                        style: entryTitleStyle)),
                              if (e.degree.isNotEmpty &&
                                  e.fieldOfStudy.isNotEmpty)
                                const Text(', ', style: entryTitleStyle),
                              if (e.fieldOfStudy.isNotEmpty)
                                _tappable(
                                    onTapField: onTapField,
                                    fieldId: 'education[$i].fieldOfStudy',
                                    value: e.fieldOfStudy,
                                    isAIPrefilled: e.isAIPrefilled,
                                    child: Text(e.fieldOfStudy,
                                        style: entryTitleStyle)),
                            ],
                          ),
                          _tappable(
                              onTapField: onTapField,
                              fieldId: 'education[$i].institution',
                              value: e.institution,
                              isAIPrefilled: e.isAIPrefilled,
                              child: Text(e.institution, style: italicMeta)),
                          if (e.honors != null && e.honors!.isNotEmpty)
                            Text(
                              e.honors!,
                              style: metaStyle.copyWith(
                                  fontStyle: FontStyle.italic),
                            ),
                          if (e.gpa != null && e.gpa!.isNotEmpty)
                            _tappable(
                                onTapField: onTapField,
                                fieldId: 'education[$i].gpa',
                                value: e.gpa!,
                                child: Text('GPA: ${e.gpa}', style: metaStyle)),
                        ],
                      ),
                    ),
                    _tappable(
                        onTapField: onTapField,
                        fieldId: 'education[$i].graduationYear',
                        value: e.graduationYear,
                        isAIPrefilled: e.isAIPrefilled,
                        child: Text(e.graduationYear, style: metaStyle)),
                  ],
                ),
              );
            }),
          ],

          if (data.summary.isNotEmpty) ...[
            header('RESEARCH & TEACHING SUMMARY'),
            _tappable(
              onTapField: onTapField,
              fieldId: 'summary',
              value: data.summary,
              child: Text(data.summary, style: bodyStyle),
            ),
          ],

          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            header('EXPERIENCE'),
            ...data.experience
                .where((e) => e.title.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _expEntryWidget(
                        entry.value,
                        entry.key,
                        entryTitleStyle,
                        metaStyle,
                        bodyStyle,
                        _academicAccent,
                        onTapField,
                        separator: ', ',
                      ),
                    )),
          ],

          if (data.skills.isNotEmpty) ...[
            header('AREAS OF EXPERTISE'),
            _skillsWidget(data.skills, bodyStyle, onTapField),
          ],

          // Certifications relabeled "Credentials" for academic context
          if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
            header('CREDENTIALS'),
            ...data.certifications
                .where((c) => c.name.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) {
              final c = entry.value;
              final i = entry.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        children: [
                          _tappable(
                              onTapField: onTapField,
                              fieldId: 'certifications[$i].name',
                              value: c.name,
                              isAIPrefilled: c.isAIPrefilled,
                              child: Text(c.name, style: entryTitleStyle)),
                          const Text(', ', style: entryTitleStyle),
                          _tappable(
                              onTapField: onTapField,
                              fieldId: 'certifications[$i].issuer',
                              value: c.issuer,
                              isAIPrefilled: c.isAIPrefilled,
                              child: Text(c.issuer, style: entryTitleStyle)),
                        ],
                      ),
                    ),
                    _tappable(
                        onTapField: onTapField,
                        fieldId: 'certifications[$i].dateEarned',
                        value: c.dateEarned,
                        isAIPrefilled: c.isAIPrefilled,
                        child: Text(c.dateEarned, style: metaStyle)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 8: VETERAN
// Military-to-Civilian. Authoritative, clean, structured rank-and-file feel.
// Dedicated "Military Training" sub-section under Education per spec §9.
// ─────────────────────────────────────────────────────────────────────────────

class VeteranTemplate extends StatelessWidget {
  const VeteranTemplate({super.key, required this.data, this.onTapField});

  final ResumeRenderData data;
  final TapFieldFn? onTapField;

  static const _veteranNavy = Color(0xFF1B2A4A);

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 25,
      fontWeight: FontWeight.w800,
      color: _veteranNavy,
      letterSpacing: -0.3,
    );
    const titleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: AppColors.secondaryTextLight,
    );
    const sectionHeaderStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
      color: Colors.white,
    );
    const bodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      height: 1.5,
      color: AppColors.primaryTextLight,
    );
    const metaStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10,
      color: AppColors.secondaryTextLight,
    );
    const entryTitleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
    );

    Widget bannerHeader(String label) => Container(
          margin: const EdgeInsets.only(top: 16, bottom: 10),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          color: _veteranNavy,
          child: Text(label, style: sectionHeaderStyle),
        );

    return Container(
      width: _pageWidth,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(
          _pagePaddingH, _pagePaddingV, _pagePaddingH, _pagePaddingV),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tappable(
            onTapField: onTapField,
            fieldId: 'contact.fullName',
            value: data.contact.fullName,
            child: Text(
              data.contact.fullName.isNotEmpty
                  ? data.contact.fullName.toUpperCase()
                  : 'YOUR NAME',
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
          Container(height: 3, color: _veteranNavy),
          if (data.summary.isNotEmpty) ...[
            bannerHeader('PROFESSIONAL SUMMARY'),
            _tappable(
              onTapField: onTapField,
              fieldId: 'summary',
              value: data.summary,
              child: Text(data.summary, style: bodyStyle),
            ),
          ],
          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            bannerHeader('PROFESSIONAL EXPERIENCE'),
            ...data.experience
                .where((e) => e.title.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _expEntryWidget(
                        entry.value,
                        entry.key,
                        entryTitleStyle,
                        metaStyle,
                        bodyStyle,
                        _veteranNavy,
                        onTapField,
                      ),
                    )),
          ],
          if (data.education.any((e) => e.institution.isNotEmpty)) ...[
            bannerHeader('EDUCATION & TRAINING'),
            ...data.education
                .where((e) => e.institution.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) {
              final e = entry.value;
              final i = entry.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _tappable(
                              onTapField: onTapField,
                              fieldId: 'education[$i].institution',
                              value: e.institution,
                              isAIPrefilled: e.isAIPrefilled,
                              child: Text(e.institution, style: entryTitleStyle)),
                          if (e.degree.isNotEmpty || e.fieldOfStudy.isNotEmpty)
                            Wrap(
                              children: [
                                if (e.degree.isNotEmpty)
                                  _tappable(
                                      onTapField: onTapField,
                                      fieldId: 'education[$i].degree',
                                      value: e.degree,
                                      isAIPrefilled: e.isAIPrefilled,
                                      child: Text(e.degree, style: metaStyle)),
                                if (e.degree.isNotEmpty &&
                                    e.fieldOfStudy.isNotEmpty)
                                  const Text(', ', style: metaStyle),
                                if (e.fieldOfStudy.isNotEmpty)
                                  _tappable(
                                      onTapField: onTapField,
                                      fieldId: 'education[$i].fieldOfStudy',
                                      value: e.fieldOfStudy,
                                      isAIPrefilled: e.isAIPrefilled,
                                      child: Text(e.fieldOfStudy,
                                          style: metaStyle)),
                              ],
                            ),
                          if (e.honors != null && e.honors!.isNotEmpty)
                            Text(
                              e.honors!,
                              style: metaStyle.copyWith(
                                  fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
                    _tappable(
                        onTapField: onTapField,
                        fieldId: 'education[$i].graduationYear',
                        value: e.graduationYear,
                        isAIPrefilled: e.isAIPrefilled,
                        child: Text(e.graduationYear, style: metaStyle)),
                  ],
                ),
              );
            }),
          ],
          if (data.skills.isNotEmpty) ...[
            bannerHeader('CORE COMPETENCIES'),
            _skillChipsWidget(
              data.skills,
              bodyStyle,
              onTapField,
              _veteranNavy.withValues(alpha: 0.4),
              radius: BorderRadius.zero,
            ),
          ],
          if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
            bannerHeader('CERTIFICATIONS'),
            ...data.certifications
                .where((c) => c.name.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => _certEntryWidget(
                    entry.value, entry.key, entryTitleStyle, metaStyle, onTapField)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared experience/education block widgets (used by Elevated template)
// ─────────────────────────────────────────────────────────────────────────────

class _EducationBlock extends StatelessWidget {
  const _EducationBlock({
    required this.e,
    required this.index,
    required this.titleStyle,
    required this.metaStyle,
    required this.onTapField,
  });

  final EducationEntry e;
  final int index;
  final TextStyle titleStyle;
  final TextStyle metaStyle;
  final TapFieldFn? onTapField;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
                  child: Text(e.institution, style: titleStyle),
                ),
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
              ],
            ),
          ),
          _tappable(
            onTapField: onTapField,
            fieldId: 'education[$index].graduationYear',
            value: e.graduationYear,
            isAIPrefilled: e.isAIPrefilled,
            child: Text(e.graduationYear, style: metaStyle),
          ),
        ],
      ),
    );
  }
}
