import '../utils/app_logger.dart';
import '../models/supporting_models.dart';

/// The document genres the extraction prompt asks Claude to self-report
/// (see _kEntryClassificationRules' Document Type rule in
/// CloudflareWorkerService) — used to break field-level conflicts between
/// documents by source authority. 'other'/unrecognized values parse to
/// null (see ResumeSanitizer.parseSourceDocType), not a member here, since
/// an unknown type must never participate in priority tie-breaking.
///
/// awardRecommendation (DA Form 638-shaped), equipmentQualification (DA
/// Form 348-shaped), and trainingCertificate (a standalone course-
/// completion certificate) were added in Stage 8 — see the priority tier
/// lists below for how awardRecommendation participates as a PEER of
/// ncoer, not a subordinate, in duty-narrative tie-breaking.
enum SourceDocType {
  stp,
  ncoer,
  jst,
  transcript,
  civilianResume,
  awardRecommendation,
  equipmentQualification,
  trainingCertificate,
}

// ─────────────────────────────────────────────────────────────────────────────
// ResumeSanitizer
//
// Single shared home for extraction-time cleanup that used to be duplicated
// (and, in places, only wired up for one document type) across
// CloudflareWorkerService and DocumentUploadScreen:
//   - certification fuzzy dedup
//   - bullet cap
//   - cross-document duplicate-role detection
//   - fallback keyword lists used ONLY when the extraction model didn't
//     return a classification (entryType / certType) for an entry.
//
// The model-returned classification is always the primary signal — these
// keyword lists exist purely as a defensive backstop, and are intentionally
// short and unambiguous so they don't risk deleting a legitimate credential.
// ─────────────────────────────────────────────────────────────────────────────

class ResumeSanitizer {
  ResumeSanitizer._();

  /// Coerces a raw Claude JSON value to String?, treating a JSON number the
  /// same way resume_sections.dart's model factories already do (see that
  /// file's `_s()` helper) — Claude's extraction API sometimes returns GPA,
  /// year, and date fields as JSON numbers (e.g. gpa: 3.9772) instead of
  /// strings. Every function below that reads one of those fields directly
  /// off a raw Claude JSON map — before it ever reaches the Hive-backed
  /// model layer's own coercion — needs this too, or a numeric response
  /// throws a type-cast error that parseFieldMappings' try/catch turns into
  /// an empty result for the WHOLE document, not just the offending field.
  /// Confirmed against a real extraction response during Stage 1 real-
  /// document verification (a real GPA came back as a JSON double and this
  /// exact crash reproduced before this fix).
  static String? coerceToString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is num) return v.toString();
    return null;
  }

  // ── AI output character sanitization ────────────────────────────────────
  //
  // WizardValidator blocks < > ; and backtick in every content field (Rule
  // §8) — but that check exists to catch what a USER types, and Claude's
  // own rewriting can introduce one of these characters into generated text
  // that the user never typed and can't fix (e.g. turning a source
  // document's comma into a semicolon while restructuring a sentence). A
  // prompt instruction alone isn't reliable enough on its own (established
  // pattern in this codebase — see fallback keyword lists above), so this
  // runs as a mandatory code-side pass on every piece of AI-generated text
  // before it can reach a Hive-backed content field, regardless of which
  // call site produced it.

  /// Prompt-level reinforcement of the same rule — include this in every
  /// extraction/generation/rewriting system prompt. Not a substitute for
  /// [sanitizeAiText] / [sanitizeAiJson], which is what actually guarantees
  /// the constraint.
  static const String noBlockedCharsPromptRule =
      'Never use the characters < > ; or a backtick (`) anywhere in your '
      'output. If source content uses one of these (e.g. a semicolon '
      'joining two clauses), rewrite it with a comma, period, or plain '
      'wording instead.';

  /// Strips/replaces the characters WizardValidator's content-field
  /// pattern (`[<>;`]`) blocks, so AI-generated text can never trip a
  /// validation error the user didn't cause and can't explain. Replaces
  /// rather than deletes where a like-for-like substitute reads naturally;
  /// only removes for the bracket characters, which have no such substitute.
  static String sanitizeAiText(String text) {
    return text
        .replaceAll(';', ',')
        .replaceAll('`', "'")
        .replaceAll('<', '')
        .replaceAll('>', '');
  }

  /// Recursively applies [sanitizeAiText] to every String leaf in a decoded
  /// JSON value (Map / List / String), leaving other types untouched. Lets
  /// every call site sanitize a whole Claude response in one call
  /// regardless of its shape — a single scalar, a flat list of strings, or
  /// a nested resume-shaped object.
  static dynamic sanitizeAiJson(dynamic value) {
    if (value is String) return sanitizeAiText(value);
    if (value is List) return value.map(sanitizeAiJson).toList();
    if (value is Map) {
      // Explicit Map<String, dynamic> construction — Map.map() on a
      // statically-dynamic receiver otherwise infers Map<dynamic, dynamic>,
      // which fails the `as Map<String, dynamic>` cast every call site uses.
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key as String: sanitizeAiJson(entry.value),
      };
    }
    return value;
  }

  // ── Migration versioning ────────────────────────────────────────────────
  //
  // Bump this whenever the sanitization rules below change in a way that
  // should re-run against already-stored resumes. ResumeMigrationService
  // compares this against UserSettings.experienceSanitizedVersion on app
  // launch and runs the migration once when it's behind.
  // v2: added dropExperienceMatchingCertification — retroactively clears
  // experience entries that duplicate an already-classified certification
  // of the same event (Priority 3 fix), not just bare-stub duplicates.
  // v3: added deduplicateEducation — completion-aware education dedup
  // (Priority 4 fix).
  // v4: added mergeCrossDocumentDuplicateRoles — auto-merges substantive
  // (non-stub) experience entries that confidently describe the same
  // real-world role recorded twice across documents/chunks, which
  // discardBareDuplicateExperience deliberately leaves alone.
  // v5: mergeCrossDocumentDuplicateRoles now also catches a single
  // incomplete "award date" (no end date, not current) that falls within
  // or near a same-title/company entry's range, or two same-title/company
  // entries that each carry the same single incomplete date (e.g. a JST
  // reporting the identical "Dates Held" value under two skill-level
  // entries for one duty title) — real cases a strict interior-overlap
  // check let through. deduplicateEducation now also refuses to silently
  // pick a winner when two COMPLETED entries in a cluster genuinely
  // disagree on GPA/field of study (as opposed to the already-handled
  // completed-vs-in-progress case), flagging them instead.
  // v6: extractYear/parseApproxDate now recognize compact "YYYYMMDD" dates
  // (e.g. a DA-638's "20181025") — previously invisible to both, since \b
  // never matches inside an unbroken digit run. Real DA-638 extractions
  // commonly use this shape, so mergeCrossDocumentDuplicateRoles' date-
  // overlap check (dateRangesOverlap, built on extractYear) may now confirm
  // overlaps it previously missed entirely on already-stored resumes.
  static const int currentSanitizationVersion = 6;

  // ── Fallback keyword lists (used only when entryType/certType is missing) ──

  /// Companies matching these patterns are training institutions, not
  /// employers — used only when an experience entry has no entryType.
  static const List<String> fallbackTrainingCompanyPatterns = [
    'academy',
    'bootcamp',
    'boot camp',
    'training center',
    'training command',
    'institute',
    'certificate program',
  ];

  /// Job-TITLE patterns (as opposed to company-name patterns above)
  /// indicating the entry describes a trainee/student role rather than paid
  /// employment — used only when an experience entry has no entryType.
  /// General title-naming convention across fields (apprenticeships,
  /// internships, military initial-qualification courses), not a
  /// military-specific list: a Soldier Talent Profile listing a duty title
  /// of "RA Trainee" for an initial qualification course is judged the same
  /// way as a civilian "Sales Intern" or "Apprentice Electrician" title.
  static const List<String> fallbackTrainingTitlePatterns = [
    'trainee',
    'recruit',
    'cadet',
    'apprentice',
    'intern',
  ];

  /// Institution names matching these patterns indicate a non-degree
  /// training program rather than a degree-granting school — used only
  /// when an education entry has no entryType.
  static const List<String> fallbackNonDegreeInstitutionPatterns = [
    'academy',
    'bootcamp',
    'boot camp',
    'institute',
    'training center',
    'certificate program',
  ];

  /// Generic, low-signal compliance/administrative training — used only
  /// when a certification entry has no certType. Deliberately short and
  /// unambiguous: nothing here should ever match the name of a real
  /// professional license or credential (medical, technical, or otherwise).
  static const List<String> fallbackComplianceCertPatterns = [
    'antiterrorism',
    'cyber awareness challenge',
    'sere training',
    'suicide awareness',
    'combating trafficking',
    'blended retirement system',
    'sponsorship training',
    'structured self development',
    'basic leader course',
    'distributed leader course',
  ];

  /// General academic course-naming CONVENTIONS (not subject-specific
  /// vocabulary) — used only when a skill entry has no skillType. These
  /// prefixes show up in course catalogs across every field (nursing,
  /// business, computer science, literature, etc.), so matching on them
  /// isn't a career-specific keyword list, just a structural signal that a
  /// term is a course/curriculum unit title rather than a skill.
  static const List<String> fallbackCourseTitlePrefixes = [
    'introduction to',
    'fundamentals of',
    'principles of',
    'foundations of',
    'survey of',
    'concepts of',
    'topics in',
    'intro to',
  ];

  // ── Source document type & field-level priority ─────────────────────────
  //
  // Different military document types are authoritative for different
  // fields: an STP's assignment-history table is the system-of-record for
  // exact duty dates/station, an NCOER's Part IV bullets are the most
  // detailed personal narrative, and a JST's course list is the definitive
  // source for training. When the same role is recorded across multiple
  // uploaded documents (see mergeCrossDocumentDuplicateRoles below) and two
  // sides disagree on a field, this priority order breaks the tie instead
  // of an arbitrary heuristic (e.g. "whichever file was processed first").
  // Only applies when both sides report a KNOWN, DIFFERENT document type —
  // a single-file upload, or any entry an extraction call didn't tag,
  // always falls through to the existing heuristic unchanged.

  /// Mirrors the "documentType" values the extraction prompt asks Claude to
  /// self-report (see _kEntryClassificationRules' Document Type rule) —
  /// 'other' and anything unrecognized/missing parse to null, which the
  /// priority lookups below treat as "unknown, don't use for tie-breaking".
  static SourceDocType? parseSourceDocType(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'stp':
        return SourceDocType.stp;
      case 'ncoer':
        return SourceDocType.ncoer;
      case 'jst':
        return SourceDocType.jst;
      case 'transcript':
        return SourceDocType.transcript;
      case 'civilian_resume':
        return SourceDocType.civilianResume;
      case 'award_recommendation':
        return SourceDocType.awardRecommendation;
      case 'equipment_qualification':
        return SourceDocType.equipmentQualification;
      case 'training_certificate':
        return SourceDocType.trainingCertificate;
      default:
        return null;
    }
  }

  /// Duty dates and duty station: the STP's assignment table is the
  /// system-of-record; an NCOER's rating-period dates are usually close but
  /// secondary; a JST's "Dates Held" field is the least precise of the
  /// three (see resume_sanitizer's date-parsing comments elsewhere).
  /// Each inner list is one priority TIER — types sharing a tier are peers
  /// (neither outranks the other; see [_preferredSide]).
  static const List<List<SourceDocType>> _dateStationPriority = [
    [SourceDocType.stp],
    [SourceDocType.ncoer],
    [SourceDocType.jst],
  ];

  /// Duty narrative / bullet content: an NCOER's Part IV comments are
  /// personal, achievement-level detail; a JST's MOS description is generic
  /// (synthesized into bullets, not copied verbatim — see the JST parsing
  /// rule); an STP has no narrative field at all.
  ///
  /// Stage 8: awardRecommendation (a DA Form 638-shaped document) shares
  /// the top tier with ncoer rather than being ranked below it — real
  /// testing showed award citations are often MORE detailed and quantified
  /// than NCOER bullets for the same period, so neither should silently
  /// outrank the other here. This only affects which side donates
  /// title/company identity text on a genuine disagreement — bullet
  /// content from both sides is unioned in [_mergeTwoRoles] regardless of
  /// tier, so award-recommendation and NCOER narrative for the same role
  /// always both survive into the merged entry.
  static const List<List<SourceDocType>> _dutyNarrativePriority = [
    [SourceDocType.ncoer, SourceDocType.awardRecommendation],
    [SourceDocType.jst],
    [SourceDocType.stp],
  ];

  /// Degree/education records: an academic transcript is the authoritative
  /// source; an STP's civilian-education field is usually a shorter
  /// self-reported summary; an NCOER rarely carries education detail at all.
  static const List<List<SourceDocType>> _educationPriority = [
    [SourceDocType.transcript],
    [SourceDocType.stp],
    [SourceDocType.ncoer],
  ];

  /// Returns the higher-priority side of [a] vs [b] per [tiers] ('a', 'b'),
  /// or null if either side is unknown/missing, both share the same type,
  /// or both types fall in the same priority TIER (peers — nothing to break
  /// a tie with) — callers fall back to their existing heuristic in any of
  /// these cases.
  static String? _preferredSide(
    List<List<SourceDocType>> tiers,
    SourceDocType? a,
    SourceDocType? b,
  ) {
    if (a == null || b == null || a == b) return null;
    final ia = tiers.indexWhere((tier) => tier.contains(a));
    final ib = tiers.indexWhere((tier) => tier.contains(b));
    if (ia == -1 || ib == -1 || ia == ib) return null;
    return ia < ib ? 'a' : 'b';
  }

  /// Public wrapper over [_dateStationPriority] for callers outside this
  /// file that need to break a tie between two documents' reported CURRENT
  /// address/location by source authority — e.g. picking which of two
  /// disagreeing contact addresses (home-of-record vs. current duty
  /// station) to pre-select as the default in a conflict prompt. Same
  /// authority order as duty-station resolution ([_mergeTwoRoles]): an
  /// STP's assignment record outranks an NCOER's rating-period address,
  /// which outranks a JST's. Returns 'a', 'b', or null exactly like
  /// [_preferredSide] — null when either side is unknown or they tie.
  static String? preferredCurrentLocationSide(
    SourceDocType? a,
    SourceDocType? b,
  ) =>
      _preferredSide(_dateStationPriority, a, b);

  // ── Address/location normalization (home-of-record vs. duty station) ────
  //
  // Two source documents can each report a complete, genuine, but different
  // address (e.g. a home-of-record mailing address vs. a current duty
  // station). Distinguishing that from a mere formatting difference ("Ft
  // Benning, GA" vs. "Fort Benning, GA", or "CO" vs. "Colorado") needs a
  // best-effort normalization pass, not exact string equality — the same
  // heuristic-fuzzy-matching philosophy as [companiesAreLikelyTheSame]
  // above, not an exhaustive gazetteer.

  static const Map<String, String> _usStateAbbreviations = {
    'alabama': 'AL', 'alaska': 'AK', 'arizona': 'AZ', 'arkansas': 'AR',
    'california': 'CA', 'colorado': 'CO', 'connecticut': 'CT',
    'delaware': 'DE', 'florida': 'FL', 'georgia': 'GA', 'hawaii': 'HI',
    'idaho': 'ID', 'illinois': 'IL', 'indiana': 'IN', 'iowa': 'IA',
    'kansas': 'KS', 'kentucky': 'KY', 'louisiana': 'LA', 'maine': 'ME',
    'maryland': 'MD', 'massachusetts': 'MA', 'michigan': 'MI',
    'minnesota': 'MN', 'mississippi': 'MS', 'missouri': 'MO',
    'montana': 'MT', 'nebraska': 'NE', 'nevada': 'NV',
    'new hampshire': 'NH', 'new jersey': 'NJ', 'new mexico': 'NM',
    'new york': 'NY', 'north carolina': 'NC', 'north dakota': 'ND',
    'ohio': 'OH', 'oklahoma': 'OK', 'oregon': 'OR', 'pennsylvania': 'PA',
    'rhode island': 'RI', 'south carolina': 'SC', 'south dakota': 'SD',
    'tennessee': 'TN', 'texas': 'TX', 'utah': 'UT', 'vermont': 'VT',
    'virginia': 'VA', 'washington': 'WA', 'west virginia': 'WV',
    'wisconsin': 'WI', 'wyoming': 'WY', 'district of columbia': 'DC',
    'puerto rico': 'PR', 'guam': 'GU',
  };

  /// Canonicalizes a state name or abbreviation to its 2-letter code (e.g.
  /// "Colorado" and "CO" both become "CO") so the two forms never look like
  /// a conflict. Anything unrecognized (a non-US region, a typo) falls back
  /// to lowercase/trim so it's still compared consistently, just without
  /// the abbreviation-awareness.
  static String normalizeStateToCode(String raw) {
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    final known = _usStateAbbreviations[trimmed];
    if (known != null) return known;
    if (RegExp(r'^[a-z]{2}$').hasMatch(trimmed)) return trimmed.toUpperCase();
    return trimmed;
  }

  /// Normalizes a city name for comparison: lowercase, strips punctuation,
  /// collapses whitespace, and expands a short list of common whole-word
  /// prefixes military/civilian records both use interchangeably ("Ft" /
  /// "Fort", "St" / "Saint", "Mt" / "Mount") so "Ft Benning" and "Fort
  /// Benning" compare equal.
  static String normalizeCityForComparison(String raw) {
    var s = raw.trim().toLowerCase().replaceAll(RegExp(r'[.,]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'\bft\b'), 'fort');
    s = s.replaceAll(RegExp(r'\bst\b'), 'saint');
    s = s.replaceAll(RegExp(r'\bmt\b'), 'mount');
    return s;
  }

  /// True if two (city, state) pairs represent the SAME real-world location
  /// after normalization — the check [_mergeResults]-style location-
  /// conflict detection uses to avoid flagging pure formatting differences
  /// ("CO" vs "Colorado", "Ft Benning, GA" vs "Fort Benning, GA") as a
  /// genuine conflict.
  static bool isSameLocation(
    String cityA,
    String stateA,
    String cityB,
    String stateB,
  ) =>
      normalizeCityForComparison(cityA) == normalizeCityForComparison(cityB) &&
      normalizeStateToCode(stateA) == normalizeStateToCode(stateB);

  /// Detects a genuine location conflict among files that each report a
  /// COMPLETE (city, state) pair for the resume's contact address — e.g. a
  /// home-of-record mailing address vs. a current duty station. [addresses]
  /// is one entry per file that provided both fields:
  /// `{sourceFile, city, state, documentType}` (documentType nullable/
  /// unrecognized is fine — see [parseSourceDocType]).
  ///
  /// Returns null when there's nothing to resolve — fewer than 2 files, or
  /// every file's address is the SAME after [isSameLocation] normalization
  /// (a pure formatting difference, not a real conflict). The caller should
  /// leave contact.city/contact.state exactly as ordinary per-field
  /// handling would in that case.
  ///
  /// Otherwise returns one entry per DISTINCT normalized address:
  /// `{city, state, sourceFiles: List<String>, isPreferred: bool}` — the
  /// pre-selected default (`isPreferred: true`, exactly one across the
  /// whole result) is whichever address has the highest-authority document
  /// type per [preferredCurrentLocationSide] (STP > NCOER > JST), falling
  /// back to whichever file appears first in [addresses] when doc type
  /// can't break the tie. This is a pre-selection only — the caller must
  /// still require explicit user confirmation before applying either one.
  static List<Map<String, dynamic>>? detectLocationConflict(
    List<Map<String, dynamic>> addresses,
  ) {
    if (addresses.length < 2) return null;

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final addr in addresses) {
      final city = addr['city'] as String;
      final state = addr['state'] as String;
      final key = '${normalizeCityForComparison(city)}|'
          '${normalizeStateToCode(state)}';
      groups.putIfAbsent(key, () => []).add(addr);
    }

    if (groups.length < 2) return null;

    // Pick the pre-selected default by source-document authority, falling
    // back to whichever file appears first in [addresses] (the existing
    // scalar-conflict tiebreak convention) when doc type doesn't decide it.
    var best = addresses.first;
    var bestType = parseSourceDocType(best['documentType'] as String?);
    for (final addr in addresses.skip(1)) {
      final addrType = parseSourceDocType(addr['documentType'] as String?);
      if (preferredCurrentLocationSide(bestType, addrType) == 'b') {
        best = addr;
        bestType = addrType;
      }
    }
    final bestFile = best['sourceFile'] as String;

    return groups.values
        .map((group) => {
              'city': group.first['city'],
              'state': group.first['state'],
              'sourceFiles':
                  group.map((g) => g['sourceFile'] as String).toList(),
              'isPreferred':
                  group.any((g) => g['sourceFile'] == bestFile),
            })
        .toList();
  }

  /// Builds the ContactInfo-shaped sub-field map (e.g. `{'city': ...,
  /// 'firstName': ...}`) from a list of ACCEPTED mapping rows — shared by
  /// DocumentUploadScreen's two apply-time call sites
  /// (_buildPrefillFromMappings for first-time setup,
  /// _writeMappingsToSections for uploading into an existing resume) so the
  /// synthetic `contact.location` conflict row (see [detectLocationConflict])
  /// is split back into real `city`/`state` values identically at both
  /// sites, from one shared implementation, rather than two independently
  /// maintained copies that could silently drift apart. [acceptedMappings]
  /// is the full accepted-mappings list — fields that don't start with
  /// `contact.` are ignored, so callers don't need to pre-filter.
  static Map<String, dynamic> contactMapFromAcceptedMappings(
    List<Map<String, dynamic>> acceptedMappings,
  ) {
    final contactMap = <String, dynamic>{};
    for (final m in acceptedMappings) {
      final field = m['field'] as String;
      if (field == 'contact.location') {
        // Split using the exact values the conflict row was built from —
        // never a re-parse of the "City, State" display string.
        contactMap['city'] = m['_locationCity'];
        contactMap['state'] = m['_locationState'];
      } else if (field.startsWith('contact.')) {
        contactMap[field.substring('contact.'.length)] = m['suggestedValue'];
      }
    }
    return contactMap;
  }

  // ── Bullet object normalization ──────────────────────────────────────────

  /// Normalizes one raw bullet value from Claude's extraction JSON — the
  /// new object shape `{"text": ..., "hasQuantifiableData": ...}`, or a bare
  /// string (a malformed deviation from the current prompt, or data from a
  /// call site that hasn't been touched by the object-shaped extraction
  /// path) — into a consistent `{'text': String, 'hasQuantifiableData':
  /// bool, 'metricRequested': bool}` map. Every bullet-handling function
  /// below operates on this raw map shape, matching the rest of the
  /// extraction pipeline (which works with decoded JSON throughout, only
  /// becoming typed BulletEntry objects once ExperienceEntry.fromJson runs
  /// at the Hive-read boundary). A bare string defaults to
  /// hasQuantifiableData: false — "not yet evaluated," same convention
  /// BulletEntry.fromJson uses for legacy stored data.
  static Map<String, dynamic> normalizeBulletMap(dynamic raw) {
    if (raw is Map) {
      return {
        'text': raw['text']?.toString() ?? '',
        'hasQuantifiableData': raw['hasQuantifiableData'] as bool? ?? true,
        'metricRequested': raw['metricRequested'] as bool? ?? false,
      };
    }
    return {
      'text': raw?.toString() ?? '',
      'hasQuantifiableData': false,
      'metricRequested': false,
    };
  }

  /// Normalizes a raw `bullets` list value (however it's shaped) into
  /// bullet-object maps via [normalizeBulletMap].
  static List<Map<String, dynamic>> normalizeBulletList(dynamic rawBullets) {
    return (rawBullets as List<dynamic>? ?? [])
        .map(normalizeBulletMap)
        .toList();
  }

  // ── Bullet cap ───────────────────────────────────────────────────────────

  /// Caps bullets per experience entry. When over the cap, keeps the [max]
  /// longest bullets (by text length — a simple, deterministic proxy for
  /// the specificity the app's extraction guidance already asks for:
  /// numbers, outcomes, scope) — while preserving the original relative
  /// order of the bullets that survive, so the entry still reads
  /// naturally. Entries at or under the cap are returned untouched.
  /// Operates on bullet-object maps (see [normalizeBulletMap]), not plain
  /// strings, so a kept bullet's hasQuantifiableData flag survives the cap
  /// along with its text.
  ///
  /// Stage 9 (2026-07-28): Master Resumes are exhaustive with no page
  /// limit, so this must NEVER be called against Master Resume data —
  /// only against Tailored Resume paths, which legitimately target a
  /// short bullet list (one page, two-page max). See the doc comments on
  /// CloudflareWorkerService.parseFieldMappings,
  /// DocumentUploadScreen._resolvePendingDecision, and
  /// ResumeMigrationService._sanitizeResume for how each of this
  /// function's call sites respects that split.
  static List<Map<String, dynamic>> capBullets(
      List<Map<String, dynamic>> bullets,
      {int max = 6}) {
    if (bullets.length <= max) return bullets;
    String textOf(int i) => bullets[i]['text'] as String? ?? '';
    final byLength = List<int>.generate(bullets.length, (i) => i)
      ..sort((a, b) => textOf(b).length.compareTo(textOf(a).length));
    final keepIndices = byLength.take(max).toSet();
    return [
      for (int i = 0; i < bullets.length; i++)
        if (keepIndices.contains(i)) bullets[i],
    ];
  }

  // ── Bare-duplicate experience dedup ─────────────────────────────────────

  /// True if an experience entry has no substantive content beyond a title —
  /// no company and no bullets. These show up as artifacts of earlier,
  /// buggier extraction/merge passes: a stub entry alongside a fuller entry
  /// for the same role.
  static bool isBareExperienceStub(Map<String, dynamic> entry) {
    // No bullets is the load-bearing signal — a real job record almost
    // always has at least one duty/achievement bullet; a stub artifact
    // from a duplicate extraction pass typically has none. Company alone
    // isn't a reliable signal (a stub can still carry the org name, e.g.
    // "Motor Transport Operator | United States Army 06-JUN-2016 –" has a
    // company but nothing else), so treat "no bullets AND no location" —
    // i.e. no substantive content beyond a title/org/date — as bare.
    final bullets = entry['bullets'] as List<dynamic>?;
    final location = (entry['location'] as String? ?? '').trim();
    return (bullets == null || bullets.isEmpty) && location.isEmpty;
  }

  /// Discards bare-stub entries (see [isBareExperienceStub]) when a fuller
  /// entry with the same normalized title exists elsewhere in the list.
  /// Never merges or discards two entries that both have real content —
  /// two full entries with the same title but different date ranges are a
  /// legitimate promotion/re-hire sequence, not a duplicate, and are left
  /// exactly as they are.
  static List<dynamic> discardBareDuplicateExperience(List<dynamic> entries) {
    final byTitle = <String, List<Map<String, dynamic>>>{};
    for (final raw in entries) {
      final e = raw as Map<String, dynamic>;
      final title = normalizeTitle(e['title'] as String? ?? '');
      byTitle.putIfAbsent(title, () => []).add(e);
    }

    final result = <dynamic>[];
    for (final entry in byTitle.entries) {
      final title = entry.key;
      final group = entry.value;
      if (title.isEmpty || group.length == 1) {
        result.addAll(group);
        continue;
      }
      final fuller = group.where((e) => !isBareExperienceStub(e)).toList();
      final bare = group.where(isBareExperienceStub).toList();
      if (fuller.isNotEmpty && bare.isNotEmpty) {
        // Discard the stub(s), keep every entry with real content.
        result.addAll(fuller);
      } else {
        // Either all bare or all full — nothing to safely discard.
        result.addAll(group);
      }
    }
    return result;
  }

  // ── Completion-aware education dedup ────────────────────────────────────
  //
  // A single degree program extracted from multiple document sections
  // (e.g. a transcript page plus a summary page) can produce several
  // entries at different levels of completeness — bare, "in progress", and
  // completed — for what is really one enrollment. Whichever entry shows
  // an actual completion date wins, even over a GPA conflict, since a
  // completed-degree record is definitionally more current/authoritative
  // than an in-progress snapshot of the same program.

  static String normalizeDegree(String s) => s.toLowerCase().trim();

  /// True if graduationYear text represents an actual conferral date
  /// rather than a forward-looking / non-completion phrase ("In Progress",
  /// "Expected 2027", "Anticipated May 2026", etc.) — general date-language
  /// detection, not a field-specific keyword list.
  static bool hasEducationCompletionDate(Map<String, dynamic> entry) {
    final grad = (coerceToString(entry['graduationYear']) ?? '').trim();
    if (grad.isEmpty) return false;
    final lower = grad.toLowerCase();
    const nonCompletionMarkers = [
      'progress', 'expected', 'anticipated', 'projected', 'enrolled',
      'ongoing', 'pursuing', 'current',
    ];
    return !nonCompletionMarkers.any((m) => lower.contains(m));
  }

  static int _educationDetailScore(Map<String, dynamic> e) {
    var score = 0;
    if ((coerceToString(e['gpa']) ?? '').isNotEmpty) score++;
    if ((e['fieldOfStudy'] as String? ?? '').isNotEmpty) score++;
    if ((coerceToString(e['honors']) ?? '').isNotEmpty) score++;
    if ((e['degree'] as String? ?? '').isNotEmpty) score++;
    if (hasEducationCompletionDate(e)) score++;
    return score;
  }

  /// True if two or more COMPLETED entries in a cluster genuinely disagree
  /// on GPA or field of study — as opposed to the already-handled case of a
  /// completed entry outranking an in-progress/bare sibling, where a
  /// differing GPA is expected (a snapshot mid-program vs. the final
  /// figure) and NOT a conflict. This only fires when there's more than one
  /// completed record to disagree with each other in the first place.
  static bool _hasGenuineEducationConflict(
      List<Map<String, dynamic>> completed) {
    if (completed.length < 2) return false;
    String? gpa;
    String? field;
    for (final e in completed) {
      final g = (coerceToString(e['gpa']) ?? '').trim();
      if (g.isNotEmpty) {
        if (gpa != null && gpa != g) return true;
        gpa = g;
      }
      final f = (e['fieldOfStudy'] as String? ?? '').trim().toLowerCase();
      if (f.isNotEmpty) {
        if (field != null && field != f) return true;
        field = f;
      }
    }
    return false;
  }

  /// Resolves a cluster of entries believed to represent the SAME degree
  /// program. Normally collapses to a single entry: a completed entry
  /// always wins over an in-progress/bare sibling (regardless of a GPA
  /// difference — an in-progress snapshot is expected to differ from the
  /// final figure, not a real conflict); with no completed entry in the
  /// cluster, keeps whichever is most detailed — ties broken by source
  /// document authority when known (a transcript outranks an STP's
  /// self-reported summary, which outranks an NCOER — see
  /// [_educationPriority]) before falling back to entry order. When two or
  /// more COMPLETED entries genuinely disagree on GPA or field of study,
  /// this is a real conflict between two supposedly-final records — rather
  /// than silently picking one, every completed entry in the disagreement
  /// is returned, each annotated with `educationConflict: true`, so the
  /// user resolves it instead of an guess being baked into the saved
  /// resume. Source priority intentionally does NOT auto-resolve this
  /// conflict case — the existing conflict UI still shows every candidate
  /// with no default.
  static List<Map<String, dynamic>> _resolveEducationCluster(
      List<Map<String, dynamic>> cluster) {
    if (cluster.length == 1) return cluster;
    final completed = cluster.where(hasEducationCompletionDate).toList();
    if (_hasGenuineEducationConflict(completed)) {
      return completed
          .map((e) => <String, dynamic>{...e, 'educationConflict': true})
          .toList();
    }
    final pool = completed.isNotEmpty ? completed : cluster;
    return [
      pool.reduce((best, e) {
        final scoreBest = _educationDetailScore(best);
        final scoreE = _educationDetailScore(e);
        if (scoreE != scoreBest) return scoreE > scoreBest ? e : best;
        final side = _preferredSide(
          _educationPriority,
          parseSourceDocType(best['_sourceDocType'] as String?),
          parseSourceDocType(e['_sourceDocType'] as String?),
        );
        return side == 'b' ? e : best;
      })
    ];
  }

  /// Deduplicates education entries by institution, resolving each
  /// institution's entries to one result per distinct named degree.
  /// Entries with no degree name at all are duplicate candidates for
  /// whichever single named degree exists at that institution — but if an
  /// institution has MULTIPLE distinct named degrees (e.g. a Bachelor's
  /// and a later Master's — both real, both must survive), bare-degree
  /// entries are left alone rather than guessing which one they belong to.
  static List<dynamic> deduplicateEducation(List<dynamic> entries) {
    final byInstitution = <String, List<Map<String, dynamic>>>{};
    final ungroupable = <dynamic>[];
    for (final raw in entries) {
      final e = raw as Map<String, dynamic>;
      final inst = normalizeInstitution(e['institution'] as String? ?? '');
      if (inst.isEmpty) {
        ungroupable.add(e);
      } else {
        byInstitution.putIfAbsent(inst, () => []).add(e);
      }
    }

    final result = <dynamic>[...ungroupable];
    for (final group in byInstitution.values) {
      if (group.length == 1) {
        result.add(group.first);
        continue;
      }

      final namedDegrees = group
          .map((e) => normalizeDegree(e['degree'] as String? ?? ''))
          .where((d) => d.isNotEmpty)
          .toSet();

      if (namedDegrees.length > 1) {
        for (final degree in namedDegrees) {
          final cluster = group
              .where((e) =>
                  normalizeDegree(e['degree'] as String? ?? '') == degree)
              .toList();
          result.addAll(_resolveEducationCluster(cluster));
        }
        result.addAll(group.where(
            (e) => normalizeDegree(e['degree'] as String? ?? '').isEmpty));
        continue;
      }

      // Zero or one named degree at this institution — every entry
      // (named or bare) is a duplicate candidate for that one degree.
      result.addAll(_resolveEducationCluster(group));
    }

    return result;
  }

  // ── Certification dedup ─────────────────────────────────────────────────

  /// Strips parenthetical suffixes like "(Communication)", "(MOS-88M10)",
  /// "(25N)" used to normalize cert names for fuzzy deduplication.
  static String normalizeCertName(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'\s*\([^)]*\)\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Deduplicates a list of certification JSON maps.
  /// Pass 1: group by normalized name; keep entry with a date or the longer name.
  /// Pass 2: among those surviving, drop entries whose issuer+date exactly matches
  ///         another entry (same issuer AND same date = definite duplicate).
  static List<dynamic> deduplicateCertifications(List<dynamic> certs) {
    // Pass 1 — normalize name dedup
    final byNorm = <String, Map<String, dynamic>>{};
    for (final cert in certs) {
      final map = cert as Map<String, dynamic>;
      final norm = normalizeCertName(map['name'] as String? ?? '');
      if (norm.isEmpty) continue;
      if (!byNorm.containsKey(norm)) {
        byNorm[norm] = map;
      } else {
        final existing = byNorm[norm]!;
        final existingDate = coerceToString(existing['dateEarned']) ?? '';
        final newDate = coerceToString(map['dateEarned']) ?? '';
        final existingName = (existing['name'] as String? ?? '');
        final newName = (map['name'] as String? ?? '');
        // Prefer entry that has a date; if both do, prefer the longer name.
        if (existingDate.isEmpty && newDate.isNotEmpty) {
          byNorm[norm] = map;
        } else if (existingDate.isNotEmpty &&
            newDate.isNotEmpty &&
            newName.length > existingName.length) {
          byNorm[norm] = map;
        }
      }
    }

    // Pass 2 — issuer+date exact dedup
    final seenIssuerDate = <String>{};
    final result = <dynamic>[];
    for (final entry in byNorm.values) {
      final issuer = (entry['issuer'] as String? ?? '').toLowerCase().trim();
      final date = (coerceToString(entry['dateEarned']) ?? '').trim();
      if (issuer.isNotEmpty && date.isNotEmpty) {
        final key = '$issuer|$date';
        if (!seenIssuerDate.add(key)) continue; // duplicate issuer+date
      }
      result.add(entry);
    }
    return result;
  }

  // ── Name normalization ──────────────────────────────────────────────────

  static String normalizeCompany(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\b(inc|llc|corp|ltd|co)\.?\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String normalizeInstitution(String s) => s
      .toLowerCase()
      .replaceAll(
          RegExp(r'\b(university|college|institute|school|of|the)\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String normalizeTitle(String s) => s.toLowerCase().trim();

  /// If [short] (already lowercase) is the initialism of some contiguous
  /// run of [words] — e.g. "us" over ["united","states","army"] matches
  /// "united","states" — returns how many leading words that run consumed
  /// (2, here). Returns null if no run matches. General acronym detection,
  /// not a lookup of known organizations: applies equally to "US"/"United
  /// States", "IBM"/"International Business Machines", "GE"/"General
  /// Electric", etc.
  static int? _initialismRunLength(String short, List<String> words) {
    if (short.length < 2) return null;
    final buffer = StringBuffer();
    for (var end = 0; end < words.length; end++) {
      final w = words[end];
      if (w.isEmpty) continue;
      buffer.write(w[0]);
      if (buffer.length == short.length) {
        return buffer.toString() == short ? end + 1 : null;
      }
    }
    return null;
  }

  /// True if two (raw, un-normalized) organization names likely refer to
  /// the same entity even though they aren't identical — an abbreviated vs.
  /// spelled-out form ("US Army" / "United States Army"), or a shortened
  /// vs. full legal suffix ("Acme Corp" / "Acme Corporation"). General
  /// string-similarity heuristics: works for any user's employer names, not
  /// a lookup table of specific organizations (military or otherwise).
  static bool companiesAreLikelyTheSame(String rawA, String rawB) {
    final a = normalizeCompany(rawA);
    final b = normalizeCompany(rawB);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;

    final wordsA = a.split(' ').where((w) => w.isNotEmpty).toList();
    final wordsB = b.split(' ').where((w) => w.isNotEmpty).toList();
    if (wordsA.isEmpty || wordsB.isEmpty) return false;

    // Every token on the shorter side must line up with the longer side —
    // either literally, as a prefix (abbreviated legal suffix: "corp" is a
    // prefix of "corporation"), or as an initialism over a run of the
    // longer side's words ("us" over "united","states").
    final shorter = wordsA.length <= wordsB.length ? wordsA : wordsB;
    final longer = wordsA.length <= wordsB.length ? wordsB : wordsA;
    if (shorter.length / longer.length < 0.34) {
      // Too lopsided to be a confident match (e.g. a single generic word
      // against a five-word name) — avoids false positives like "acme"
      // alone matching "acme regional medical center management group".
      return false;
    }

    var consumedThroughLonger = 0;
    for (final token in shorter) {
      var matched = false;
      for (var i = consumedThroughLonger; i < longer.length; i++) {
        if (longer[i] == token ||
            longer[i].startsWith(token) ||
            token.startsWith(longer[i])) {
          matched = true;
          consumedThroughLonger = i + 1;
          break;
        }
      }
      if (matched) continue;
      final runLength = _initialismRunLength(
          token, longer.sublist(consumedThroughLonger));
      if (runLength != null) {
        matched = true;
        consumedThroughLonger += runLength;
      }
      if (!matched) return false;
    }
    return true;
  }

  // ── Date range overlap ───────────────────────────────────────────────────

  static int? extractYear(String? s) {
    if (s == null || s.isEmpty) return null;
    // Compact "YYYYMMDD" (e.g. a DA-638's "20181025") is an unbroken digit
    // run — \b never matches between two digits, so the general regex below
    // can't see the year inside it. Checked first, on the whole trimmed
    // string, so it doesn't also swallow an 8-digit substring of something
    // longer that isn't actually this shape.
    final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s.trim());
    if (compact != null) {
      final y = int.parse(compact.group(1)!);
      if (y >= 1900 && y <= 2099) return y;
    }
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(s);
    return match != null ? int.tryParse(match.group(0)!) : null;
  }

  static const Map<String, int> _monthNames = {
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
    'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7,
    'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9,
    'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12,
    'december': 12,
  };

  /// Best-effort parse of a date string into a comparable [DateTime], at
  /// whatever precision the string actually supports (day, month, or
  /// year-only — defaulting missing month/day to the start of the period).
  /// Returns null if no year can be found at all. Covers the date shapes
  /// this app's extraction actually produces: ISO ("2016-04-25"), compact
  /// "YYYYMMDD" (a DA-638's period-of-award dates, e.g. "20181025"), the
  /// "DD-MMM-YYYY" style military records use ("06-JUN-2016"), "Mon YYYY" /
  /// "Month YYYY", and a bare "YYYY".
  static DateTime? parseApproxDate(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final trimmed = s.trim();

    // Compact "YYYYMMDD" (e.g. a DA-638's "20181025") — see extractYear's
    // comment on why this needs its own check rather than falling through
    // to the general year-extraction path at the bottom of this method.
    final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(trimmed);
    if (compact != null) {
      final y = int.parse(compact.group(1)!);
      final m = int.parse(compact.group(2)!);
      final d = int.parse(compact.group(3)!);
      if (y >= 1900 && y <= 2099 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return DateTime(y, m, d);
      }
    }

    final iso =
        RegExp(r'^(\d{4})-(\d{1,2})(?:-(\d{1,2}))?$').firstMatch(trimmed);
    if (iso != null) {
      final y = int.parse(iso.group(1)!);
      final m = int.parse(iso.group(2)!);
      final d = iso.group(3) != null ? int.parse(iso.group(3)!) : 1;
      return DateTime(y, m, d);
    }

    final dmy = RegExp(r'^(\d{1,2})[-\s]([A-Za-z]{3,})[-\s](\d{4})$')
        .firstMatch(trimmed);
    if (dmy != null) {
      final month = _monthNames[dmy.group(2)!.toLowerCase()];
      if (month != null) {
        return DateTime(int.parse(dmy.group(3)!), month, int.parse(dmy.group(1)!));
      }
    }

    final my = RegExp(r'^([A-Za-z]{3,})\s+(\d{4})$').firstMatch(trimmed);
    if (my != null) {
      final month = _monthNames[my.group(1)!.toLowerCase()];
      if (month != null) return DateTime(int.parse(my.group(2)!), month, 1);
    }

    final year = extractYear(trimmed);
    return year != null ? DateTime(year, 1, 1) : null;
  }

  /// Returns true if the two date ranges strictly overlap (shared interior,
  /// not just touching endpoints). "2019–2021" and "2021–2023" share only
  /// the endpoint 2021, so they do NOT overlap — that's a promotion sequence.
  static bool dateRangesOverlap(
    String startA, String? endA, bool isCurrentA,
    String startB, String? endB, bool isCurrentB,
  ) {
    final sa = extractYear(startA);
    final sb = extractYear(startB);
    if (sa == null || sb == null) return false; // can't determine → don't flag
    final ea = isCurrentA ? 9999 : (extractYear(endA) ?? sa);
    final eb = isCurrentB ? 9999 : (extractYear(endB) ?? sb);
    // Strict: sa < eb AND sb < ea (touching endpoints excluded)
    return sa < eb && sb < ea;
  }

  // ── Cross-document duplicate-role detection ─────────────────────────────
  //
  // A user uploading multiple source documents (resume + transcript + old
  // LinkedIn export, or a JST + a Soldier Talent Profile) can easily end up
  // with the same role recorded twice with mismatched or incomplete dates —
  // one document might record only an award/completion date where another
  // records a full range. This is a general multi-document problem, not
  // specific to any one type of source document.

  /// Returns true if two experience entries look like the same role
  /// recorded from different documents: same company AND same title, and
  /// either their date ranges overlap OR at least one side has incomplete
  /// date info (a single date rather than a full range) so a strict overlap
  /// check can't rule out that they describe the same assignment.
  static bool isLikelyCrossDocumentDuplicateRole(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final rawCompanyA = a['company'] as String? ?? '';
    final rawCompanyB = b['company'] as String? ?? '';
    if (!companiesAreLikelyTheSame(rawCompanyA, rawCompanyB)) return false;

    final titleA = normalizeTitle(a['title'] as String? ?? '');
    final titleB = normalizeTitle(b['title'] as String? ?? '');
    if (titleA.isEmpty || titleA != titleB) return false;

    final startA = coerceToString(a['startDate']) ?? '';
    final endA = coerceToString(a['endDate']);
    final currentA = a['isCurrent'] as bool? ?? false;
    final startB = coerceToString(b['startDate']) ?? '';
    final endB = coerceToString(b['endDate']);
    final currentB = b['isCurrent'] as bool? ?? false;

    if (dateRangesOverlap(startA, endA, currentA, startB, endB, currentB)) {
      return true;
    }

    // Incomplete-date fallback: one side is a single award/completion date
    // (no end date, not current) rather than a real range — dates alone
    // can't distinguish "same assignment, recorded differently" from
    // "two different assignments", so flag it for the user to review.
    final aIncomplete = !currentA && (endA == null || endA.isEmpty);
    final bIncomplete = !currentB && (endB == null || endB.isEmpty);
    return aIncomplete || bIncomplete;
  }

  /// Returns true if [entries] contains a likely cross-document duplicate
  /// experience pair. Distinct from the same-document duplicate check
  /// already applied by [deduplicateCertifications]-style exact matching —
  /// this one tolerates mismatched dates on purpose.
  static bool hasCrossDocumentDuplicateRoles(List<dynamic> entries) {
    for (int i = 0; i < entries.length; i++) {
      for (int j = i + 1; j < entries.length; j++) {
        if (isLikelyCrossDocumentDuplicateRole(
            entries[i] as Map<String, dynamic>,
            entries[j] as Map<String, dynamic>)) {
          return true;
        }
      }
    }
    return false;
  }

  /// True for the HIGH-confidence half of [isLikelyCrossDocumentDuplicateRole]
  /// only — same fuzzy-matched company (or both sides blank — see below),
  /// same normalized title, and dates confidently describing the SAME
  /// assignment (see [_isConfidentlySameAssignmentDates]). This is the bar
  /// for automatically merging two entries rather than merely flagging them
  /// for the user to review via [hasCrossDocumentDuplicateRoles].
  static bool _isConfidentCrossDocumentDuplicateRole(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final companyA = a['company'] as String? ?? '';
    final companyB = b['company'] as String? ?? '';
    // Both sides blank is treated as a match, not a mismatch: a
    // military-experience-style entry (e.g. a JST MOS record) often has no
    // per-entry employer field at all, so requiring a company match would
    // never let two identically-titled entries from that kind of source
    // merge. Two full, populated-but-different company strings still fail
    // the fuzzy check as before.
    final companiesMatch = companiesAreLikelyTheSame(companyA, companyB) ||
        (companyA.trim().isEmpty && companyB.trim().isEmpty);
    if (!companiesMatch) return false;

    final titleA = normalizeTitle(a['title'] as String? ?? '');
    final titleB = normalizeTitle(b['title'] as String? ?? '');
    if (titleA.isEmpty || titleA != titleB) return false;

    return _isConfidentlySameAssignmentDates(
      coerceToString(a['startDate']) ?? '',
      coerceToString(a['endDate']),
      a['isCurrent'] as bool? ?? false,
      coerceToString(b['startDate']) ?? '',
      coerceToString(b['endDate']),
      b['isCurrent'] as bool? ?? false,
    );
  }

  /// True if [a] and [b]'s dates confidently describe the SAME assignment —
  /// either a genuine interior overlap (see [dateRangesOverlap], which
  /// deliberately excludes two full ranges that merely touch at an
  /// endpoint, since that's the signature of a real promotion/re-hire
  /// sequence), OR at least one side is a single incomplete "award/
  /// completion date" (no end date, not current — the shape a JST's "Dates
  /// Held" field or an STP assignment-table row often takes) that falls
  /// within, or within a year of, the other side's span. Real source
  /// documents frequently report the same assignment as a single award date
  /// in one section and a full range in another — or the identical single
  /// date twice, e.g. a JST listing the same duty title under two MOS
  /// skill-level entries, both stamped with the same "Dates Held" value.
  /// Two full date RANGES on both sides are never merged here beyond what
  /// [dateRangesOverlap] already allows — that promotion-sequence
  /// protection is preserved exactly as before.
  static bool _isConfidentlySameAssignmentDates(
    String startA, String? endA, bool isCurrentA,
    String startB, String? endB, bool isCurrentB,
  ) {
    if (dateRangesOverlap(
        startA, endA, isCurrentA, startB, endB, isCurrentB)) {
      return true;
    }

    final aIncomplete = !isCurrentA && (endA == null || endA.isEmpty);
    final bIncomplete = !isCurrentB && (endB == null || endB.isEmpty);
    // Two fully-dated (or current) ranges that don't interior-overlap are
    // left to dateRangesOverlap's judgment alone — a touching/gapped pair
    // of real ranges is a promotion or re-hire sequence, not a duplicate.
    if (!aIncomplete && !bIncomplete) return false;

    final sa = parseApproxDate(startA);
    final sb = parseApproxDate(startB);
    if (sa == null || sb == null) return false;

    const oneYear = Duration(days: 366);

    if (aIncomplete && bIncomplete) {
      // Both sides are single award-date-shaped entries — closeness of the
      // single date is the only signal available.
      return sa.difference(sb).abs() <= oneYear;
    }

    // Exactly one side is a single date — confident only if it falls
    // within (or just outside, allowing for imprecise source dates) the
    // other side's full range.
    final singleDate = aIncomplete ? sa : sb;
    final rangeStart = aIncomplete ? sb : sa;
    final rangeEnd = aIncomplete
        ? (isCurrentB ? DateTime.now() : (parseApproxDate(endB) ?? rangeStart))
        : (isCurrentA ? DateTime.now() : (parseApproxDate(endA) ?? rangeStart));

    final lowerBound = rangeStart.subtract(oneYear);
    final upperBound = rangeEnd.add(oneYear);
    return !singleDate.isBefore(lowerBound) && !singleDate.isAfter(upperBound);
  }

  static String _normalizeBulletForDedup(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Returns [entry]'s own contributing-range history: if it already has a
  /// `_contributingRanges` list (because it's itself the product of a prior
  /// [_mergeTwoRoles] round, in a chained 3+-way merge), that list is
  /// returned as-is; otherwise a fresh single-element list is synthesized
  /// from [entry]'s own (pre-merge) startDate/endDate/isCurrent/bullets.
  /// [hasBullets] is fixed at whichever this leaf entry itself reported —
  /// it is never recomputed from the merged whole, so later rounds can't
  /// retroactively make an originally-bulletless source look covered.
  /// See [TimelineCoverageGap] / detectIntraEntryGaps for what this feeds.
  static List<Map<String, dynamic>> _contributingRangesOf(
      Map<String, dynamic> entry) {
    final existing = entry['_contributingRanges'] as List<dynamic>?;
    if (existing != null) return existing.cast<Map<String, dynamic>>();
    final bullets = entry['bullets'] as List<dynamic>?;
    return [
      {
        'start': entry['startDate'],
        'end': entry['endDate'],
        'isCurrent': entry['isCurrent'] as bool? ?? false,
        'hasBullets': bullets != null && bullets.isNotEmpty,
      }
    ];
  }

  /// Merges two SUBSTANTIVE (non-stub) experience entries believed to
  /// describe the same real-world role — see
  /// [_isConfidentCrossDocumentDuplicateRole] for the bar that triggers
  /// this. Combines bullets from both (deduplicating near-identical ones —
  /// same text after whitespace/case normalization), keeps the earliest
  /// start date, and keeps the latest end date (or "current", if either
  /// side is marked current — an ongoing role recorded from an older
  /// document is still ongoing). Prefers the more detailed side's title/
  /// company text as the surviving entry's identity fields — by source
  /// document authority when both sides report a known, different
  /// [SourceDocType] (an NCOER's narrative outranks a JST's, which outranks
  /// an STP's — see [_dutyNarrativePriority]), falling back to whichever
  /// side has more bullets when doc type isn't known for either side. Duty
  /// station is resolved the same way when both sides disagree (see
  /// [_dateStationPriority]) — never silently loses one side's location
  /// when only one side has it. Date range combination (earliest start,
  /// latest end) is untouched by source priority — combining fragmentary
  /// date coverage across documents is a deliberate widening strategy, not
  /// a conflict pick, so it's left exactly as before.
  static Map<String, dynamic> _mergeTwoRoles(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    // Captured from the RAW, pre-merge a/b before bullets get unioned below
    // — see _contributingRangesOf's doc comment for why hasBullets must be
    // fixed at what each original leaf side reported, not recomputed later.
    final contributingRanges = [
      ..._contributingRangesOf(a),
      ..._contributingRangesOf(b),
    ];

    final aBullets = normalizeBulletList(a['bullets']);
    final bBullets = normalizeBulletList(b['bullets']);

    final seen = <String>{};
    final mergedBullets = <Map<String, dynamic>>[];
    for (final bullet in [...aBullets, ...bBullets]) {
      final key = _normalizeBulletForDedup(bullet['text'] as String? ?? '');
      if (key.isEmpty || !seen.add(key)) continue;
      mergedBullets.add(bullet);
    }

    final docTypeA = parseSourceDocType(a['_sourceDocType'] as String?);
    final docTypeB = parseSourceDocType(b['_sourceDocType'] as String?);
    final narrativeSide =
        _preferredSide(_dutyNarrativePriority, docTypeA, docTypeB);

    // The higher-authority document for duty narrative donates identity
    // fields (title casing, company formatting) when doc type is known for
    // both sides; otherwise whichever side has more bullets is treated as
    // the more complete record, as before.
    final Map<String, dynamic> primary;
    if (narrativeSide != null) {
      primary = narrativeSide == 'a' ? a : b;
    } else {
      primary = aBullets.length >= bBullets.length ? a : b;
    }

    final startA = extractYear(coerceToString(a['startDate']));
    final startB = extractYear(coerceToString(b['startDate']));
    final earlierStartEntry =
        (startA != null && (startB == null || startA <= startB)) ? a : b;

    final currentA = a['isCurrent'] as bool? ?? false;
    final currentB = b['isCurrent'] as bool? ?? false;
    final isCurrent = currentA || currentB;

    String? mergedEndDate;
    if (!isCurrent) {
      final endA = extractYear(coerceToString(a['endDate']));
      final endB = extractYear(coerceToString(b['endDate']));
      if (endA == null) {
        mergedEndDate = coerceToString(b['endDate']);
      } else if (endB == null) {
        mergedEndDate = coerceToString(a['endDate']);
      } else {
        mergedEndDate = endA >= endB
            ? coerceToString(a['endDate'])
            : coerceToString(b['endDate']);
      }
    }

    final rawLocationA = (a['location'] as String? ?? '').trim();
    final rawLocationB = (b['location'] as String? ?? '').trim();
    final String mergedLocation;
    if (rawLocationA.isNotEmpty &&
        rawLocationB.isNotEmpty &&
        rawLocationA.toLowerCase() != rawLocationB.toLowerCase()) {
      // Genuine disagreement (e.g. an older assignment's station vs. a
      // newer one) — the higher-authority document wins when doc type is
      // known for both sides, else fall back to the identity donor chosen
      // above (unchanged from before this field existed).
      final stationSide =
          _preferredSide(_dateStationPriority, docTypeA, docTypeB);
      mergedLocation = stationSide == null
          ? (primary['location'] as String? ?? '')
          : (stationSide == 'a' ? rawLocationA : rawLocationB);
    } else {
      // Only one side has a value (or they agree) — never drop it.
      mergedLocation = rawLocationA.isNotEmpty ? rawLocationA : rawLocationB;
    }

    return <String, dynamic>{
      ...primary,
      'title': primary['title'],
      'company': primary['company'],
      'location': mergedLocation,
      'startDate': earlierStartEntry['startDate'],
      'endDate': mergedEndDate,
      'isCurrent': isCurrent,
      'bullets': mergedBullets,
      '_contributingRanges': contributingRanges,
    };
  }

  /// Extends [discardBareDuplicateExperience]'s bare-stub dedup to the
  /// substantive-vs-substantive case: two entries that both have real
  /// content (bullets, not just a title) but describe the same real-world
  /// role, recorded twice — typically because they were extracted from
  /// different documents or different sections/chunks of the same
  /// document. Only merges pairs meeting
  /// [_isConfidentCrossDocumentDuplicateRole]'s bar (fuzzy company match +
  /// same title + genuine date-range overlap) — a weaker signal (e.g. one
  /// side has only an incomplete date) is left alone and still surfaces via
  /// [hasCrossDocumentDuplicateRoles] for the user to review manually,
  /// rather than risk silently merging two entries that turn out to be
  /// genuinely different assignments.
  static List<dynamic> mergeCrossDocumentDuplicateRoles(
      List<dynamic> entries) {
    if (entries.length < 2) return entries;

    final remaining = entries.map((e) => e as Map<String, dynamic>).toList();
    final result = <Map<String, dynamic>>[];

    while (remaining.isNotEmpty) {
      var merged = remaining.removeAt(0);
      var mergedAny = true;
      while (mergedAny) {
        mergedAny = false;
        for (var i = 0; i < remaining.length; i++) {
          if (_isConfidentCrossDocumentDuplicateRole(merged, remaining[i])) {
            merged = _mergeTwoRoles(merged, remaining[i]);
            remaining.removeAt(i);
            mergedAny = true;
            break;
          }
        }
      }
      result.add(merged);
    }

    return result;
  }

  // ── Timeline coverage gap detection (Stage 3) ────────────────────────────
  //
  // A real employment date gap can go unnoticed because extraction works
  // per-document rather than against one unified timeline. This checks the
  // FINAL merged experience list (post mergeCrossDocumentDuplicateRoles) for
  // two distinct failure shapes:
  //   - betweenEntries: dead time between two separate, adjacent jobs.
  //   - withinEntry: a single entry's date range was widened by merging
  //     (see _mergeTwoRoles/_contributingRanges) beyond what any of its
  //     contributing bullets actually narrate — e.g. an STP's current-
  //     assignment dates widening a role whose only bullets come from a
  //     narrower NCOER rating period.
  // Pure Dart date arithmetic, no model call — deterministic and free,
  // matching Stage 1/2's "mechanical first" approach. Gaps under
  // [minGapDays] are never flagged (rounding/imprecision, not a real gap).

  static const int minGapDays = 30;

  /// [entry]'s own (start, end) span — end is "now" if current, else the
  /// parsed endDate, falling back to start if endDate is missing/unparsable
  /// (a single award-date-shaped entry, matching the convention used
  /// elsewhere in this file). Null if startDate itself can't be parsed.
  static ({DateTime start, DateTime end})? _entrySpan(
      Map<String, dynamic> entry) {
    final start = parseApproxDate(coerceToString(entry['startDate']));
    if (start == null) return null;
    final isCurrent = entry['isCurrent'] as bool? ?? false;
    final end = isCurrent
        ? DateTime.now()
        : (parseApproxDate(coerceToString(entry['endDate'])) ?? start);
    return (start: start, end: end);
  }

  /// Detects unexplained dead time between adjacent experience entries
  /// (sorted by start date), treating any education/certification entry
  /// whose own single date falls within the gap as plausible coverage (a
  /// degree completed, or a certification earned, during what looks like a
  /// job gap). This is a deliberately approximate signal — education/
  /// certification entries only carry one point-in-time date in this app's
  /// data model, not a range, so "coverage" here means "something notable
  /// happened during this window," not a verified full-span explanation.
  static List<TimelineCoverageGap> detectInterEntryGaps(
    List<dynamic> experienceEntries,
    List<dynamic> educationEntries,
    List<dynamic> certificationEntries,
  ) {
    final spans = <({String id, DateTime start, DateTime end})>[];
    for (final raw in experienceEntries) {
      final entry = raw as Map<String, dynamic>;
      final span = _entrySpan(entry);
      if (span == null) continue;
      spans.add((
        id: entry['id'] as String? ?? '',
        start: span.start,
        end: span.end,
      ));
    }
    if (spans.length < 2) return [];
    spans.sort((a, b) => a.start.compareTo(b.start));

    final coveringDates = <DateTime>[];
    for (final raw in educationEntries) {
      final d = parseApproxDate(
          coerceToString((raw as Map<String, dynamic>)['graduationYear']));
      if (d != null) coveringDates.add(d);
    }
    for (final raw in certificationEntries) {
      final d = parseApproxDate(
          coerceToString((raw as Map<String, dynamic>)['dateEarned']));
      if (d != null) coveringDates.add(d);
    }

    final gaps = <TimelineCoverageGap>[];
    for (var i = 0; i < spans.length - 1; i++) {
      final prev = spans[i];
      final next = spans[i + 1];
      final gapStart = prev.end;
      final gapEnd = next.start;
      if (!gapEnd.isAfter(gapStart)) continue;
      if (gapEnd.difference(gapStart).inDays < minGapDays) continue;
      final covered = coveringDates
          .any((d) => !d.isBefore(gapStart) && !d.isAfter(gapEnd));
      if (covered) continue;
      gaps.add(TimelineCoverageGap(
        id: 'gap_between_${prev.id}_${next.id}',
        startDate: gapStart,
        endDate: gapEnd,
        kind: TimelineGapKind.betweenEntries,
        adjacentEntryIds: [prev.id, next.id],
      ));
    }
    return gaps;
  }

  /// Detects a single experience entry whose date range was widened by
  /// cross-document merging beyond what its contributing sides' bullets
  /// actually cover — see [_contributingRangesOf]. Entries that never went
  /// through a cross-document merge (fewer than 2 contributing ranges) are
  /// skipped entirely — there's nothing for this failure mode to apply to.
  /// General interval-merging: handles any number of contributing ranges,
  /// not just two, so a 3+-way chained merge is covered the same way.
  static List<TimelineCoverageGap> detectIntraEntryGaps(
    List<dynamic> experienceEntries,
  ) {
    final gaps = <TimelineCoverageGap>[];

    for (final raw in experienceEntries) {
      final entry = raw as Map<String, dynamic>;
      final ranges = entry['_contributingRanges'] as List<dynamic>?;
      if (ranges == null || ranges.length < 2) continue;

      final span = _entrySpan(entry);
      if (span == null) continue;
      final entryStart = span.start;
      final entryEnd = span.end;
      final entryId = entry['id'] as String? ?? '';

      final covered = <({DateTime start, DateTime end})>[];
      for (final r in ranges) {
        final range = r as Map<String, dynamic>;
        if (range['hasBullets'] != true) continue;
        final start = parseApproxDate(coerceToString(range['start']));
        if (start == null) continue;
        final isCurrent = range['isCurrent'] as bool? ?? false;
        final end = isCurrent
            ? DateTime.now()
            : (parseApproxDate(coerceToString(range['end'])) ?? start);
        // Clip to the entry's own span — a contributing side's raw dates
        // can't extend coverage beyond what the merged entry itself claims.
        final clippedStart = start.isBefore(entryStart) ? entryStart : start;
        final clippedEnd = end.isAfter(entryEnd) ? entryEnd : end;
        if (clippedEnd.isAfter(clippedStart)) {
          covered.add((start: clippedStart, end: clippedEnd));
        }
      }

      // Merge overlapping/adjacent covered intervals, sorted ascending.
      covered.sort((a, b) => a.start.compareTo(b.start));
      final merged = <({DateTime start, DateTime end})>[];
      for (final iv in covered) {
        if (merged.isNotEmpty && !iv.start.isAfter(merged.last.end)) {
          final last = merged.removeLast();
          merged.add((
            start: last.start,
            end: iv.end.isAfter(last.end) ? iv.end : last.end,
          ));
        } else {
          merged.add(iv);
        }
      }

      // Walk the uncovered stretches: before the first covered interval,
      // between consecutive covered intervals, and after the last one.
      var cursor = entryStart;
      for (final iv in merged) {
        if (iv.start.difference(cursor).inDays >= minGapDays) {
          gaps.add(TimelineCoverageGap(
            id: 'gap_within_${entryId}_${cursor.toIso8601String()}',
            startDate: cursor,
            endDate: iv.start,
            kind: TimelineGapKind.withinEntry,
            adjacentEntryIds: [entryId],
          ));
        }
        if (iv.end.isAfter(cursor)) cursor = iv.end;
      }
      if (entryEnd.difference(cursor).inDays >= minGapDays) {
        gaps.add(TimelineCoverageGap(
          id: 'gap_within_${entryId}_${cursor.toIso8601String()}',
          startDate: cursor,
          endDate: entryEnd,
          kind: TimelineGapKind.withinEntry,
          adjacentEntryIds: [entryId],
        ));
      }
    }

    return gaps;
  }

  // ── Cross-section duplicate: same event as both a cert and a job ────────
  //
  // A single document (e.g. a multi-page transcript-style record) can
  // describe the same underlying event in two different sections using
  // different framing — one section describing it as training/coursework
  // (correctly classified as a certification), another describing it in
  // job-shaped language (title, duty location, date range) that gets
  // classified as employment. Per-entry classification alone can't catch
  // this, since each entry is independently well-formed — it takes a
  // cross-reference against what already landed in certifications. Title
  // matching is general (normalized string equality), not a keyword list,
  // so it applies to any field: a "CPR Certification" course appearing
  // correctly as a credential and incorrectly as a job titled "CPR
  // Certification" is caught the same way as any military example.

  /// Drops experience entries whose normalized title matches an existing
  /// certification's normalized name AND whose date range contains the
  /// certification's date — the tell that distinguishes "same event
  /// described twice" from the common, entirely legitimate pattern of
  /// getting certified and THEN hired into that role (certification date
  /// at or before the job's start date). A certification date landing
  /// *inside* an experience entry's range, rather than before it, means the
  /// "job" is most likely just describing the training/course period
  /// itself — not omitting real employment. When neither entry has a full
  /// date range to compare, both must be entirely undated to count as a
  /// match; an undated certification is never enough on its own to drop a
  /// dated job. The certification is left as-is — it already went through
  /// its own classification and dedup.
  static List<dynamic> dropExperienceMatchingCertification(
    List<dynamic> experience,
    List<dynamic> certifications,
  ) {
    if (experience.isEmpty || certifications.isEmpty) return experience;

    final certSignatures = certifications
        .map((raw) {
          final c = raw as Map<String, dynamic>;
          return (
            name: normalizeTitle(c['name'] as String? ?? ''),
            date: parseApproxDate(coerceToString(c['dateEarned'])),
          );
        })
        .where((c) => c.name.isNotEmpty)
        .toList();

    return experience.where((raw) {
      final e = raw as Map<String, dynamic>;
      final title = normalizeTitle(e['title'] as String? ?? '');
      if (title.isEmpty) return true;
      final start = parseApproxDate(coerceToString(e['startDate']));
      final isCurrent = e['isCurrent'] as bool? ?? false;
      final parsedEnd = parseApproxDate(coerceToString(e['endDate']));
      final bullets = e['bullets'] as List<dynamic>?;

      final isDuplicate = certSignatures.where((c) => c.name == title).any((c) {
        if (c.date == null) {
          // Undated cert: only a match if the "job" is equally content-free
          // — otherwise a dated, bulleted real job with an undated cert of
          // the same title looks like the legitimate certify-then-hired
          // pattern, and must not be dropped on name alone.
          return start == null && (bullets == null || bullets.isEmpty);
        }
        if (start == null) return false; // no usable range — don't guess
        // Inclusive range containment is the tell: a certification date
        // *before* the job's start is the normal, legitimate
        // certify-then-hired pattern (must NOT match). A certification
        // date landing inside the range means the "job" most likely just
        // describes the training/course period itself.
        final rangeEnd = isCurrent ? DateTime.now() : (parsedEnd ?? start);
        return !c.date!.isBefore(start) && !c.date!.isAfter(rangeEnd);
      });

      if (isDuplicate) {
        devLog('[SANITIZE] Dropped experience entry duplicating an '
            'existing certification of the same title: ${e['title']}');
      }
      return !isDuplicate;
    }).toList();
  }

  // ── Generation-time certification classification ────────────────────────
  //
  // Used by tailored-resume generation (Phase2ApiService.generateTailoredResume),
  // where the Sonnet call is required to tag each certification it returns
  // with certType — same structured signal as extraction-time classification,
  // not a prose-only instruction the model may or may not follow.

  /// Classifies a single certification's certType, preferring the model's
  /// own classification when present and valid, falling back to the generic
  /// keyword list (and logging that the fallback engaged) when it's missing
  /// or malformed.
  static String classifyCertType(Map<String, dynamic> cert) {
    final certType = cert['certType'] as String?;
    if (certType == 'credential' ||
        certType == 'compliance_training' ||
        certType == 'award_recognition' ||
        certType == 'uncertain') {
      devLog(
          '[ResumeSanitizer] cert → $certType (model): "${cert['name']}"');
      return certType!;
    }
    // award_recognition is model-classification-only (no fallback keyword
    // list — award names vary too much by field to safely pattern-match).
    // Anything the model didn't tag falls back to the established
    // compliance-training check only.
    final name = (cert['name'] as String? ?? '').toLowerCase();
    final isCompliance =
        fallbackComplianceCertPatterns.any((p) => name.contains(p));
    final fallbackType = isCompliance ? 'compliance_training' : 'credential';
    devLog('[ResumeSanitizer] cert missing/invalid certType — fallback '
        'keyword list engaged: "${cert['name']}" → $fallbackType');
    return fallbackType;
  }

  /// Filters a tailored-resume generation response's certifications by
  /// certType. compliance_training and award_recognition are excluded;
  /// credential AND uncertain are both kept — tailored-resume generation
  /// must stay fast and never stop to ask the user, so an uncertain cert
  /// defaults to inclusion rather than exclusion. The cost of one extra
  /// low-value line on a tailored resume is far lower than silently
  /// dropping a real credential, which is the failure mode this whole pass
  /// exists to fix. Strips the certType key from surviving entries — it's a
  /// generation-time signal, not part of the stored/displayed resume schema.
  static Map<String, dynamic> filterGeneratedCertifications(
      Map<String, dynamic> resumeJson) {
    final rawCerts = resumeJson['certifications'] as List<dynamic>? ?? [];
    final kept = <dynamic>[];
    for (final raw in rawCerts) {
      final cert = raw as Map<String, dynamic>;
      final certType = classifyCertType(cert);
      if (certType == 'compliance_training' || certType == 'award_recognition') {
        devLog('[ResumeSanitizer] tailored resume cert excluded '
            '($certType): ${cert['name']}');
        continue;
      }
      kept.add(Map<String, dynamic>.from(cert)..remove('certType'));
    }
    return {...resumeJson, 'certifications': kept};
  }
}
