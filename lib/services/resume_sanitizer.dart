import '../utils/app_logger.dart';

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
  static const int currentSanitizationVersion = 4;

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

  // ── Bullet cap ───────────────────────────────────────────────────────────

  /// Caps bullets per experience entry in the master resume. When over the
  /// cap, keeps the [max] longest bullets — length is a simple, deterministic
  /// proxy for the specificity the app's extraction guidance already asks
  /// for (numbers, outcomes, scope) — while preserving the original relative
  /// order of the bullets that survive, so the entry still reads naturally.
  /// Entries at or under the cap are returned untouched.
  static List<String> capBullets(List<String> bullets, {int max = 6}) {
    if (bullets.length <= max) return bullets;
    final byLength = List<int>.generate(bullets.length, (i) => i)
      ..sort((a, b) => bullets[b].length.compareTo(bullets[a].length));
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
    final grad = (entry['graduationYear'] as String? ?? '').trim();
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
    if ((e['gpa'] as String? ?? '').isNotEmpty) score++;
    if ((e['fieldOfStudy'] as String? ?? '').isNotEmpty) score++;
    if ((e['honors'] as String? ?? '').isNotEmpty) score++;
    if ((e['degree'] as String? ?? '').isNotEmpty) score++;
    if (hasEducationCompletionDate(e)) score++;
    return score;
  }

  /// Resolves a cluster of entries believed to represent the SAME degree
  /// program to a single entry: a completed entry always wins (regardless
  /// of GPA conflicts with an in-progress sibling); with no completed
  /// entry in the cluster, keeps whichever is most detailed.
  static Map<String, dynamic> _resolveEducationCluster(
      List<Map<String, dynamic>> cluster) {
    if (cluster.length == 1) return cluster.first;
    final completed = cluster.where(hasEducationCompletionDate).toList();
    final pool = completed.isNotEmpty ? completed : cluster;
    return pool.reduce((best, e) =>
        _educationDetailScore(e) > _educationDetailScore(best) ? e : best);
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
          result.add(_resolveEducationCluster(cluster));
        }
        result.addAll(group.where(
            (e) => normalizeDegree(e['degree'] as String? ?? '').isEmpty));
        continue;
      }

      // Zero or one named degree at this institution — every entry
      // (named or bare) is a duplicate candidate for that one degree.
      result.add(_resolveEducationCluster(group));
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
        final existingDate = existing['dateEarned'] as String? ?? '';
        final newDate = map['dateEarned'] as String? ?? '';
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
      final date = (entry['dateEarned'] as String? ?? '').trim();
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
  /// this app's extraction actually produces: ISO ("2016-04-25"), the
  /// "DD-MMM-YYYY" style military records use ("06-JUN-2016"), "Mon YYYY" /
  /// "Month YYYY", and a bare "YYYY".
  static DateTime? parseApproxDate(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final trimmed = s.trim();

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

    final startA = a['startDate'] as String? ?? '';
    final endA = a['endDate'] as String?;
    final currentA = a['isCurrent'] as bool? ?? false;
    final startB = b['startDate'] as String? ?? '';
    final endB = b['endDate'] as String?;
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
  /// only — same fuzzy-matched company, same normalized title, and a real
  /// date-range overlap (not just "one side has an incomplete date", which
  /// is too weak a signal to act on automatically; see that function's
  /// "incomplete-date fallback" comment). This is the bar for automatically
  /// merging two entries rather than merely flagging them for the user to
  /// review via [hasCrossDocumentDuplicateRoles].
  static bool _isConfidentCrossDocumentDuplicateRole(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    if (!companiesAreLikelyTheSame(
        a['company'] as String? ?? '', b['company'] as String? ?? '')) {
      return false;
    }
    final titleA = normalizeTitle(a['title'] as String? ?? '');
    final titleB = normalizeTitle(b['title'] as String? ?? '');
    if (titleA.isEmpty || titleA != titleB) return false;

    return dateRangesOverlap(
      a['startDate'] as String? ?? '',
      a['endDate'] as String?,
      a['isCurrent'] as bool? ?? false,
      b['startDate'] as String? ?? '',
      b['endDate'] as String?,
      b['isCurrent'] as bool? ?? false,
    );
  }

  static String _normalizeBulletForDedup(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Merges two SUBSTANTIVE (non-stub) experience entries believed to
  /// describe the same real-world role — see
  /// [_isConfidentCrossDocumentDuplicateRole] for the bar that triggers
  /// this. Combines bullets from both (deduplicating near-identical ones —
  /// same text after whitespace/case normalization), keeps the earliest
  /// start date, and keeps the latest end date (or "current", if either
  /// side is marked current — an ongoing role recorded from an older
  /// document is still ongoing). Prefers the more detailed side's title/
  /// company/location text as the surviving entry's identity fields.
  static Map<String, dynamic> _mergeTwoRoles(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aBullets = (a['bullets'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final bBullets = (b['bullets'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    final seen = <String>{};
    final mergedBullets = <String>[];
    for (final bullet in [...aBullets, ...bBullets]) {
      final key = _normalizeBulletForDedup(bullet);
      if (key.isEmpty || !seen.add(key)) continue;
      mergedBullets.add(bullet);
    }

    // Whichever side has more bullets is treated as the more complete
    // record and donates its identity fields (title casing, company
    // formatting, location) to the merged entry.
    final primary = aBullets.length >= bBullets.length ? a : b;
    final secondary = identical(primary, a) ? b : a;

    final startA = extractYear(a['startDate'] as String?);
    final startB = extractYear(b['startDate'] as String?);
    final earlierStartEntry =
        (startA != null && (startB == null || startA <= startB)) ? a : b;

    final currentA = a['isCurrent'] as bool? ?? false;
    final currentB = b['isCurrent'] as bool? ?? false;
    final isCurrent = currentA || currentB;

    String? mergedEndDate;
    if (!isCurrent) {
      final endA = extractYear(a['endDate'] as String?);
      final endB = extractYear(b['endDate'] as String?);
      if (endA == null) {
        mergedEndDate = b['endDate'] as String?;
      } else if (endB == null) {
        mergedEndDate = a['endDate'] as String?;
      } else {
        mergedEndDate =
            endA >= endB ? a['endDate'] as String? : b['endDate'] as String?;
      }
    }

    return <String, dynamic>{
      ...primary,
      'title': primary['title'],
      'company': primary['company'],
      'location': (primary['location'] as String? ?? '').isNotEmpty
          ? primary['location']
          : secondary['location'],
      'startDate': earlierStartEntry['startDate'],
      'endDate': mergedEndDate,
      'isCurrent': isCurrent,
      'bullets': mergedBullets,
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
            date: parseApproxDate(c['dateEarned'] as String?),
          );
        })
        .where((c) => c.name.isNotEmpty)
        .toList();

    return experience.where((raw) {
      final e = raw as Map<String, dynamic>;
      final title = normalizeTitle(e['title'] as String? ?? '');
      if (title.isEmpty) return true;
      final start = parseApproxDate(e['startDate'] as String?);
      final isCurrent = e['isCurrent'] as bool? ?? false;
      final parsedEnd = parseApproxDate(e['endDate'] as String?);
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
