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
// Stage 7 — density tiers.
//
// Three FIXED, pre-baked tiers — not computed per-resume. Each template
// keeps its own distinct comfortable-tier look (Sharp is already tighter
// than Clean, by design); a tier's fontScale/spacingScale is a multiplier
// applied to that template's OWN baseline literals, not a single set of
// absolute values imposed on all 4 templates alike. spacingScale shrinks
// more aggressively than fontScale — margins/line-spacing are the more
// forgiving lever for fitting more content per page; font size affects
// legibility directly, so it's barely touched even at compact.
// ─────────────────────────────────────────────────────────────────────────────

enum DensityTier {
  comfortable(fontScale: 1.0, spacingScale: 1.0),
  standard(fontScale: 0.95, spacingScale: 0.85),
  compact(fontScale: 0.90, spacingScale: 0.70);

  const DensityTier({required this.fontScale, required this.spacingScale});

  final double fontScale;
  final double spacingScale;

  /// The next tighter tier, or null if already at [compact] — used by
  /// _ResumeTemplateRendererState's retry loop to step through tiers in
  /// order without hardcoding the sequence in more than one place.
  DensityTier? get next => switch (this) {
        DensityTier.comfortable => DensityTier.standard,
        DensityTier.standard => DensityTier.compact,
        DensityTier.compact => null,
      };
}

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

class ResumeTemplateRenderer extends StatefulWidget {
  const ResumeTemplateRenderer({
    super.key,
    required this.resume,
    required this.data,
    this.onTapField,
    this.scaleFactor = 1.0,
    this.onDensityResult,
  });

  final Resume resume;
  final ResumeRenderData data;

  /// Called when the user taps a field for inline editing.
  /// Passes the field identifier so the parent knows what to edit.
  final void Function(String fieldId, String currentValue)? onTapField;

  /// Scale factor for fitting the resume inside a constrained preview area.
  final double scaleFactor;

  /// Stage 7 — reports the outcome once the density-tier retry loop (see
  /// _ResumeTemplateRendererState) settles: the tier it rendered at, the
  /// resulting page count, and whether a Tailored Resume still exceeds the
  /// 2-page max even at compact. Master Resumes always report
  /// (DensityTier.comfortable, pageCount, false) — they never retry tiers
  /// and never trip the max, per Stage 9's exhaustiveness rule.
  final void Function(DensityTier tier, int pageCount, bool exceedsTailoredMax)?
      onDensityResult;

  @override
  State<ResumeTemplateRenderer> createState() => _ResumeTemplateRendererState();
}

// ─────────────────────────────────────────────────────────────────────────────
// Stage 11 — heading/subtitle keep-together — merged with Stage 7 — density
// tiers.
//
// Both are render/measure/retry concerns over the SAME rendered tree:
// keep-together inserts spacers that change total content height, and
// that's exactly the height Stage 7 needs to decide whether the current
// tier fits. Running them as two independent loops risked exactly the
// coupled-oscillation problem the two stages were built to avoid: a tier
// change invalidates keep-together spacers (the spacing that changed IS
// what keep-together measured), so a tier decision made against a height
// that hasn't finished settling its spacers would be wrong, and the two
// loops could fight each other. So there is one merged loop:
//
//   1. Measure/settle keep-together spacers at the CURRENT tier (unchanged
//      from Stage 11 — see _scheduleKeepTogetherMeasurement).
//   2. Once spacers are stable for this tier, check density fit (Tailored
//      Resumes only — Master always renders at comfortable, no fit check
//      at all, per Stage 9's exhaustiveness rule): if the settled height
//      is already ≤1 page (the target), done. Otherwise, if there's a
//      tighter tier left, bump to it, reset spacers (they're stale — the
//      spacing they were computed against just changed), and go back to
//      step 1 at the new tier. If already at compact and still >1 page,
//      that's accepted as long as it's ≤2 pages (the max); only >2 pages
//      at compact is reported as unfittable, never silently truncated or
//      silently left overflowing.
//
// Bounded by _maxMeasurePasses across the WHOLE combined loop (keep-together
// settling happens up to 3 times — once per tier — plus a few tier
// transitions), generously sized to guarantee termination.
// ─────────────────────────────────────────────────────────────────────────────

class _ResumeTemplateRendererState extends State<ResumeTemplateRenderer> {
  final GlobalKey _rootKey = GlobalKey();
  final Map<String, GlobalKey> _blockKeys = {};
  Map<String, double> _spacers = {};
  DensityTier _tier = DensityTier.comfortable;
  int _measurePasses = 0;

  // Keep-together spacer insertions only ever push a block LATER, never
  // earlier, so a straddling block is fixed in one measure/render cycle,
  // and a cascading push into a later block resolves within a couple more.
  // A tier bump resets spacers and restarts that settling process at the
  // new tier, up to 2 more times (standard, then compact). Bounded well
  // above the realistic worst case to guarantee termination regardless.
  static const int _maxMeasurePasses = 24;

  // Deliberately no explicit _scheduleMeasurement() call in initState or
  // didUpdateWidget: build() unconditionally calls it at its own end (every
  // build, including the first one and every one triggered by
  // didUpdateWidget), and it must be the ONLY place that does — see the
  // comment in _scheduleMeasurement's setState branches for why a second,
  // independent registration caused an oscillation instead of convergence.

  @override
  void didUpdateWidget(ResumeTemplateRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data || oldWidget.resume != widget.resume) {
      _spacers = {};
      _tier = DensityTier.comfortable;
      _measurePasses = 0;
    }
  }

  void _scheduleMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _measurePasses >= _maxMeasurePasses) return;
      final rootBox = _rootKey.currentContext?.findRenderObject() as RenderBox?;
      if (rootBox == null || !rootBox.hasSize) return;

      final newSpacers = <String, double>{};
      for (final entry in widget.data.experience) {
        final key = _blockKeys[entry.id];
        final blockBox =
            key?.currentContext?.findRenderObject() as RenderBox?;
        if (blockBox == null || !blockBox.hasSize) continue;
        final height = blockBox.size.height;
        // A block taller than a full page can never avoid straddling a
        // boundary regardless of spacing — leave it to flow naturally,
        // same as today, rather than pushing it onto an equally-doomed
        // next page and wasting the rest of the current one.
        if (height > kResumePageHeight) continue;
        // Measured position INCLUDES this block's own currently-applied
        // spacer (if any) — subtract it back out to get the block's
        // natural, unspaced position before deciding whether (and how
        // much) spacing it needs. Checking the raw measured position
        // directly is wrong: once a spacer is correctly applied, the
        // block no longer straddles (that's the point), so re-measuring
        // it as "straddles" would always read false and the spacer would
        // get removed next pass — which un-fixes it, makes it straddle
        // again, re-adds the spacer, and oscillates forever rather than
        // converging. Recomputing from the natural position instead lets
        // a genuine cascade (an earlier entry's new spacer pushing this
        // one further down) still get picked up and re-corrected, without
        // the already-correct case ever being mistaken for "fixed, so
        // undo it".
        final measuredY = blockBox.localToGlobal(Offset.zero, ancestor: rootBox).dy;
        final naturalY = measuredY - (_spacers[entry.id] ?? 0);
        final pageBottom =
            ((naturalY / kResumePageHeight).floor() + 1) * kResumePageHeight;
        final straddles =
            naturalY < pageBottom && naturalY + height > pageBottom;
        if (straddles) {
          newSpacers[entry.id] = pageBottom - naturalY;
        }
      }

      final spacersChanged = newSpacers.length != _spacers.length ||
          newSpacers.entries.any((e) => _spacers[e.key] != e.value);
      _measurePasses++;

      if (spacersChanged) {
        // Keep-together hasn't settled at this tier yet. setState triggers
        // exactly one rebuild, and build() unconditionally reschedules the
        // next measurement pass at its end — deliberately NOT calling
        // _scheduleMeasurement() again here too: doing both used to
        // register two overlapping postFrameCallbacks per cycle, and the
        // second could fire before the rebuild from this setState actually
        // relaid out the tree, measuring stale (pre-rebuild) geometry
        // against the just-updated _spacers — which under-/over-corrected
        // and oscillated (7 → 14 → 21 → 7 → 0 → repeat) rather than
        // converging. One reschedule per state change, from build() alone,
        // guarantees each pass measures a real post-rebuild layout.
        setState(() => _spacers = newSpacers);
        return;
      }

      // Spacers are stable for this tier. Master Resumes never retry
      // tiers or get a fit prompt (Stage 9 — exhaustive, no page limit) —
      // report once at comfortable and stop. this exact height is still
      // reported (useful for page-count display), just never acted on.
      final pageCount = (rootBox.size.height / kResumePageHeight).ceil();
      if (!widget.resume.isTailored) {
        widget.onDensityResult?.call(_tier, pageCount, false);
        return;
      }

      // Tailored: retry against the 1-page TARGET first.
      if (pageCount <= 1) {
        widget.onDensityResult?.call(_tier, pageCount, false);
        return;
      }
      final nextTier = _tier.next;
      if (nextTier != null) {
        setState(() {
          _tier = nextTier;
          _spacers = {}; // stale — spacing just changed under them.
        });
        return;
      }

      // Already at compact and still over the 1-page target. That's fine
      // as long as it's within the 2-page MAX — only exceeding the max
      // gets reported as unfittable (never silently truncated, never
      // silently left overflowing beyond what the user is told).
      widget.onDensityResult?.call(_tier, pageCount, pageCount > 2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final resume = widget.resume;
    final data = widget.data;
    // Master Resumes always render at comfortable — no exceptions, no
    // per-resume computation of "how compact" is needed, per Stage 9.
    final tier = resume.isTailored ? _tier : DensityTier.comfortable;

    final currentIds = data.experience.map((e) => e.id).toSet();
    _blockKeys.removeWhere((id, _) => !currentIds.contains(id));
    for (final e in data.experience) {
      _blockKeys.putIfAbsent(e.id, () => GlobalKey());
    }

    final template = switch (resume.templateId) {
      AppConstants.templateClassic => _ClassicTemplate(
          data: data,
          onTapField: widget.onTapField,
          keepTogetherKeys: _blockKeys,
          keepTogetherSpacers: _spacers,
          tier: tier),
      AppConstants.templateSharp => _SharpTemplate(
          data: data,
          onTapField: widget.onTapField,
          keepTogetherKeys: _blockKeys,
          keepTogetherSpacers: _spacers,
          tier: tier),
      AppConstants.templateEntry => _EntryTemplate(
          data: data,
          onTapField: widget.onTapField,
          keepTogetherKeys: _blockKeys,
          keepTogetherSpacers: _spacers,
          tier: tier),
      AppConstants.templateElevated =>
        ElevatedTemplate(data: data, onTapField: widget.onTapField),
      AppConstants.templateFederal =>
        FederalTemplate(data: data, onTapField: widget.onTapField),
      AppConstants.templateAcademic =>
        AcademicTemplate(data: data, onTapField: widget.onTapField),
      AppConstants.templateVeteran =>
        VeteranTemplate(data: data, onTapField: widget.onTapField),
      AppConstants.templateTechnical =>
        TechnicalTemplate(data: data, onTapField: widget.onTapField),
      AppConstants.templateHorizon => HorizonTemplate(
          data: data,
          onTapField: widget.onTapField,
          accentColorHex: resume.templateAccentColor),
      AppConstants.templateSidebar =>
        SidebarTemplate(data: data, onTapField: widget.onTapField),
      AppConstants.templatePillar =>
        PillarTemplate(data: data, onTapField: widget.onTapField),
      _ => _CleanTemplate(
          data: data,
          onTapField: widget.onTapField,
          keepTogetherKeys: _blockKeys,
          keepTogetherSpacers: _spacers,
          tier: tier),
    };

    _scheduleMeasurement();

    final rootedTemplate = SizedBox(key: _rootKey, child: template);

    if (widget.scaleFactor == 1.0) return rootedTemplate;

    return Transform.scale(
      scale: widget.scaleFactor,
      alignment: Alignment.topCenter,
      child: rootedTemplate,
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
  const _BaseTemplate({
    required this.data,
    this.onTapField,
    this.keepTogetherKeys = const {},
    this.keepTogetherSpacers = const {},
    this.tier = DensityTier.comfortable,
  });

  final ResumeRenderData data;
  final void Function(String fieldId, String currentValue)? onTapField;

  /// Stage 11 — keyed by ExperienceEntry.id. A GlobalKey per entry lets
  /// _ResumeTemplateRendererState measure each entry's title/subtitle/
  /// first-bullet block after layout, to decide whether it straddles a
  /// kResumePageHeight boundary (see experienceEntry below and
  /// _ResumeTemplateRendererState._scheduleKeepTogetherMeasurement).
  final Map<String, GlobalKey> keepTogetherKeys;

  /// Stage 11 — keyed by ExperienceEntry.id. The leading spacer height
  /// (in logical pixels) to insert immediately before an entry's heading
  /// block so it starts flush at the top of the next page instead of
  /// straddling the boundary. Zero/absent means no adjustment needed.
  final Map<String, double> keepTogetherSpacers;

  /// Stage 7 — which fixed density tier to render this template's own
  /// literal font sizes and spacing at (see the DensityTier doc comment
  /// above). Defaults to comfortable — the exact baseline this template
  /// has always rendered at, so Master Resumes (which never change tier)
  /// look pixel-identical to before this stage.
  final DensityTier tier;

  /// Page padding scales with spacingScale like every other spacing value
  /// in these templates — instance getters (not static const) because they
  /// now depend on this instance's [tier].
  double get pagePaddingH => 48.0 * tier.spacingScale;
  double get pagePaddingV => 48.0 * tier.spacingScale;

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
  ///
  /// Returns a flat list rather than one Widget: the title/subtitle row and
  /// first bullet are wrapped as ONE atomic "keep together" unit (see
  /// [keepTogetherKeys]/[keepTogetherSpacers]) so page-break logic can't
  /// split a heading from its opening bullet, while any REMAINING bullets
  /// stay ordinary flow siblings after it, still free to spill across a
  /// page boundary individually if the entry runs long — only the heading
  /// itself is protected, not the whole entry.
  List<Widget> experienceEntry(
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

    Widget bulletRow(String bulletText, int bulletIndex) => Padding(
          padding: EdgeInsets.only(
              top: 3 * tier.spacingScale, left: 10 * tier.spacingScale),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: bulletStyle.copyWith(color: bulletColor)),
              Expanded(
                child: tappable(
                  fieldId: 'experience[$index].bullet.$bulletIndex',
                  value: bulletText,
                  isAIPrefilled: e.isAIPrefilled,
                  child: Text(bulletText, style: bulletStyle),
                ),
              ),
            ],
          ),
        );

    final visibleBullets = [
      for (int i = 0; i < e.bullets.length; i++)
        if (e.bullets[i].isNotEmpty) MapEntry(i, e.bullets[i].text),
    ];

    final headingChildren = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: titleArea),
          SizedBox(width: 8 * tier.spacingScale),
          dateArea,
        ],
      ),
      SizedBox(height: 4 * tier.spacingScale),
    ];
    if (visibleBullets.isNotEmpty) {
      headingChildren
          .add(bulletRow(visibleBullets.first.value, visibleBullets.first.key));
    }

    final remainingBullets = visibleBullets
        .skip(1)
        .map((entry) => bulletRow(entry.value, entry.key))
        .toList();

    final leadingSpacer = keepTogetherSpacers[e.id] ?? 0;

    final entryBottomGap = 12 * tier.spacingScale;

    return [
      // leadingSpacer (Stage 11 keep-together) is deliberately NOT scaled
      // by tier here — it's computed by _ResumeTemplateRendererState from
      // this exact render pass's actual measured heights at whatever tier
      // is currently active, so it's already correct for that tier.
      if (leadingSpacer > 0) SizedBox(height: leadingSpacer),
      Padding(
        padding:
            EdgeInsets.only(bottom: remainingBullets.isEmpty ? entryBottomGap : 0),
        child: Column(
          key: keepTogetherKeys[e.id],
          crossAxisAlignment: CrossAxisAlignment.start,
          children: headingChildren,
        ),
      ),
      for (int i = 0; i < remainingBullets.length; i++)
        Padding(
          padding: EdgeInsets.only(
              bottom: i == remainingBullets.length - 1 ? entryBottomGap : 0),
          child: remainingBullets[i],
        ),
    ];
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
      padding: EdgeInsets.only(bottom: 10 * tier.spacingScale),
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
      padding: EdgeInsets.only(bottom: 6 * tier.spacingScale),
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

  /// Shared section header (title + divider) — used by all 4 Phase 1
  /// templates. _ClassicTemplate's own spacing/divider is identical to the
  /// defaults here (it used to carry a byte-for-byte duplicate private copy,
  /// `_classicSectionHeader`); _SharpTemplate's tighter spacing and
  /// different divider color/thickness (matching its deliberately denser
  /// look) are overridable via the named parameters below (it used to carry
  /// its own duplicate, `_sharpHeader`, hardcoding those differences
  /// instead of parameterizing them). Consolidated into one instance method
  /// so [tier] scaling lives in exactly one place instead of being
  /// re-derived per template.
  Widget _sectionHeader(
    String title,
    TextStyle style, {
    Color dividerColor = AppColors.borderLight,
    double dividerThickness = 1.0,
    double spacingBefore = 4,
    double spacingAfter = 8,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: style),
        SizedBox(height: spacingBefore * tier.spacingScale),
        Divider(color: dividerColor, height: 1, thickness: dividerThickness),
        SizedBox(height: spacingAfter * tier.spacingScale),
      ],
    );
  }

  Widget _sectionSpacer() => SizedBox(height: 16 * tier.spacingScale);
}

// ─────────────────────────────────────────────────────────────────────────────
// Template 1: CLEAN
// Sans-serif throughout, generous white space, safest ATS layout.
// ─────────────────────────────────────────────────────────────────────────────

class _CleanTemplate extends _BaseTemplate {
  const _CleanTemplate({
    required super.data,
    super.onTapField,
    super.keepTogetherKeys,
    super.keepTogetherSpacers,
    super.tier,
  });

  @override
  Widget build(BuildContext context) {
    final nameStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 26 * tier.fontScale,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
      height: 1.2,
    );
    final titleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 13 * tier.fontScale,
      color: AppColors.secondaryTextLight,
    );
    final sectionHeaderStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11 * tier.fontScale,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: AppColors.accentLightColor,
    );
    final bodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11 * tier.fontScale,
      height: 1.5,
      color: AppColors.primaryTextLight,
    );
    final metaStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10 * tier.fontScale,
      color: AppColors.secondaryTextLight,
    );
    final entryTitleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11 * tier.fontScale,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );

    return Container(
      width: kResumePageWidth,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: pagePaddingH,
        vertical: pagePaddingV,
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
            SizedBox(height: 2 * tier.spacingScale),
            tappable(
              fieldId: 'contact.professionalTitle',
              value: data.contact.professionalTitle,
              child: Text(data.contact.professionalTitle, style: titleStyle),
            ),
          ],
          SizedBox(height: 6 * tier.spacingScale),
          _contactLineWidget(data.contact, metaStyle),
          SizedBox(height: 20 * tier.spacingScale),
          const Divider(color: AppColors.borderLight, height: 1),
          SizedBox(height: 16 * tier.spacingScale),

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
                .expand((entry) => experienceEntry(
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
  const _ClassicTemplate({
    required super.data,
    super.onTapField,
    super.keepTogetherKeys,
    super.keepTogetherSpacers,
    super.tier,
  });

  @override
  Widget build(BuildContext context) {
    final nameStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 28 * tier.fontScale,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
      height: 1.2,
    );
    final titleStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 13 * tier.fontScale,
      fontStyle: FontStyle.italic,
      color: AppColors.secondaryTextLight,
    );
    final sectionHeaderStyle = TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: 13 * tier.fontScale,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
      letterSpacing: 0.5,
    );
    final bodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11 * tier.fontScale,
      height: 1.55,
      color: AppColors.primaryTextLight,
    );
    final metaStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10 * tier.fontScale,
      color: AppColors.secondaryTextLight,
    );
    final entryTitleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11 * tier.fontScale,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );

    return Container(
      width: kResumePageWidth,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: pagePaddingH,
        vertical: pagePaddingV,
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
                  SizedBox(height: 3 * tier.spacingScale),
                  tappable(
                    fieldId: 'contact.professionalTitle',
                    value: data.contact.professionalTitle,
                    child: Text(data.contact.professionalTitle, style: titleStyle),
                  ),
                ],
                SizedBox(height: 6 * tier.spacingScale),
                _contactLineWidget(data.contact, metaStyle, centered: true),
              ],
            ),
          ),
          SizedBox(height: 16 * tier.spacingScale),
          const Divider(
              color: AppColors.primaryTextLight, height: 1, thickness: 1.5),
          SizedBox(height: 4 * tier.spacingScale),
          const Divider(color: AppColors.primaryTextLight, height: 1),
          SizedBox(height: 16 * tier.spacingScale),

          // Sections
          if (data.summary.isNotEmpty) ...[
            _sectionHeader('PROFESSIONAL SUMMARY', sectionHeaderStyle),
            tappable(
              fieldId: 'summary',
              value: data.summary,
              child: Text(data.summary, style: bodyStyle),
            ),
            _sectionSpacer(),
          ],
          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            _sectionHeader(
                'PROFESSIONAL EXPERIENCE', sectionHeaderStyle),
            ...data.experience
                .where((e) => e.title.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .expand((entry) => experienceEntry(
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
          if (data.skills.isNotEmpty) ...[
            _sectionHeader('SKILLS', sectionHeaderStyle),
            tappableSkillsWrap(data.skills, bodyStyle),
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
// Template 3: SHARP
// Bold all-caps headers, tight spacing, high density. Corporate/banking.
// ─────────────────────────────────────────────────────────────────────────────

class _SharpTemplate extends _BaseTemplate {
  const _SharpTemplate({
    required super.data,
    super.onTapField,
    super.keepTogetherKeys,
    super.keepTogetherSpacers,
    super.tier,
  });

  @override
  Widget build(BuildContext context) {
    final nameStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 24 * tier.fontScale,
      fontWeight: FontWeight.w800,
      color: AppColors.primaryTextLight,
      letterSpacing: -0.5,
    );
    final titleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12 * tier.fontScale,
      fontWeight: FontWeight.w500,
      color: AppColors.secondaryTextLight,
    );
    final sectionHeaderStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10 * tier.fontScale,
      fontWeight: FontWeight.w800,
      letterSpacing: 2.0,
      color: AppColors.primaryTextLight,
    );
    final bodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10.5 * tier.fontScale,
      height: 1.45,
      color: AppColors.primaryTextLight,
    );
    final metaStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 9.5 * tier.fontScale,
      color: AppColors.secondaryTextLight,
    );
    final entryTitleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10.5 * tier.fontScale,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
    );

    return Container(
      width: kResumePageWidth,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: pagePaddingH,
        vertical: 40 * tier.spacingScale,
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
          SizedBox(height: 4 * tier.spacingScale),
          _contactLineWidget(data.contact, metaStyle),
          SizedBox(height: 12 * tier.spacingScale),
          Container(height: 2, color: AppColors.primaryTextLight),
          SizedBox(height: 12 * tier.spacingScale),

          // Sections — tighter spacing throughout
          if (data.summary.isNotEmpty) ...[
            _sectionHeader('SUMMARY', sectionHeaderStyle, dividerColor: AppColors.primaryTextLight, dividerThickness: 0.8, spacingBefore: 3, spacingAfter: 6),
            tappable(
              fieldId: 'summary',
              value: data.summary,
              child: Text(data.summary, style: bodyStyle),
            ),
            SizedBox(height: 12 * tier.spacingScale),
          ],
          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            _sectionHeader('EXPERIENCE', sectionHeaderStyle, dividerColor: AppColors.primaryTextLight, dividerThickness: 0.8, spacingBefore: 3, spacingAfter: 6),
            ...data.experience
                .where((e) => e.title.isNotEmpty)
                .toList()
                .asMap()
                .entries
                .expand((entry) => experienceEntry(
                      entry.value,
                      entryTitleStyle,
                      metaStyle,
                      bodyStyle,
                      AppColors.secondaryTextLight,
                      entry.key,
                    )),
            SizedBox(height: 12 * tier.spacingScale),
          ],
          if (data.education.any((e) => e.institution.isNotEmpty)) ...[
            _sectionHeader('EDUCATION', sectionHeaderStyle, dividerColor: AppColors.primaryTextLight, dividerThickness: 0.8, spacingBefore: 3, spacingAfter: 6),
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
            SizedBox(height: 12 * tier.spacingScale),
          ],
          if (data.skills.isNotEmpty) ...[
            _sectionHeader('SKILLS', sectionHeaderStyle, dividerColor: AppColors.primaryTextLight, dividerThickness: 0.8, spacingBefore: 3, spacingAfter: 6),
            tappableSkillsWrap(data.skills, bodyStyle),
            SizedBox(height: 12 * tier.spacingScale),
          ],
          if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
            _sectionHeader('CERTIFICATIONS', sectionHeaderStyle, dividerColor: AppColors.primaryTextLight, dividerThickness: 0.8, spacingBefore: 3, spacingAfter: 6),
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
// Template 4: ENTRY
// Education + skills above experience. Best for new graduates/interns.
// ─────────────────────────────────────────────────────────────────────────────

class _EntryTemplate extends _BaseTemplate {
  const _EntryTemplate({
    required super.data,
    super.onTapField,
    super.keepTogetherKeys,
    super.keepTogetherSpacers,
    super.tier,
  });

  @override
  Widget build(BuildContext context) {
    // Same visual style as Clean but section ORDER is different:
    // Contact → Summary → Education → Skills → Experience → Certifications
    final nameStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 24 * tier.fontScale,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryTextLight,
    );
    final titleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12 * tier.fontScale,
      color: AppColors.secondaryTextLight,
    );
    final sectionHeaderStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10 * tier.fontScale,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: AppColors.accentLightColor,
    );
    final bodyStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11 * tier.fontScale,
      height: 1.5,
      color: AppColors.primaryTextLight,
    );
    final metaStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 10 * tier.fontScale,
      color: AppColors.secondaryTextLight,
    );
    final entryTitleStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 11 * tier.fontScale,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryTextLight,
    );

    return Container(
      width: kResumePageWidth,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: pagePaddingH,
        vertical: pagePaddingV,
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
          SizedBox(height: 6 * tier.spacingScale),
          _contactLineWidget(data.contact, metaStyle),
          SizedBox(height: 16 * tier.spacingScale),
          const Divider(color: AppColors.borderLight, height: 1),
          SizedBox(height: 14 * tier.spacingScale),

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
                .expand((entry) => experienceEntry(
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


