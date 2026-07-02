import 'dart:convert';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/resume.dart';
import '../models/resume_sections.dart';
import '../services/hive_service.dart';
import '../theme/app_colors.dart';
import 'phase2_templates.dart';
import 'phase3_templates.dart';

/// US Letter page width in logical pixels — used by renderer and preview scroller.
const double kResumePageWidth = 816.0;

/// US Letter page height in logical pixels.
const double kResumePageHeight = 1056.0;

// ─────────────────────────────────────────────────────────────────────────────
// ResumeTemplateRenderer
//
// Renders a resume using the selected template as a Flutter widget tree.
// Phase 1 templates: Classic, Clean, Sharp, Entry.
// All render from the same underlying resume data — template is display only.
//
// Spec §11 ATS Export Rule:
//   PDF always generated from single-column content regardless of template.
//   Plain text ignores layout entirely.
//   The renderer here is for on-screen preview and inline editing only.
// ─────────────────────────────────────────────────────────────────────────────

class ResumeTemplateRenderer extends StatelessWidget {
  const ResumeTemplateRenderer({
    super.key,
    required this.resume,
    required this.data,
    this.onTapField,
    this.scaleFactor = 1.0,
  });

  final Resume resume;
  final ResumeRenderData data;

  /// Called when the user taps a field for inline editing.
  /// Passes the field identifier so the parent knows what to edit.
  final void Function(String fieldId, String currentValue)? onTapField;

  /// Scale factor for fitting the resume inside a constrained preview area.
  final double scaleFactor;

  @override
  Widget build(BuildContext context) {
    final template = switch (resume.templateId) {
      AppConstants.templateClassic =>
        _ClassicTemplate(data: data, onTapField: onTapField),
      AppConstants.templateSharp =>
        _SharpTemplate(data: data, onTapField: onTapField),
      AppConstants.templateEntry =>
        _EntryTemplate(data: data, onTapField: onTapField),
      AppConstants.templateElevated =>
        ElevatedTemplate(data: data, onTapField: onTapField),
      AppConstants.templateFederal =>
        FederalTemplate(data: data, onTapField: onTapField),
      AppConstants.templateAcademic =>
        AcademicTemplate(data: data, onTapField: onTapField),
      AppConstants.templateVeteran =>
        VeteranTemplate(data: data, onTapField: onTapField),
      AppConstants.templateTechnical =>
        TechnicalTemplate(data: data, onTapField: onTapField),
      AppConstants.templateHorizon => HorizonTemplate(
          data: data,
          onTapField: onTapField,
          accentColorHex: resume.templateAccentColor),
      AppConstants.templateSidebar =>
        SidebarTemplate(data: data, onTapField: onTapField),
      AppConstants.templatePillar =>
        PillarTemplate(data: data, onTapField: onTapField),
      _ => _CleanTemplate(data: data, onTapField: onTapField),
    };

    if (scaleFactor == 1.0) return template;

    return Transform.scale(
      scale: scaleFactor,
      alignment: Alignment.topCenter,
      child: template,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ResumeRenderData
// Typed, decoded section data passed to templates.
// Loaded once by the parent and passed down — templates are stateless.
// ─────────────────────────────────────────────────────────────────────────────

class ResumeRenderData {
  const ResumeRenderData({
    required this.contact,
    required this.summary,
    required this.experience,
    required this.education,
    required this.skills,
    required this.certifications,
  });

  final ContactInfo contact;
  final String summary;
  final List<ExperienceEntry> experience;
  final List<EducationEntry> education;
  final List<SkillEntry> skills;
  final List<CertificationEntry> certifications;

  /// Load all resume sections from Hive and decode into typed data.
  static ResumeRenderData fromHive(String resumeId) {
    ContactInfo contact = ContactInfo();
    String summary = '';
    List<ExperienceEntry> experience = [];
    List<EducationEntry> education = [];
    List<SkillEntry> skills = [];
    List<CertificationEntry> certifications = [];

    final box = HiveService.resumeSectionBox;

    try {
      final contactSection = box.get('${resumeId}_contact');
      if (contactSection != null) {
        contact = ContactInfo.fromJson(
            jsonDecode(contactSection.data) as Map<String, dynamic>);
      }
    } catch (_) {}

    try {
      final summarySection = box.get('${resumeId}_summary');
      if (summarySection != null) {
        final decoded = jsonDecode(summarySection.data) as Map<String, dynamic>;
        summary = decoded['text'] as String? ?? '';
      }
    } catch (_) {}

    try {
      final expSection = box.get('${resumeId}_experience');
      if (expSection != null) {
        final list = jsonDecode(expSection.data) as List<dynamic>;
        experience = list
            .map((e) => ExperienceEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    try {
      final eduSection = box.get('${resumeId}_education');
      if (eduSection != null) {
        final list = jsonDecode(eduSection.data) as List<dynamic>;
        education = list
            .map((e) => EducationEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    try {
      final skillsSection = box.get('${resumeId}_skills');
      if (skillsSection != null) {
        final list = jsonDecode(skillsSection.data) as List<dynamic>;
        skills = list
            .map((e) => SkillEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    try {
      final certSection = box.get('${resumeId}_certifications');
      if (certSection != null) {
        final list = jsonDecode(certSection.data) as List<dynamic>;
        certifications = list
            .map((e) => CertificationEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    return ResumeRenderData(
      contact: contact,
      summary: summary,
      experience: experience,
      education: education,
      skills: skills,
      certifications: certifications,
    );
  }

  bool get isEmpty =>
      contact.fullName.isEmpty &&
      summary.isEmpty &&
      experience.isEmpty &&
      education.isEmpty &&
      skills.isEmpty &&
      certifications.isEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// Base template scaffold — shared by all Phase 1 templates
// ─────────────────────────────────────────────────────────────────────────────

abstract class _BaseTemplate extends StatelessWidget {
  const _BaseTemplate({required this.data, this.onTapField});

  final ResumeRenderData data;
  final void Function(String fieldId, String currentValue)? onTapField;

  static const double pagePaddingH = 48.0;
  static const double pagePaddingV = 48.0;

  /// Wraps a widget in a tap gesture for inline editing.
  /// When [isAIPrefilled] is true and edit mode is active, shows a small
  /// purple dot badge to indicate Claude-generated content.
  Widget tappable({
    required String fieldId,
    required String value,
    required Widget child,
    bool isAIPrefilled = false,
  }) {
    if (onTapField == null) return child;
    final Widget core = GestureDetector(
      onTap: () => onTapField!(fieldId, value),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(2)),
        child: child,
      ),
    );
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
              color: AppColors.aiIndicator,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

  /// Renders a single experience entry — shared across templates.
  Widget experienceEntry(
    ExperienceEntry e,
    TextStyle titleStyle,
    TextStyle metaStyle,
    TextStyle bulletStyle,
    Color bulletColor,
    int index,
  ) {
    // In edit mode: show each sub-field as a separate tappable element so
    // title, company, location, and dates can all be edited independently.
    // In view mode: restore the original single-Text layout for visual fidelity.
    final Widget titleArea = onTapField != null
        ? Wrap(
            children: [
              if (e.title.isNotEmpty)
                tappable(
                  fieldId: 'experience[$index].title',
                  value: e.title,
                  isAIPrefilled: e.isAIPrefilled,
                  child: Text(e.title, style: titleStyle),
                ),
              if (e.title.isNotEmpty &&
                  (e.company.isNotEmpty || e.location.isNotEmpty))
                Text('  |  ', style: titleStyle),
              if (e.company.isNotEmpty)
                tappable(
                  fieldId: 'experience[$index].company',
                  value: e.company,
                  isAIPrefilled: e.isAIPrefilled,
                  child: Text(e.company, style: titleStyle),
                ),
              if (e.company.isNotEmpty && e.location.isNotEmpty)
                Text('  |  ', style: titleStyle),
              if (e.location.isNotEmpty)
                tappable(
                  fieldId: 'experience[$index].location',
                  value: e.location,
                  isAIPrefilled: e.isAIPrefilled,
                  child: Text(e.location, style: titleStyle),
                ),
            ],
          )
        : Text(
            [e.title, e.company, e.location]
                .where((s) => s.isNotEmpty)
                .join('  |  '),
            style: titleStyle,
          );

    final Widget dateArea = onTapField != null
        ? Wrap(
            children: [
              tappable(
                fieldId: 'experience[$index].startDate',
                value: e.startDate,
                child: Text(e.startDate, style: metaStyle),
              ),
              Text(' – ', style: metaStyle),
              tappable(
                fieldId: 'experience[$index].endDate',
                value: e.isCurrent ? 'Present' : (e.endDate ?? ''),
                child: Text(
                    e.isCurrent ? 'Present' : (e.endDate ?? ''), style: metaStyle),
              ),
            ],
          )
        : Text(e.dateRange, style: metaStyle);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
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
          const SizedBox(height: 4),
          ...e.bullets.where((b) => b.isNotEmpty).map((b) => Padding(
                padding: const EdgeInsets.only(top: 3, left: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ',
                        style: bulletStyle.copyWith(color: bulletColor)),
                    Expanded(
                      child: tappable(
                        fieldId:
                            'experience[$index].bullet.${e.bullets.indexOf(b)}',
                        value: b,
                        isAIPrefilled: e.isAIPrefilled,
                        child: Text(b, style: bulletStyle),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  /// Renders a single education entry — shared across templates.
  Widget educationEntry(
    EducationEntry e,
    TextStyle titleStyle,
    TextStyle metaStyle,
    int index,
  ) {
    final Widget degreeRow;
    if (e.degree.isNotEmpty || e.fieldOfStudy.isNotEmpty) {
      degreeRow = onTapField != null
          ? Wrap(
              children: [
                if (e.degree.isNotEmpty)
                  tappable(
                    fieldId: 'education[$index].degree',
                    value: e.degree,
                    isAIPrefilled: e.isAIPrefilled,
                    child: Text(e.degree, style: metaStyle),
                  ),
                if (e.degree.isNotEmpty && e.fieldOfStudy.isNotEmpty)
                  Text(', ', style: metaStyle),
                if (e.fieldOfStudy.isNotEmpty)
                  tappable(
                    fieldId: 'education[$index].fieldOfStudy',
                    value: e.fieldOfStudy,
                    isAIPrefilled: e.isAIPrefilled,
                    child: Text(e.fieldOfStudy, style: metaStyle),
                  ),
              ],
            )
          : Text(
              [e.degree, e.fieldOfStudy].where((s) => s.isNotEmpty).join(', '),
              style: metaStyle,
            );
    } else {
      degreeRow = const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tappable(
                  fieldId: 'education[$index].institution',
                  value: e.institution,
                  isAIPrefilled: e.isAIPrefilled,
                  child: Text(e.institution, style: titleStyle),
                ),
                if (e.degree.isNotEmpty || e.fieldOfStudy.isNotEmpty)
                  degreeRow,
                if (e.honors != null && e.honors!.isNotEmpty)
                  Text(
                    e.honors!,
                    style: metaStyle.copyWith(fontStyle: FontStyle.italic),
                  ),
                if (e.gpa != null && e.gpa!.isNotEmpty)
                  tappable(
                    fieldId: 'education[$index].gpa',
                    value: e.gpa!,
                    child: Text('GPA: ${e.gpa}', style: metaStyle),
                  ),
              ],
            ),
          ),
          tappable(
            fieldId: 'education[$index].graduationYear',
            value: e.graduationYear,
            isAIPrefilled: e.isAIPrefilled,
            child: Text(e.graduationYear, style: metaStyle),
          ),
        ],
      ),
    );
  }

  /// Contact line: in edit mode each field is individually tappable.
  Widget _contactLineWidget(ContactInfo c, TextStyle style,
      {bool centered = false}) {
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
    if (c.cityState.isNotEmpty) {
      fields.add((id: 'contact.cityState', value: c.cityState));
    }
    if (c.phone.isNotEmpty) {
      fields.add((id: 'contact.phone', value: c.phone));
    }
    if (c.email.isNotEmpty) {
      fields.add((id: 'contact.email', value: c.email));
    }
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
      children.add(tappable(
        fieldId: fields[i].id,
        value: fields[i].value,
        child: Text(fields[i].value, style: style),
      ));
      if (i < fields.length - 1) children.add(Text('   |   ', style: style));
    }
    return Wrap(
      alignment: centered ? WrapAlignment.center : WrapAlignment.start,
      children: children,
    );
  }

  /// Skills: in edit mode each chip is individually tappable.
  Widget tappableSkillsWrap(List<SkillEntry> skills, TextStyle style) {
    if (onTapField == null) {
      return Text(skills.map((s) => s.name).join('   ·   '), style: style);
    }
    final children = <Widget>[];
    for (int i = 0; i < skills.length; i++) {
      children.add(tappable(
        fieldId: 'skills[$i]',
        value: skills[i].name,
        isAIPrefilled: skills[i].isAIPrefilled,
        child: Text(skills[i].name, style: style),
      ));
      if (i < skills.length - 1) {
        children.add(Text('   ·   ', style: style));
      }
    }
    return Wrap(children: children);
  }

  /// Single certification row with tappable name, issuer, and date.
  Widget certEntry(CertificationEntry c, TextStyle titleStyle,
      TextStyle metaStyle, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              children: [
                tappable(
                  fieldId: 'certifications[$index].name',
                  value: c.name,
                  isAIPrefilled: c.isAIPrefilled,
                  child: Text(c.name, style: titleStyle),
                ),
                Text('  —  ', style: titleStyle),
                tappable(
                  fieldId: 'certifications[$index].issuer',
                  value: c.issuer,
                  isAIPrefilled: c.isAIPrefilled,
                  child: Text(c.issuer, style: titleStyle),
                ),
              ],
            ),
          ),
          tappable(
            fieldId: 'certifications[$index].dateEarned',
            value: c.dateEarned,
            isAIPrefilled: c.isAIPrefilled,
            child: Text(c.dateEarned, style: metaStyle),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 1: CLEAN
// Sans-serif throughout, generous white space, safest ATS layout.
// ─────────────────────────────────────────────────────────────────────────────

class _CleanTemplate extends _BaseTemplate {
  const _CleanTemplate({required super.data, super.onTapField});

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
      height: 1.2,
    );
    const titleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 13,
      color: AppColors.secondaryTextLight,
    );
    const sectionHeaderStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: AppColors.accentLightColor,
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
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );

    return Container(
      width: kResumePageWidth,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: _BaseTemplate.pagePaddingH,
        vertical: _BaseTemplate.pagePaddingV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Contact header ────────────────────────────────────────────────
          tappable(
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
            const SizedBox(height: 2),
            tappable(
              fieldId: 'contact.professionalTitle',
              value: data.contact.professionalTitle,
              child: Text(data.contact.professionalTitle, style: titleStyle),
            ),
          ],
          const SizedBox(height: 6),
          _contactLineWidget(data.contact, metaStyle),
          const SizedBox(height: 20),
          const Divider(color: AppColors.borderLight, height: 1),
          const SizedBox(height: 16),

          // ── Summary ───────────────────────────────────────────────────────
          if (data.summary.isNotEmpty) ...[
            _sectionHeader('SUMMARY', sectionHeaderStyle),
            tappable(
              fieldId: 'summary',
              value: data.summary,
              child: Text(data.summary, style: bodyStyle),
            ),
            _sectionSpacer(),
          ],

          // ── Experience ────────────────────────────────────────────────────
          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            _sectionHeader('EXPERIENCE', sectionHeaderStyle),
            ...data.experience
                .where((e) => e.title.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => experienceEntry(
                      entry.value,
                      entryTitleStyle,
                      metaStyle,
                      bodyStyle,
                      AppColors.secondaryTextLight,
                      entry.key,
                    )),
            _sectionSpacer(),
          ],

          // ── Education ─────────────────────────────────────────────────────
          if (data.education.any((e) => e.institution.isNotEmpty)) ...[
            _sectionHeader('EDUCATION', sectionHeaderStyle),
            ...data.education
                .where((e) => e.institution.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => educationEntry(
                      entry.value,
                      entryTitleStyle,
                      metaStyle,
                      entry.key,
                    )),
            _sectionSpacer(),
          ],

          // ── Skills ────────────────────────────────────────────────────────
          if (data.skills.isNotEmpty) ...[
            _sectionHeader('SKILLS', sectionHeaderStyle),
            tappableSkillsWrap(data.skills, bodyStyle),
            _sectionSpacer(),
          ],

          // ── Certifications ────────────────────────────────────────────────
          if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
            _sectionHeader('CERTIFICATIONS', sectionHeaderStyle),
            ...data.certifications
                .where((c) => c.name.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) =>
                    certEntry(entry.value, entryTitleStyle, metaStyle, entry.key)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 2: CLASSIC
// Serif header, horizontal rule dividers, traditional section order.
// ─────────────────────────────────────────────────────────────────────────────

class _ClassicTemplate extends _BaseTemplate {
  const _ClassicTemplate({required super.data, super.onTapField});

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
      height: 1.2,
    );
    const titleStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 13,
      fontStyle: FontStyle.italic,
      color: AppColors.secondaryTextLight,
    );
    const sectionHeaderStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
      letterSpacing: 0.5,
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
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );

    return Container(
      width: kResumePageWidth,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: _BaseTemplate.pagePaddingH,
        vertical: _BaseTemplate.pagePaddingV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Centered contact header ───────────────────────────────────────
          Center(
            child: Column(
              children: [
                tappable(
                  fieldId: 'contact.fullName',
                  value: data.contact.fullName,
                  child: Text(
                    data.contact.fullName.isNotEmpty
                        ? data.contact.fullName
                        : 'Your Name',
                    style: nameStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (data.contact.professionalTitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  tappable(
                    fieldId: 'contact.professionalTitle',
                    value: data.contact.professionalTitle,
                    child: Text(data.contact.professionalTitle, style: titleStyle),
                  ),
                ],
                const SizedBox(height: 6),
                _contactLineWidget(data.contact, metaStyle, centered: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(
              color: AppColors.primaryTextLight, height: 1, thickness: 1.5),
          const SizedBox(height: 4),
          const Divider(color: AppColors.primaryTextLight, height: 1),
          const SizedBox(height: 16),

          // Sections
          if (data.summary.isNotEmpty) ...[
            _classicSectionHeader('PROFESSIONAL SUMMARY', sectionHeaderStyle),
            tappable(
              fieldId: 'summary',
              value: data.summary,
              child: Text(data.summary, style: bodyStyle),
            ),
            _sectionSpacer(),
          ],
          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            _classicSectionHeader(
                'PROFESSIONAL EXPERIENCE', sectionHeaderStyle),
            ...data.experience
                .where((e) => e.title.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => experienceEntry(
                      entry.value,
                      entryTitleStyle,
                      metaStyle,
                      bodyStyle,
                      AppColors.secondaryTextLight,
                      entry.key,
                    )),
            _sectionSpacer(),
          ],
          if (data.education.any((e) => e.institution.isNotEmpty)) ...[
            _classicSectionHeader('EDUCATION', sectionHeaderStyle),
            ...data.education
                .where((e) => e.institution.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => educationEntry(
                      entry.value,
                      entryTitleStyle,
                      metaStyle,
                      entry.key,
                    )),
            _sectionSpacer(),
          ],
          if (data.skills.isNotEmpty) ...[
            _classicSectionHeader('SKILLS', sectionHeaderStyle),
            tappableSkillsWrap(data.skills, bodyStyle),
            _sectionSpacer(),
          ],
          if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
            _classicSectionHeader('CERTIFICATIONS', sectionHeaderStyle),
            ...data.certifications
                .where((c) => c.name.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) =>
                    certEntry(entry.value, entryTitleStyle, metaStyle, entry.key)),
          ],
        ],
      ),
    );
  }

  Widget _classicSectionHeader(String title, TextStyle style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: style),
        const SizedBox(height: 4),
        const Divider(color: AppColors.borderLight, height: 1),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 3: SHARP
// Bold all-caps headers, tight spacing, high density. Corporate/banking.
// ─────────────────────────────────────────────────────────────────────────────

class _SharpTemplate extends _BaseTemplate {
  const _SharpTemplate({required super.data, super.onTapField});

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 24,
      fontWeight: FontWeight.w800,
      color: AppColors.primaryTextLight,
      letterSpacing: -0.5,
    );
    const titleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AppColors.secondaryTextLight,
    );
    const sectionHeaderStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 2.0,
      color: AppColors.primaryTextLight,
    );
    const bodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10.5,
      height: 1.45,
      color: AppColors.primaryTextLight,
    );
    const metaStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 9.5,
      color: AppColors.secondaryTextLight,
    );
    const entryTitleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
    );

    return Container(
      width: kResumePageWidth,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: _BaseTemplate.pagePaddingH,
        vertical: 40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header — left-aligned, tight ──────────────────────────────────
          tappable(
            fieldId: 'contact.fullName',
            value: data.contact.fullName,
            child: Text(
              data.contact.fullName.isNotEmpty
                  ? data.contact.fullName.toUpperCase()
                  : 'YOUR NAME',
              style: nameStyle,
            ),
          ),
          if (data.contact.professionalTitle.isNotEmpty)
            tappable(
              fieldId: 'contact.professionalTitle',
              value: data.contact.professionalTitle,
              child: Text(data.contact.professionalTitle, style: titleStyle),
            ),
          const SizedBox(height: 4),
          _contactLineWidget(data.contact, metaStyle),
          const SizedBox(height: 12),
          Container(height: 2, color: AppColors.primaryTextLight),
          const SizedBox(height: 12),

          // Sections — tighter spacing throughout
          if (data.summary.isNotEmpty) ...[
            _sharpHeader('SUMMARY', sectionHeaderStyle),
            tappable(
              fieldId: 'summary',
              value: data.summary,
              child: Text(data.summary, style: bodyStyle),
            ),
            const SizedBox(height: 12),
          ],
          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            _sharpHeader('EXPERIENCE', sectionHeaderStyle),
            ...data.experience
                .where((e) => e.title.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => experienceEntry(
                      entry.value,
                      entryTitleStyle,
                      metaStyle,
                      bodyStyle,
                      AppColors.secondaryTextLight,
                      entry.key,
                    )),
            const SizedBox(height: 12),
          ],
          if (data.education.any((e) => e.institution.isNotEmpty)) ...[
            _sharpHeader('EDUCATION', sectionHeaderStyle),
            ...data.education
                .where((e) => e.institution.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => educationEntry(
                      entry.value,
                      entryTitleStyle,
                      metaStyle,
                      entry.key,
                    )),
            const SizedBox(height: 12),
          ],
          if (data.skills.isNotEmpty) ...[
            _sharpHeader('SKILLS', sectionHeaderStyle),
            tappableSkillsWrap(data.skills, bodyStyle),
            const SizedBox(height: 12),
          ],
          if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
            _sharpHeader('CERTIFICATIONS', sectionHeaderStyle),
            ...data.certifications
                .where((c) => c.name.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) =>
                    certEntry(entry.value, entryTitleStyle, metaStyle, entry.key)),
          ],
        ],
      ),
    );
  }

  Widget _sharpHeader(String title, TextStyle style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: style),
        const SizedBox(height: 3),
        const Divider(
            color: AppColors.primaryTextLight, height: 1, thickness: 0.8),
        const SizedBox(height: 6),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 4: ENTRY
// Education + skills above experience. Best for new graduates/interns.
// ─────────────────────────────────────────────────────────────────────────────

class _EntryTemplate extends _BaseTemplate {
  const _EntryTemplate({required super.data, super.onTapField});

  @override
  Widget build(BuildContext context) {
    // Same visual style as Clean but section ORDER is different:
    // Contact → Summary → Education → Skills → Experience → Certifications
    const nameStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
    );
    const titleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      color: AppColors.secondaryTextLight,
    );
    const sectionHeaderStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: AppColors.accentLightColor,
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
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );

    return Container(
      width: kResumePageWidth,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: _BaseTemplate.pagePaddingH,
        vertical: _BaseTemplate.pagePaddingV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tappable(
            fieldId: 'contact.fullName',
            value: data.contact.fullName,
            child: Text(
              data.contact.fullName.isNotEmpty
                  ? data.contact.fullName
                  : 'Your Name',
              style: nameStyle,
            ),
          ),
          if (data.contact.professionalTitle.isNotEmpty)
            tappable(
              fieldId: 'contact.professionalTitle',
              value: data.contact.professionalTitle,
              child: Text(data.contact.professionalTitle, style: titleStyle),
            ),
          const SizedBox(height: 6),
          _contactLineWidget(data.contact, metaStyle),
          const SizedBox(height: 16),
          const Divider(color: AppColors.borderLight, height: 1),
          const SizedBox(height: 14),

          // Entry-specific order: Education and Skills FIRST
          if (data.summary.isNotEmpty) ...[
            _sectionHeader('SUMMARY', sectionHeaderStyle),
            tappable(
              fieldId: 'summary',
              value: data.summary,
              child: Text(data.summary, style: bodyStyle),
            ),
            _sectionSpacer(),
          ],
          if (data.education.any((e) => e.institution.isNotEmpty)) ...[
            _sectionHeader('EDUCATION', sectionHeaderStyle),
            ...data.education
                .where((e) => e.institution.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => educationEntry(
                    entry.value, entryTitleStyle, metaStyle, entry.key)),
            _sectionSpacer(),
          ],
          if (data.skills.isNotEmpty) ...[
            _sectionHeader('SKILLS', sectionHeaderStyle),
            tappableSkillsWrap(data.skills, bodyStyle),
            _sectionSpacer(),
          ],
          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            _sectionHeader('EXPERIENCE', sectionHeaderStyle),
            ...data.experience
                .where((e) => e.title.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) => experienceEntry(
                    entry.value,
                    entryTitleStyle,
                    metaStyle,
                    bodyStyle,
                    AppColors.secondaryTextLight,
                    entry.key)),
            _sectionSpacer(),
          ],
          if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
            _sectionHeader('CERTIFICATIONS', sectionHeaderStyle),
            ...data.certifications
                .where((c) => c.name.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .map((entry) =>
                    certEntry(entry.value, entryTitleStyle, metaStyle, entry.key)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared template helpers (free functions used by all templates)
// ─────────────────────────────────────────────────────────────────────────────

Widget _sectionHeader(String title, TextStyle style) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: style),
      const SizedBox(height: 4),
      const Divider(color: AppColors.borderLight, height: 1),
      const SizedBox(height: 8),
    ],
  );
}

Widget _sectionSpacer() => const SizedBox(height: 16);

