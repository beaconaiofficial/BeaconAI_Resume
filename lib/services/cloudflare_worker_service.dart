import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';
import '../models/app_enums.dart';
import '../models/supporting_models.dart';
import '../utils/app_logger.dart';
import 'dev_extraction_cache.dart';
import 'hive_service.dart';
import 'resume_sanitizer.dart';
import 'session_extraction_cache.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// CloudflareWorkerService
//
// Rule §1: NEVER call api.anthropic.com directly from Flutter.
//          ALL Claude API calls go through the Cloudflare Worker URL.
//          The Worker holds the API key and proxies to Anthropic.
//
// Rule §8 (API sanitization):
//   - Strip < > and backticks from all user text before sending.
//   - Always wrap user text in <user_content>...</user_content> XML tags.
//   - Never interpolate raw user input into instruction sentences.
// ─────────────────────────────────────────────────────────────────────────────

// General entry-classification rules injected into every extraction system
// prompt, for every document type and every user. This is what decides
// employment-vs-training, degree-vs-non-degree-training, and
// credential-vs-compliance-clutter — problems every resume has, not just
// military ones. The model reads actual bullet/course content, not
// institution names. Kept at file level so it is shared across text, PDF,
// and image paths.
//
// Prompt caching was evaluated for this constant + _kMilitaryDocumentParsingRules
// (extractResumeFields' full rendered system prompt) and skipped as of the
// last measurement: a live max_tokens:0 call put it at 3,330 input tokens,
// below Haiku 4.5's 4,096-token minimum cacheable prefix — cache_control
// would be a silent no-op as-is. Stages 8/9 added the document-type-
// taxonomy and master-resume-completeness content below, which has NOT
// been re-measured since — re-run the max_tokens:0 check before relying on
// this comment's number again; this content may now be close to or over
// the threshold.
const _kEntryClassificationRules = r'''

ENTRY CLASSIFICATION RULES (apply to every document, for every entry):

━━━ MASTER RESUME COMPLETENESS — READ CAREFULLY, THIS OVERRIDES YOUR ━━━
━━━ DEFAULT RESUME-WRITING INSTINCTS ━━━

This document is being extracted into a MASTER RESUME — an exhaustive
personal record with NO PAGE LIMIT and no space constraint. Everything
else in this prompt about brevity, trimming, or a professional target
length is about a SEPARATE, LATER step (a job-specific tailored resume)
that you are not performing right now. Do not let ordinary resume-writing
conventions ("keep it to one page," "trim to the strongest few," "this is
too much detail") shape what you extract here — those instincts are wrong
for this task specifically, even though they are usually correct.

Concretely:
- Two bullets that SOUND similar are NOT automatically the same
  achievement. If they cite different specific facts — different numbers,
  scope, outcome, or timeframe — keep BOTH, even though a human editor
  might later merge them for a tailored resume. Only treat two bullets as
  duplicates when they describe the literal same fact reported twice (the
  same underlying sentence pulled from two documents).
- NEVER omit an entire employment period, role, or document's content
  because it seems "not relevant," "too old," "too junior," or "unlikely to
  matter for a job search." Relevance judgment belongs entirely to the
  later, separate tailored-resume step — not this one. Every period
  documented in the source material must appear in the output.
- Do not shorten, cap, or trim any section (experience, bullets, skills,
  certifications) to fit an assumed page length. There is no page length
  here. A long, detailed response is the CORRECT output, not a problem to
  fix.

━━━ DOCUMENT TYPE ━━━

Set the top-level "documentType" field to identify the kind of document you
are parsing, using exactly one of these values:
- "stp": a Soldier Talent Profile (assignment-history table with MOS codes,
  Comd Duty Title / Organization / Station columns).
- "ncoer": an NCOER, EPR, FITREP, or OER-style periodic performance
  evaluation (rating period, Part IV bullet comments, ACHIEVES/DEVELOPS
  sections).
- "jst": a Joint Services Transcript (MOS descriptions, ACE-credited course
  list with SH values, "Dates Held" fields).
- "transcript": a civilian academic transcript (course list, credit hours,
  GPA, degree-granting institution).
- "civilian_resume": a standard civilian resume or CV.
- "award_recommendation": a DA Form 638-shaped award recommendation — an
  achievement narrative/citation written to justify a specific award,
  covering a defined award period (e.g. "Period Covered: FROM ... TO ...").
- "equipment_qualification": a DA Form 348-shaped equipment/vehicle
  operator qualification record.
- "training_certificate": a standalone training/course-completion
  certificate (not a full transcript, not an award).
- "other": anything that doesn't clearly match one of the above (a cover
  letter, a LinkedIn export, etc.).
This tag is used to decide which document wins when the same fact (a date,
a duty station, a GPA) is reported differently across multiple uploaded
documents — never leave it blank; pick the closest match if uncertain.

━━━ EXPERIENCE ENTRIES — employment vs. training ━━━

Every experience entry must be tagged with "entryType":
- "employment": the person performed job duties for pay/rank within an
  organization — bullets describe responsibilities, achievements, or scope
  of a real role.
- "education_training": the entry actually describes attending a course,
  school, bootcamp, workshop, or training curriculum rather than performing
  job duties — e.g. bullets describe curriculum content, skills taught, or
  say "completed"/"graduated from"/"attended" a program. This applies
  regardless of the institution's name — judge it from what the bullets
  actually describe, not from whether the company name contains a
  particular word.
- "uncertain": you cannot confidently tell which of the above applies. Set
  "uncertaintyReason" to a short, plain-language sentence explaining why
  (e.g. "Bullets describe both coursework and paid work — unclear which.").
  Do not guess — mark it uncertain instead.

CONSOLIDATION RULE — same title, multiple locations/stations:
- If the same job title appears at multiple different units, duty stations,
  or office locations for the same employer, create EXACTLY ONE experience
  entry for that title. Use the earliest start date and latest end date
  across all occurrences. Merge ALL achievement-oriented, specific bullets
  from every occurrence into the single entry — see the MASTER RESUME
  COMPLETENESS rule near the top of these instructions: there is no bullet
  count to select down to here. Only drop a bullet if it fails the Bullet
  Quality Rule below (a generic duty description with no independent
  value), never merely to shorten the list. Do NOT create separate entries
  for each location.

BULLET QUALITY RULE:
- No maximum bullet count per experience entry in the master resume — see
  the MASTER RESUME COMPLETENESS rule near the top of these instructions.
- For EVERY bullet, actively attempt to extract or infer a quantifiable
  result from the source material — a percentage, dollar figure, headcount
  or team size, time saved, volume/scale, or other measurable outcome. Read
  the surrounding source text (not just the sentence the bullet is drawn
  from) for a number that belongs to that specific achievement before
  concluding none exists — do not stop at the first generic phrasing.
- If no quantifiable result exists anywhere in the source material for a
  given achievement, keep the bullet ONLY if it independently demonstrates
  a specific, relevant skill, responsibility, or scope of work with real
  resume value on its own — not a vague, generic restatement of the job
  title or duty description. Otherwise, exclude the bullet rather than
  padding the entry with a low-value, unquantified line.
- Drop bullets that are generic duty descriptions copied from a manual,
  job description, or regulation rather than something the person actually
  did or achieved.
- Every bullet is an object: {"text": "...", "hasQuantifiableData": true or
  false} — not a bare string. Set hasQuantifiableData to true when the
  bullet's text itself contains the quantifiable result you found or
  inferred (a number, percentage, dollar figure, headcount, or similar).
  Set it to false when you kept the bullet for its independent skill/scope
  value despite finding no quantifiable result anywhere in the source
  material for it — this is a real, expected outcome for some bullets, not
  a mistake to avoid. Never leave this field out.

REWRITE RULE for dense jargon:
- Translate dense, role-specific jargon, abbreviations, and internal
  tool/system names into language a hiring manager outside that field would
  understand — this applies to medical, legal, technical, military, or any
  other specialized field. Keep a specific system or tool name verbatim only
  when it is the kind of term that would appear in a job posting for that
  field (e.g. a named software platform).
- This rewrite rule also applies to the "title" and "company" fields
  themselves, not just bullet text. "title" must always be a civilian-
  legible, recognizable job title — never a raw internal duty title,
  jargon-heavy role code, or field-specific rank/grade/tier used as if it
  were a job title. "company" must always be a plain-language description
  of the employer/organization — never a bare internal unit designation,
  cost-center code, or organizational abbreviation with no meaning outside
  that organization. This applies to any field with internal titling
  conventions (military duty titles and unit designations, hospital
  department codes, corporate internal team names), not just military
  documents.
- A person's rank, grade, pay grade, or seniority tier (military rank, a
  civil-service GS grade, a corporate band/level, etc.) is never itself a
  job title — always extract and translate the actual duty/role title to
  its civilian equivalent instead. If no distinct duty title is available
  at all, infer the most accurate civilian-equivalent title from the role's
  actual responsibilities described in the source material, rather than
  falling back to the rank.

━━━ EDUCATION ENTRIES — degree vs. non-degree training ━━━

Every education entry must be tagged with "entryType":
- "degree": a college/university degree program (Associate, Bachelor,
  Master, Doctorate) or a currently-enrolled program with an expected
  graduation date.
- "non_degree_training": the entry is actually a non-degree training or
  certificate program (a bootcamp, trade school course, professional
  training program, or similar) rather than a degree — regardless of the
  institution's name. Judge this from what the entry actually describes.
- "uncertain": you cannot confidently tell which of the above applies. Set
  "uncertaintyReason" to a short, plain-language sentence explaining why.
  Do not guess — mark it uncertain instead.

If the document is a college or university transcript, extract and map to
ONE education entry (entryType: "degree"): student name, institution,
degree + field of study, graduation/conferral date (include month and year
if visible), GPA (labeled "Cum GPA", "Cumulative GPA", or "GPA"), and honors
(Summa/Magna Cum Laude, Cum Laude). Do NOT extract individual course
listings, semester-by-semester grade rows, transfer credit records, legend/
grading scale pages, or registrar certification statements as separate
entries — produce exactly one education entry and no certification entries
for the courses on it.

━━━ CERTIFICATION ENTRIES — real credential vs. compliance clutter vs. award ━━━

Every certification entry must be tagged with "certType":
- "credential": a genuine professional license, certification exam, or
  named credential with real resume value and differentiating signal (e.g.
  a licensure, an industry certification, a completed apprenticeship with a
  credential attached).
- "compliance_training": a generic, often mandatory or recurring
  administrative/awareness training with little to no differentiating
  resume value (e.g. annual harassment-prevention training, generic safety
  briefings, generic onboarding compliance modules) — this applies
  regardless of industry, not just one field.
- "award_recognition": anything that recognizes performance, service, or
  merit rather than certifying a skill or completing a program — medals,
  badges, employee-of-the-month or top-performer awards, dean's list or
  honor roll, sales/performance recognition, and equivalents in any field.
  Judge this by what the entry actually represents (recognition of past
  performance vs. certification of a capability), never by matching against
  a list of specific award names — a corporate "Top Performer Award" and a
  military commendation medal both get this tag for the same reason.
- "uncertain": you cannot confidently tell which of the above applies. Set
  "certUncertaintyReason" to a short, plain-language sentence explaining why.
  Do not guess — mark it uncertain instead.

━━━ SKILLS — demonstrated skill vs. literal course/curriculum title ━━━

Every skill entry must be tagged with "skillType":
- "skill": a genuine demonstrated competency, tool, technology, or
  professional ability — the kind of term that belongs on a resume skills
  line (e.g. "Python", "Project Management", "Patient Care", "Database
  Management", "Conflict Resolution").
- "course_title": the literal name of a class, course, or curriculum unit
  from a transcript or education record, rather than a skill in its own
  right (e.g. "Object Oriented Design", "Fundamentals of Programming",
  "Introduction to Financial Accounting", "Survey of American Literature").
  A course's CONTENT can justify inferring a real skill (e.g. coursework
  titled "Database Concepts" may justify inferring "Database Management" or
  "SQL" as a skill if the surrounding text supports it) — but the course
  title itself must never become a skill entry verbatim. When in doubt
  whether a term is a skill or a course title, default to "skill" — do not
  guess something into "course_title" without a clear signal (e.g. it was
  explicitly listed under a "Courses" or "Coursework" heading, or reads as
  an academic unit title rather than a competency).

Keep the total skills list focused: aim for roughly 8-12 of the strongest,
most relevant skills rather than exhaustively listing every term that
appears anywhere in the source material. If the source material supports
meaningfully more than that, include the strongest ones and leave the rest
out rather than padding the list.

━━━ PROFESSIONAL SUMMARY RULE ━━━

Generate a professional summary that reflects the person's OVERALL career
arc and strongest qualifications, not just their most recent role. Write
3-4 sentences. Do not copy from any existing summary in the document.

Never state a specific number, figure, or factual claim (a GPA, a
percentage, a dollar amount, a count of anything) in the summary unless
that exact figure also appears in one of the structured fields you
extracted elsewhere in this response (an education entry's gpa, an
experience bullet, etc.). If the source material contains a specific
figure that seems noteworthy but you're not confident which structured
field it belongs to (or it doesn't cleanly fit any of them), do not guess
by writing it into the summary anyway — report it via unplacedFindings
instead (see below) and write the summary without it.

━━━ UNPLACED FINDINGS ━━━

While reading the source material, you will sometimes encounter a specific
number, figure, or factual claim that seems worth keeping but does not
cleanly map to any structured field above — for example, a GPA figure on a
page that doesn't clearly belong to any single education entry, or a
headcount/percentage mentioned in passing that isn't tied to a specific
bullet you extracted. Report each one as an object in the top-level
"unplacedFindings" array instead of silently dropping it OR silently
folding it into prose (the summary, a bullet, anywhere) where it can't be
verified against a structured field:
{"value": "3.94 GPA", "context": "the surrounding sentence or two of source
text the figure appeared in, verbatim or near-verbatim, so the reader can
judge where it actually belongs"}
Only use this for figures you are NOT confident belong to a specific
structured field you already populated — if a number clearly belongs to a
specific education entry's gpa or a specific experience bullet, put it
there directly and do not also duplicate it here.

━━━ REMINDER: THIS IS A MASTER RESUME, NOT A TAILORED ONE ━━━

Before finalizing your response, re-check it against the MASTER RESUME
COMPLETENESS rule near the top of these instructions: did you merge two
distinct achievements because they sounded similar, or drop an entire
employment period or document's content because it seemed less relevant?
If so, undo it. Every distinct achievement and every documented employment
period must be present in your output — exhaustiveness is the correct
result here, conciseness is not your job in this step.

━━━ OUTPUT CHARACTER RULE ━━━

Never use the characters < > ; or a backtick (`) anywhere in your output.
If source content uses one of these (e.g. a semicolon joining two clauses),
rewrite it with a comma, period, or plain wording instead.
''';

// Military-document-specific PARSING rules — these only ever activate when
// the document itself is a JST, NCOER, or Soldier Talent Profile, and they
// do not replace the general classification rules above. Kept narrow on
// purpose: MOS jargon translation and the structural quirks of these
// specific document formats, not general classification logic (that lives
// in _kEntryClassificationRules so it applies to every user).
const _kMilitaryDocumentParsingRules = r'''

MILITARY DOCUMENT PARSING RULES (only apply when the document is one of
the formats below):

━━━ MOS JARGON TRANSLATION ━━━
- "PMCS" → "preventive maintenance"
- "ISYSCON/JNMS/DPEMS" → keep as-is (these are specific system names
  that appear in job postings for signal/network roles)
- "BCT NETOPS" → "Brigade Combat Team network operations"
- "COMSEC" → "communications security (COMSEC)"
- MOS codes like "25N", "88M" → never include raw MOS codes in bullets

━━━ CIVILIAN TITLE & EMPLOYER TRANSLATION ━━━
Applies the general title/company rewrite rule above, with concrete
military examples — these are illustrative, not an exhaustive lookup list;
apply the same translation logic to any duty title or unit designation
that follows this pattern, not just the exact strings below.
- Raw duty titles such as "TC NETWORK COMMUNICATION SYSTEMS", "SR NODAL NET
  SYS OPR-M", "FC HEAVY VEHICLE DRIVER" → translate to the civilian-
  equivalent title implied by the underlying MOS/duty description (e.g.
  "Network Communications Systems Operator", "Senior Network Systems
  Technician", "Heavy Equipment/Logistics Operator") in the "title" field —
  never output the raw abbreviated duty-title string verbatim.
- Raw unit/organization strings such as "W6NF INSTALLATION RCPTN CENTE",
  "0317 EN BN CO C BRIGADE SI", "D CO, 3-81, 199TH, MCOE" → translate to a
  plain-language organization description (e.g. "U.S. Army, Installation
  Reception Center", "U.S. Army, Engineer Battalion", "U.S. Army, Infantry
  Company, Maneuver Center of Excellence") in the "company" field — never
  output the raw UIC/unit-designation string verbatim.
- Rank or rank-with-modifier (e.g. "SGT(P)", "Staff Sergeant", "SSG") must
  never be used as the "title" value — always extract the actual duty
  title being performed and translate it per the rule above.

━━━ JST (Joint Services Transcript) ━━━

The "Military Experience" section of a JST contains MOS descriptions —
these are generic descriptions of what that MOS does, NOT the individual's
personal experience. Use them only to understand what skills the person has,
then synthesize 3-4 achievement-oriented bullets based on the scope of the
role (entryType: "employment"). Do NOT copy the paragraph verbatim as bullets.

Certifications from the "Military Courses" section:
- certType "credential": courses with explicit ACE credit recommendations
  (they show SH values like "3 SH", "6 SH" and levels L, U, V, G), and MOS
  qualification course names and dates.
- certType "compliance_training": anything in the "Other Learning
  Experiences" section, and administrative/awareness courses such as
  Antiterrorism Awareness, DOD Cyber Awareness, SERE training, Suicide
  Awareness and Prevention, Combating Trafficking in Persons, Emergency
  Preparedness courses, JFC 200 modules, Blended Retirement System courses,
  Sponsorship Training, Structured Self Development, Basic Leader Course,
  and Distributed Leader courses. Any course listed under "reason code 1"
  (not evaluated by ACE) is also compliance_training.

Skills (from JST): subject areas from ACE-credited courses that represent
real professional skills — Network Administration, Network Troubleshooting,
Networking Fundamentals, Server Administration, Telecommunications,
Supervision, Communication, Introduction To Management.

Experience date rule for JST MOS entries: the "Dates Held" field on a JST is
a single award date, not a date range. If only one date is available, use it
as startDate, leave endDate empty, isCurrent: false. NEVER copy the same
date to both startDate and endDate.

━━━ NCOER ━━━

INCLUDE: name and rank from Part I; Principal Duty Title translated to its
civilian equivalent (per the Civilian Title & Employer Translation rule
above) as the "title" field — never the raw Principal Duty Title string,
and never the rank; unit translated to a plain-language organization
description (same rule) and dates as an experience entry (entryType:
"employment"); bullet comments from Part IV (lines starting with "o") as
experience bullets — these ARE personal documented achievements, include
them; prioritize ACHIEVES and DEVELOPS section bullets over DUTY
DESCRIPTION.

EXCLUDE: SSN/DOD ID numbers, rater/senior rater personal information,
APFT/ACFT scores (unless specifically impressive, e.g. 300+), checkbox
ratings and numerical codes.

━━━ SOLDIER TALENT PROFILE (STP) ━━━

INCLUDE: name and rank; assignment history table as experience entries
(entryType: "employment"), applying the consolidation rule above (same MOS
title = one entry, not one per duty station); the "Comd Duty Title" and
"Organization"/"Station" columns translated to civilian-equivalent title
and plain-language employer per the Civilian Title & Employer Translation
rule above — never the raw duty-title or UIC/unit strings verbatim, and
never rank as the title; EXCLUDING rows with MOS code "99999Z" (Standard
Excess — not a real job); EXCLUDING projected/future assignments; awards as
certifications; Military Education courses as certifications (classify
with certType per the JST guidance above); civilian education degree
(entryType: "degree").

EXCLUDE: ASVAB scores, PULHES, MRC codes; all "Self-Professed" sections
showing "0 Self-Professed"; career mapping projections; DLPT scores listed
as "Memorized Proficiency"; home address, date of birth, SSN, weight,
height, religion, marital status.

━━━ DA FORM 638 (AWARD RECOMMENDATION) ━━━

INCLUDE: the achievement narrative/justification text as experience
bullets (entryType: "employment") for the role the person held during the
award period — these ARE personal documented achievements, exactly like an
NCOER's Part IV comments, and are often MORE detailed and more quantified
than an NCOER bullet for the same period; include them fully, do not treat
them as secondary to an NCOER covering the same role. The "title" and
"company" fields must be the person's duty position and unit AT THE TIME
OF THE ACHIEVEMENT, translated to civilian-equivalent terms per the
Civilian Title & Employer Translation rule above — using the SAME
translation this document's NCOER or STP entry for that period would use,
so this entry can be recognized as describing the same role and combined
with it, not left as a separate duplicate entry.

The award period (often labeled "Period Covered", "For the Period", or
similar, given as a FROM/TO date pair) becomes this entry's startDate/
endDate — a genuine date range, not a single award date, whenever both a
FROM and a TO date are present. If only one date is given, use it as
startDate, leave endDate empty, isCurrent: false (same convention as a
JST's single "Dates Held" date).

Also extract the award/medal name and level as a separate certification
entry (certType: "award_recognition", per the certification rule above) —
this is in ADDITION to, not instead of, using the narrative as experience
bullets above; the two uses of this document's content are independent.

EXCLUDE: approval-chain signatures and endorsement routing, admin
approval/routing codes, awarding authority letterhead boilerplate.

━━━ DA FORM 348 (EQUIPMENT QUALIFICATION RECORD) ━━━

This document records which vehicles/equipment the person is qualified to
operate — it does NOT describe a role, employer, or time period, so never
create an experience entry from it.

INCLUDE: each qualified equipment/vehicle type as a skill entry (skillType:
"skill", e.g. "Heavy Equipment Operation", "Tactical Vehicle Operation")
UNLESS the record functions as a formal licensure/qualification credential
in its own right, in which case extract it as a certification entry
(certType: "credential" per the certification rule above) instead — judge
this the same way you judge any other credential-vs-skill boundary.

EXCLUDE: raw equipment nomenclature/NSN or model codes, internal
qualification-standard reference numbers, examiner signatures.

━━━ STANDALONE TRAINING CERTIFICATE ━━━

A standalone training/course-completion certificate (not a transcript, not
an award). Extract as exactly ONE certification entry using the
certificate's course/program name, issuing organization, and completion
date — tag certType per the general certification rule above ("credential"
for a genuine skill-differentiating credential, "compliance_training" for
generic mandatory/administrative training). Do NOT create an experience or
education entry from a standalone certificate.
''';

class CloudflareWorkerService {
  CloudflareWorkerService._();

  // Swappable HTTP client — production code never touches this; tests
  // substitute a mock (e.g. package:http/testing.dart's MockClient) so
  // upload-limit and other gating logic can assert the real Claude API
  // client was never invoked, without making live network calls.
  static http.Client client = http.Client();

  // ── Model IDs ──────────────────────────────────────────────────────────────
  // Haiku: document/field extraction (structured JSON output, ~80 % cheaper).
  // Sonnet: content generation (rewrites, summaries, cover letters, interview prep).
  static const String _modelExtract = 'claude-haiku-4-5-20251001';
  static const String _modelGenerate = 'claude-sonnet-4-6';

  // Haiku extraction completes in <10 s — 30 s is a generous ceiling.
  static const Duration _timeout = Duration(seconds: 30);
  // Sonnet generation of 1000–3000 tokens typically takes 30–60 s.
  // 90 s gives headroom without hanging the UI indefinitely.
  static const Duration _generationTimeout = Duration(seconds: 90);

  // ── Cost/usage logging ──────────────────────────────────────────────────
  //
  // Per-call visibility into token usage and estimated cost — reads fields
  // already present in every Claude API response, so this adds no extra
  // request and no production cost. Update this table if pricing changes;
  // it's a rough estimate for debugging, not a billing source of truth.
  static const Map<String, ({double inputPerMTok, double outputPerMTok})>
      _pricingPerMTok = {
    'claude-haiku-4-5-20251001': (inputPerMTok: 1.0, outputPerMTok: 5.0),
    'claude-sonnet-4-6': (inputPerMTok: 3.0, outputPerMTok: 15.0),
  };

  /// Logs token usage and an estimated cost for one API call. [callLabel]
  /// identifies which call site this was (e.g. "extractResumeFields",
  /// "tailoredResume.draftGeneration") so a test session's logs can answer
  /// "which call cost what" without guessing. No-ops silently if the
  /// response has no usage block (e.g. an error response).
  static void _logUsage(
      String callLabel, String model, Map<String, dynamic> responseBody) {
    final usage = responseBody['usage'] as Map<String, dynamic>?;
    if (usage == null) return;

    final inputTokens = usage['input_tokens'] as int? ?? 0;
    final outputTokens = usage['output_tokens'] as int? ?? 0;
    final cacheCreationTokens = usage['cache_creation_input_tokens'] as int? ?? 0;
    final cacheReadTokens = usage['cache_read_input_tokens'] as int? ?? 0;

    final pricing = _pricingPerMTok[model];
    var costLabel = 'unknown pricing for $model';
    if (pricing != null) {
      // Cache writes bill at ~1.25x the input rate (5-minute TTL, the only
      // TTL this app uses); cache reads at ~0.1x. See shared/prompt-caching.md.
      final cost = (inputTokens / 1e6 * pricing.inputPerMTok) +
          (outputTokens / 1e6 * pricing.outputPerMTok) +
          (cacheCreationTokens / 1e6 * pricing.inputPerMTok * 1.25) +
          (cacheReadTokens / 1e6 * pricing.inputPerMTok * 0.1);
      costLabel = '~\$${cost.toStringAsFixed(5)}';
    }

    devLog('[COST] $callLabel | $model | '
        'in=$inputTokens out=$outputTokens '
        'cacheWrite=$cacheCreationTokens cacheRead=$cacheReadTokens | '
        '$costLabel');
  }

  // ── Sanitization ───────────────────────────────────────────────────────────

  /// Sanitizes user-supplied text before inclusion in any Claude prompt.
  /// Strips < > ; and backticks per spec §8.
  static String sanitize(String input) {
    return input
        .replaceAll('<', '')
        .replaceAll('>', '')
        .replaceAll(';', '')
        .replaceAll('`', '');
  }

  /// Strips a markdown code fence Claude occasionally wraps JSON output in
  /// despite the prompt saying not to (```json ... ``` or ``` ... ```).
  /// Returns the input unchanged, trimmed, if it isn't fenced.
  static String stripMarkdownFences(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
      return cleaned;
    }
    // Defense in depth: a fenced block preceded by conversational prose
    // (e.g. "Here's the result:\n```json\n{...}\n```\n\nI focused on...")
    // — the check above only handles a fence at the very start of the
    // string, which a leading sentence defeats entirely even though every
    // system prompt asks for JSON only. Extract the fenced content instead
    // of giving up. See the P0 "tailored resume identical to master"
    // investigation: this exact shape is what let a malformed response
    // reach the save step undetected.
    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(cleaned);
    if (fenced != null) {
      return fenced.group(1)!.trim();
    }
    return cleaned;
  }

  /// Wraps sanitized user text in XML delimiters to structurally separate
  /// it from system instructions. Never interpolate raw input into prompts.
  static String wrap(String sanitizedText) {
    return '<user_content>$sanitizedText</user_content>';
  }

  // ── Age assurance gate ─────────────────────────────────────────────────────

  /// Whether AI calls are blocked for the stored age bracket. Overridable in
  /// tests. Defaults to the on-device bracket; if Hive isn't open (unit tests
  /// that never call HiveService.init) it reports not-blocked. The bracket
  /// itself is never included in any request.
  static bool Function() isAiBlocked = _aiBlockedFromSettings;

  static bool _aiBlockedFromSettings() {
    try {
      return HiveService.settings.ageBracket.isAiBlocked;
    } catch (_) {
      return false;
    }
  }

  /// Backstop for every Worker POST: throws [AiRestrictedException] (a
  /// [CloudflareApiException], so every existing screen handler surfaces its
  /// neutral message) before any document content leaves the device.
  static void _ensureAiAllowed() {
    if (isAiBlocked()) {
      devLog('[AGE SIGNAL] AI call blocked (restricted mode)');
      throw const AiRestrictedException();
    }
  }

  // ── Core request ───────────────────────────────────────────────────────────

  /// Sends a prompt to Claude via the Cloudflare Worker proxy.
  /// Returns the response text or throws a [CloudflareApiException].
  /// [callLabel] identifies the caller for the [_logUsage] cost log — see
  /// that method's doc for why it's required rather than optional.
  static Future<String> sendPrompt({
    required String callLabel,
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 2000,
    String model = _modelGenerate,
    void Function()? onCancel,
    Duration? timeout,
  }) async {
    _ensureAiAllowed();
    final body = jsonEncode({
      'model': model,
      'max_tokens': maxTokens,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userMessage},
      ],
    });

    try {
      final response = await client
          .post(
            Uri.parse(AppConstants.cloudflareWorkerUrl),
            headers: {
              'Content-Type': 'application/json',
              'X-BeaconAI-Secret': AppConstants.cloudflareWorkerSharedSecret,
            },
            body: body,
          )
          // Haiku (extraction) → 30 s; Sonnet (generation) → 90 s.
          // An explicit timeout parameter always wins.
          .timeout(timeout ??
              (model == _modelExtract ? _timeout : _generationTimeout));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        _logUsage(callLabel, model, decoded);
        if (decoded['stop_reason'] == 'max_tokens') {
          devLog('[$callLabel] TRUNCATED — hit the $maxTokens-token cap');
          throw CloudflareTruncatedResponseException(maxTokens);
        }
        final content = decoded['content'] as List<dynamic>?;
        if (content != null && content.isNotEmpty) {
          final first = content.first as Map<String, dynamic>;
          return first['text'] as String? ?? '';
        }
        throw const CloudflareApiException('Empty response from Claude API');
      } else {
        throw AiErrorMessages.forStatus(response.statusCode);
      }
    } on CloudflareApiException {
      rethrow;
    } catch (e) {
      throw AiErrorMessages.forTransport(e,
          timeoutMessage:
              'Request timed out. Check your connection and try again.');
    }
  }

  // ── Web-search-enabled request ────────────────────────────────────────────

  static const Duration _webSearchTimeout = Duration(seconds: 60);

  /// Pro interview prep researches the company with web search and then
  /// writes 10-15 questions with answer guides: measured at ~45 s for a
  /// shorter version of the same request (2026-11-25), so 60 s timed out on
  /// real postings. Only the web-search call uses this.
  static const Duration _interviewResearchTimeout = Duration(seconds: 150);

  /// Sends a prompt to Claude with the web_search tool enabled.
  /// Used for Pro-tier Interview Prep, which must research the actual
  /// company/role rather than rely on training data alone.
  /// Concatenates ALL text blocks in the response (not just the first) since
  /// tool-using responses interleave text, tool_use, and tool_result blocks.
  static Future<String> sendPromptWithWebSearch({
    required String callLabel,
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 4000,
  }) async {
    _ensureAiAllowed();
    final body = jsonEncode({
      'model': _modelGenerate,
      'max_tokens': maxTokens,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userMessage},
      ],
      'tools': [
        {'type': 'web_search_20250305', 'name': 'web_search'},
      ],
    });

    try {
      final response = await client
          .post(
            Uri.parse(AppConstants.cloudflareWorkerUrl),
            headers: {
              'Content-Type': 'application/json',
              'X-BeaconAI-Secret': AppConstants.cloudflareWorkerSharedSecret,
            },
            body: body,
          )
          .timeout(_interviewResearchTimeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        _logUsage(callLabel, _modelGenerate, decoded);
        final content = decoded['content'] as List<dynamic>?;
        if (content == null || content.isEmpty) {
          throw const CloudflareApiException('Empty response from Claude API');
        }
        final buffer = StringBuffer();
        for (final block in content) {
          final map = block as Map<String, dynamic>;
          if (map['type'] == 'text') {
            buffer.write(map['text'] as String? ?? '');
          }
        }
        final text = buffer.toString();
        if (text.isEmpty) {
          throw const CloudflareApiException(
              'Claude returned no usable text content');
        }
        return text;
      } else {
        throw AiErrorMessages.forStatus(response.statusCode);
      }
    } on CloudflareApiException {
      rethrow;
    } catch (e) {
      throw AiErrorMessages.forTransport(e,
          timeoutMessage:
              'Request timed out. Web research can take longer than usual — please try again.');
    }
  }

  // ── Document extraction ────────────────────────────────────────────────────

  /// Extracts structured resume data from a raw document text.
  /// Returns a JSON string containing suggested field mappings.
  /// Available to ALL tiers — never paywalled (spec §9).
  static Future<String> extractResumeFields(String rawDocumentText,
      {Duration? timeout}) async {
    const systemPrompt = '''
You are an expert resume parser. Extract all resume information from the provided document text and return it as a structured JSON object.

Return ONLY valid JSON with no explanation, no markdown, no code fences.

JSON structure to return:
{
  "documentType": "",
  "contact": {
    "firstName": "",
    "lastName": "",
    "professionalTitle": "",
    "city": "",
    "state": "",
    "phone": "",
    "email": "",
    "linkedInUrl": "",
    "websiteUrl": "",
    "gitHubUrl": ""
  },
  "summary": "",
  "experience": [
    {
      "id": "uuid-placeholder",
      "title": "",
      "company": "",
      "location": "",
      "startDate": "",
      "endDate": "",
      "isCurrent": false,
      "bullets": [
        {"text": "", "hasQuantifiableData": true}
      ],
      "entryType": "employment",
      "uncertaintyReason": "",
      "isAIPrefilled": true
    }
  ],
  "education": [
    {
      "id": "uuid-placeholder",
      "degree": "",
      "institution": "",
      "fieldOfStudy": "",
      "graduationYear": "",
      "gpa": null,
      "honors": null,
      "entryType": "degree",
      "uncertaintyReason": "",
      "isAIPrefilled": true
    }
  ],
  "skills": [
    {
      "id": "uuid-placeholder",
      "name": "",
      "category": "uncategorized",
      "skillType": "skill",
      "isAIPrefilled": true
    }
  ],
  "certifications": [
    {
      "id": "uuid-placeholder",
      "name": "",
      "issuer": "",
      "dateEarned": "",
      "expiresDate": null,
      "credentialId": null,
      "certType": "credential",
      "certUncertaintyReason": "",
      "isAIPrefilled": true
    }
  ],
  "unplacedFindings": [
    {
      "value": "",
      "context": ""
    }
  ]
}

Guidelines:
- Extract only what is present in the document. Leave fields empty string or empty array if not found.
- For skills, categorize as: technical, softSkill, toolsSoftware, or uncategorized. Tag every skill with skillType per the classification rules below.
- Each experience bullet is an object ({"text": ..., "hasQuantifiableData": ...}), not a bare string — see the bullet quality rule below for what belongs in "text" and how to set "hasQuantifiableData".
- Set isAIPrefilled to true for all extracted fields.
- UUID placeholders will be replaced by the app — use "uuid-placeholder" for all id fields.
- entryType, uncertaintyReason, certType, certUncertaintyReason, and skillType are always required — see the classification rules below for how to set them.
- unplacedFindings is required but usually empty ([]) — only populate it per the Unplaced Findings rule below.
- documentType is always required — see the Document Type rule below for the allowed values.
$_kEntryClassificationRules$_kMilitaryDocumentParsingRules''';

    final sanitized = sanitize(rawDocumentText);
    final userMessage =
        'Extract all resume information from this document:\n\n${wrap(sanitized)}';
    final content = utf8.encode(rawDocumentText);

    // Session cache (always on, production-safe) is checked first; a miss
    // falls through to the dev cache (dev-only, gated off by default),
    // which falls through to the real call. See each cache's own doc
    // comment for why they're separate.
    return SessionExtractionCache.cachedOrCall(
      label: 'extractResumeFields',
      content: content,
      call: () => DevExtractionCache.cachedOrCall(
        label: 'extractResumeFields',
        content: content,
        call: () => sendPrompt(
          callLabel: 'extractResumeFields',
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          maxTokens: 8000,
          model: _modelExtract,
          timeout: timeout,
        ),
      ),
    );
  }

  // ── PDF-based resume extraction (Claude native PDF) ──────────────────────

  /// Extracts structured resume data from a PDF document using Claude's
  /// native PDF document vision capability. Called as a fallback when
  /// local text extraction produces output that times out during parsing.
  ///
  /// Sends a document content block — the same transparent-proxy pattern
  /// already used by [extractResumeFieldsFromImage]. No Worker-side changes
  /// needed: the Worker forwards the full messages array unchanged.
  /// Uses [_webSearchTimeout] (60 s) — PDF payloads are larger than text.
  static Future<String> extractResumeFieldsFromPdf(List<int> pdfBytes) async {
    _ensureAiAllowed();
    const systemPrompt = '''
You are an expert document parser. Extract all resume or professional background information from the provided PDF document and return it as a structured JSON object.

The document may be a standard resume, a military service record (JST, NCOER, Soldier Talent Profile), a transcript, or another career-related document. Extract whatever professional information is present and map it to the closest resume fields.

Return ONLY valid JSON with no explanation, no markdown, no code fences.

JSON structure to return:
{
  "documentType": "",
  "contact": {
    "firstName": "",
    "lastName": "",
    "professionalTitle": "",
    "city": "",
    "state": "",
    "phone": "",
    "email": "",
    "linkedInUrl": "",
    "websiteUrl": "",
    "gitHubUrl": ""
  },
  "summary": "",
  "experience": [
    {
      "id": "uuid-placeholder",
      "title": "",
      "company": "",
      "location": "",
      "startDate": "",
      "endDate": "",
      "isCurrent": false,
      "bullets": [
        {"text": "", "hasQuantifiableData": true}
      ],
      "entryType": "employment",
      "uncertaintyReason": "",
      "isAIPrefilled": true
    }
  ],
  "education": [
    {
      "id": "uuid-placeholder",
      "degree": "",
      "institution": "",
      "fieldOfStudy": "",
      "graduationYear": "",
      "gpa": null,
      "honors": null,
      "entryType": "degree",
      "uncertaintyReason": "",
      "isAIPrefilled": true
    }
  ],
  "skills": [
    {
      "id": "uuid-placeholder",
      "name": "",
      "category": "uncategorized",
      "skillType": "skill",
      "isAIPrefilled": true
    }
  ],
  "certifications": [
    {
      "id": "uuid-placeholder",
      "name": "",
      "issuer": "",
      "dateEarned": "",
      "expiresDate": null,
      "credentialId": null,
      "certType": "credential",
      "certUncertaintyReason": "",
      "isAIPrefilled": true
    }
  ],
  "unplacedFindings": [
    {
      "value": "",
      "context": ""
    }
  ]
}

Guidelines:
- Extract only what is present in the document. Leave fields empty string or empty array if not found.
- For military documents: map duty titles to experience.title, unit/organization to experience.company, duty descriptions/achievements to experience.bullets, MOS/training courses to certifications or skills.
- For skills, categorize as: technical, softSkill, toolsSoftware, or uncategorized. Tag every skill with skillType per the classification rules below.
- Each experience bullet is an object ({"text": ..., "hasQuantifiableData": ...}), not a bare string — see the bullet quality rule below for what belongs in "text" and how to set "hasQuantifiableData".
- Set isAIPrefilled to true for all extracted fields.
- UUID placeholders will be replaced by the app — use "uuid-placeholder" for all id fields.
- entryType, uncertaintyReason, certType, certUncertaintyReason, and skillType are always required — see the classification rules below for how to set them.
- unplacedFindings is required but usually empty ([]) — only populate it per the Unplaced Findings rule below.
- documentType is always required — see the Document Type rule below for the allowed values.
$_kEntryClassificationRules$_kMilitaryDocumentParsingRules''';

    final base64Pdf = base64Encode(pdfBytes);

    final body = jsonEncode({
      'model': _modelExtract,
      'max_tokens': 8000,
      'system': systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'document',
              'source': {
                'type': 'base64',
                'media_type': 'application/pdf',
                'data': base64Pdf,
              },
            },
            {
              'type': 'text',
              'text': 'Extract all resume and professional background information from this document.',
            },
          ],
        },
      ],
    });

    // Session cache (always on, production-safe) is checked first; a miss
    // falls through to the dev cache (dev-only, gated off by default),
    // which falls through to the real call.
    return SessionExtractionCache.cachedOrCall(
      label: 'extractResumeFieldsFromPdf',
      content: pdfBytes,
      call: () => DevExtractionCache.cachedOrCall(
        label: 'extractResumeFieldsFromPdf',
        content: pdfBytes,
        call: () async {
          try {
            final response = await client
                .post(
                  Uri.parse(AppConstants.cloudflareWorkerUrl),
                  headers: {
              'Content-Type': 'application/json',
              'X-BeaconAI-Secret': AppConstants.cloudflareWorkerSharedSecret,
            },
                  body: body,
                )
                .timeout(_webSearchTimeout);

            if (response.statusCode == 200) {
              final decoded =
                  jsonDecode(response.body) as Map<String, dynamic>;
              _logUsage('extractResumeFieldsFromPdf', _modelExtract, decoded);
              final content = decoded['content'] as List<dynamic>?;
              if (content != null && content.isNotEmpty) {
                final first = content.first as Map<String, dynamic>;
                return first['text'] as String? ?? '';
              }
              throw const CloudflareApiException(
                  'Empty response from Claude API');
            } else if (response.statusCode == 413) {
              throw const CloudflareApiException(
                  'PDF file is too large for direct analysis. Try uploading fewer pages.');
            } else {
              throw AiErrorMessages.forStatus(response.statusCode);
            }
          } on CloudflareApiException {
            rethrow;
          } catch (e) {
            throw AiErrorMessages.forTransport(e,
                timeoutMessage:
                    'Request timed out. The document may be too complex — try uploading fewer pages at a time.');
          }
        },
      ),
    );
  }

  // ── Image-based resume extraction (Claude vision) ────────────────────────

  /// Extracts structured resume data from an image (JPEG or PNG) using
  /// Claude's vision capability.
  ///
  /// Sends a multimodal content array — [{"type":"image",...}, {"type":"text",...}]
  /// — which is valid Anthropic Messages API format. The Cloudflare Worker
  /// acts as a transparent proxy: it adds the auth header and forwards the
  /// entire request body to Anthropic unchanged. No Worker-side changes are
  /// needed; the Worker already passes through arbitrary content arrays
  /// (confirmed by the web_search tools array in sendPromptWithWebSearch
  /// also being forwarded without modification).
  ///
  /// [mediaType] must be 'image/jpeg' or 'image/png'.
  /// Uses [_webSearchTimeout] (60 s) — image payloads are larger than text.
  static Future<String> extractResumeFieldsFromImage(
    List<int> imageBytes,
    String mediaType,
  ) async {
    _ensureAiAllowed();
    const systemPrompt = '''
You are an expert resume parser. Extract all resume information from the provided image and return it as a structured JSON object.

Return ONLY valid JSON with no explanation, no markdown, no code fences.

JSON structure to return:
{
  "documentType": "",
  "contact": {
    "firstName": "",
    "lastName": "",
    "professionalTitle": "",
    "city": "",
    "state": "",
    "phone": "",
    "email": "",
    "linkedInUrl": "",
    "websiteUrl": "",
    "gitHubUrl": ""
  },
  "summary": "",
  "experience": [
    {
      "id": "uuid-placeholder",
      "title": "",
      "company": "",
      "location": "",
      "startDate": "",
      "endDate": "",
      "isCurrent": false,
      "bullets": [
        {"text": "", "hasQuantifiableData": true}
      ],
      "entryType": "employment",
      "uncertaintyReason": "",
      "isAIPrefilled": true
    }
  ],
  "education": [
    {
      "id": "uuid-placeholder",
      "degree": "",
      "institution": "",
      "fieldOfStudy": "",
      "graduationYear": "",
      "gpa": null,
      "honors": null,
      "entryType": "degree",
      "uncertaintyReason": "",
      "isAIPrefilled": true
    }
  ],
  "skills": [
    {
      "id": "uuid-placeholder",
      "name": "",
      "category": "uncategorized",
      "skillType": "skill",
      "isAIPrefilled": true
    }
  ],
  "certifications": [
    {
      "id": "uuid-placeholder",
      "name": "",
      "issuer": "",
      "dateEarned": "",
      "expiresDate": null,
      "credentialId": null,
      "certType": "credential",
      "certUncertaintyReason": "",
      "isAIPrefilled": true
    }
  ],
  "unplacedFindings": [
    {
      "value": "",
      "context": ""
    }
  ]
}

Guidelines:
- Extract only what is visible in the image. Leave fields empty string or empty array if not found.
- For skills, categorize as: technical, softSkill, toolsSoftware, or uncategorized. Tag every skill with skillType per the classification rules below.
- Each experience bullet is an object ({"text": ..., "hasQuantifiableData": ...}), not a bare string — see the bullet quality rule below for what belongs in "text" and how to set "hasQuantifiableData".
- Set isAIPrefilled to true for all extracted fields.
- UUID placeholders will be replaced by the app — use "uuid-placeholder" for all id fields.
- entryType, uncertaintyReason, certType, certUncertaintyReason, and skillType are always required — see the classification rules below for how to set them.
- unplacedFindings is required but usually empty ([]) — only populate it per the Unplaced Findings rule below.
- documentType is always required — see the Document Type rule below for the allowed values.
$_kEntryClassificationRules$_kMilitaryDocumentParsingRules''';

    final base64Image = base64Encode(imageBytes);

    final body = jsonEncode({
      'model': _modelExtract,
      'max_tokens': 8000,
      'system': systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': mediaType,
                'data': base64Image,
              },
            },
            {
              'type': 'text',
              'text': 'Extract all resume information from this image.',
            },
          ],
        },
      ],
    });

    // Session cache (always on, production-safe) is checked first; a miss
    // falls through to the dev cache (dev-only, gated off by default),
    // which falls through to the real call.
    return SessionExtractionCache.cachedOrCall(
      label: 'extractResumeFieldsFromImage:$mediaType',
      content: imageBytes,
      call: () => DevExtractionCache.cachedOrCall(
        label: 'extractResumeFieldsFromImage:$mediaType',
        content: imageBytes,
        call: () async {
          try {
            final response = await client
                .post(
                  Uri.parse(AppConstants.cloudflareWorkerUrl),
                  headers: {
              'Content-Type': 'application/json',
              'X-BeaconAI-Secret': AppConstants.cloudflareWorkerSharedSecret,
            },
                  body: body,
                )
                .timeout(_webSearchTimeout);

            if (response.statusCode == 200) {
              final decoded =
                  jsonDecode(response.body) as Map<String, dynamic>;
              _logUsage('extractResumeFieldsFromImage:$mediaType',
                  _modelExtract, decoded);
              final content = decoded['content'] as List<dynamic>?;
              if (content != null && content.isNotEmpty) {
                final first = content.first as Map<String, dynamic>;
                return first['text'] as String? ?? '';
              }
              throw const CloudflareApiException(
                  'Empty response from Claude API');
            } else if (response.statusCode == 413) {
              throw const CloudflareApiException(
                  'Image file is too large. Please use an image under 5 MB.');
            } else {
              throw AiErrorMessages.forStatus(response.statusCode);
            }
          } on CloudflareApiException {
            rethrow;
          } catch (e) {
            throw AiErrorMessages.forTransport(e,
                timeoutMessage:
                    'Request timed out. Image analysis can take longer — please try again.');
          }
        },
      ),
    );
  }

  // ── Job posting extraction ────────────────────────────────────────────────

  /// Extracts structured data from a job posting text.
  /// Returns a JSON string containing the parsed job details.
  /// Used to pre-fill the tailored resume flow with role/company context.
  static Future<String> extractJobPosting(String rawJobPostingText) async {
    const systemPrompt = '''
You are an expert job posting parser. Extract all relevant information from the provided job posting and return it as a structured JSON object.

Return ONLY valid JSON with no explanation, no markdown, no code fences.

JSON structure to return:
{
  "jobTitle": "",
  "company": "",
  "location": "",
  "employmentType": "",
  "salaryRange": "",
  "summary": "",
  "responsibilities": [],
  "requiredSkills": [],
  "preferredSkills": [],
  "requiredQualifications": [],
  "preferredQualifications": []
}

Guidelines:
- Extract only what is explicitly stated in the posting. Leave fields as empty string or empty array if not found.
- For requiredSkills and preferredSkills, extract individual skill names as strings.
- For responsibilities and qualifications, extract individual items as strings.
- employmentType values: "full-time", "part-time", "contract", "internship", or "" if not specified.
- Do not infer or embellish — only extract what is present in the text.
''';

    final sanitized = sanitize(rawJobPostingText);
    final userMessage =
        'Extract all relevant information from this job posting:\n\n${wrap(sanitized)}';

    return sendPrompt(
      callLabel: 'extractJobPosting(dead-CloudflareWorkerService)',
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      maxTokens: 2000,
    );
  }

  // ── Entry classification ────────────────────────────────────────────────
  //
  // Routes each extracted entry using the model's entryType/certType field
  // (set per _kEntryClassificationRules — general, applies to every user).
  // The keyword lists in ResumeSanitizer only fire when the model didn't
  // return a recognized classification for an entry — a defensive backstop,
  // never the primary signal.

  /// Splits raw experience entries into confident employment entries,
  /// entries promoted to certifications (training/school entries), and
  /// entries the model could not confidently classify.
  static ({
    List<dynamic> employment,
    List<dynamic> promotedCerts,
    List<PendingEntryDecision> pending,
  }) _classifyExperienceEntries(List<dynamic> entries) {
    final employment = <dynamic>[];
    final promotedCerts = <dynamic>[];
    final pending = <PendingEntryDecision>[];

    for (final raw in entries) {
      final e = raw as Map<String, dynamic>;
      final company = e['company'] as String? ?? '';
      final title = e['title'] as String? ?? '';
      final bullets = ResumeSanitizer.normalizeBulletList(e['bullets'])
          .map((b) => b['text'] as String)
          .toList();

      var entryType = e['entryType'] as String?;
      final fromFallback = entryType != 'employment' &&
          entryType != 'education_training' &&
          entryType != 'uncertain';
      if (fromFallback) {
        final isTraining = ResumeSanitizer.fallbackTrainingCompanyPatterns
                .any((p) => company.toLowerCase().contains(p)) ||
            ResumeSanitizer.fallbackTrainingTitlePatterns
                .any((p) => title.toLowerCase().contains(p));
        entryType = isTraining ? 'education_training' : 'employment';
      }

      switch (entryType) {
        case 'education_training':
          promotedCerts.add({
            'id': 'uuid-placeholder',
            'name': title,
            'issuer': company,
            'dateEarned': ResumeSanitizer.coerceToString(e['startDate']) ?? '',
            'expiresDate': null,
            'credentialId': null,
            'isAIPrefilled': true,
          });
          devLog('[CLASSIFY] experience → training, moved to '
              'certifications ${fromFallback ? '(fallback keyword list)' : '(model)'}: $title @ $company');
        case 'uncertain':
          final reason = (e['uncertaintyReason'] as String?)?.trim();
          pending.add(PendingEntryDecision(
            id: _uuid.v4(),
            rawTitle: title,
            rawCompany: company,
            rawBullets: bullets,
            uncertaintyReason: (reason == null || reason.isEmpty)
                ? 'Not sure if this is a job or training.'
                : reason,
            kind: PendingDecisionKind.employmentVsTraining,
            rawEntry: e,
          ));
          devLog('[CLASSIFY] experience → uncertain (model): $title @ $company');
        default: // 'employment'
          devLog('[CLASSIFY] experience → employment '
              '${fromFallback ? '(fallback keyword list)' : '(model)'}: $title @ $company');
          // Bullet cap intentionally does NOT run here — it runs once, in
          // parseFieldMappings, after dedup. Capping before dedup and
          // capping after dedup can select different bullets when two
          // duplicate entries get merged, so cap must be the last step
          // against the final deduped list, not applied per-entry this
          // early.
          employment.add(e);
      }
    }

    return (employment: employment, promotedCerts: promotedCerts, pending: pending);
  }

  /// Splits raw education entries into confident degree entries, entries
  /// promoted to certifications (non-degree training/certificate programs),
  /// and entries the model could not confidently classify. Same structural
  /// pattern as [_classifyExperienceEntries] and [_classifyCertifications]:
  /// structured field first, fallback keyword list only when the field is
  /// missing/invalid, pending decision for genuine ambiguity — never a
  /// silent guess. Fallback keyword matching only ever resolves to "degree"
  /// or "non_degree_training" (never "uncertain") — same precedent as
  /// award_recognition below: novel/ambiguous categories are
  /// model-classification-only, not something a keyword list should guess at.
  static ({
    List<dynamic> degrees,
    List<dynamic> promotedCerts,
    List<PendingEntryDecision> pending,
  }) _classifyEducationEntries(List<dynamic> entries) {
    final degrees = <dynamic>[];
    final promotedCerts = <dynamic>[];
    final pending = <PendingEntryDecision>[];

    for (final raw in entries) {
      final e = raw as Map<String, dynamic>;
      final institution = e['institution'] as String? ?? '';
      final degree = e['degree'] as String? ?? '';

      var entryType = e['entryType'] as String?;
      final fromFallback = entryType != 'degree' &&
          entryType != 'non_degree_training' &&
          entryType != 'uncertain';
      if (fromFallback) {
        final isTraining = ResumeSanitizer.fallbackNonDegreeInstitutionPatterns
            .any((p) => institution.toLowerCase().contains(p));
        entryType = isTraining ? 'non_degree_training' : 'degree';
      }

      switch (entryType) {
        case 'non_degree_training':
          promotedCerts.add({
            'id': 'uuid-placeholder',
            'name': degree.isNotEmpty ? degree : institution,
            'issuer': institution,
            'dateEarned': ResumeSanitizer.coerceToString(e['graduationYear']) ?? '',
            'expiresDate': null,
            'credentialId': null,
            'isAIPrefilled': true,
          });
          devLog('[CLASSIFY] education → non-degree training, moved to '
              'certifications ${fromFallback ? '(fallback keyword list)' : '(model)'}: $institution');
        case 'uncertain':
          final reason = (e['uncertaintyReason'] as String?)?.trim();
          pending.add(PendingEntryDecision(
            id: _uuid.v4(),
            rawTitle: degree,
            rawCompany: institution,
            rawBullets: const [],
            uncertaintyReason: (reason == null || reason.isEmpty)
                ? 'Not sure if this is a degree program or non-degree training.'
                : reason,
            kind: PendingDecisionKind.degreeVsNonDegreeTraining,
            rawEntry: e,
          ));
          devLog('[CLASSIFY] education → uncertain (model): $institution');
        default: // 'degree'
          devLog('[CLASSIFY] education → degree '
              '${fromFallback ? '(fallback keyword list)' : '(model)'}: $institution');
          degrees.add(e);
      }
    }

    return (degrees: degrees, promotedCerts: promotedCerts, pending: pending);
  }

  /// Filters out skills the model tagged (or the fallback structurally
  /// detected) as literal course/curriculum titles rather than genuine
  /// demonstrated skills. Defaults to KEEPING a skill when skillType is
  /// missing/invalid or the fallback pattern doesn't match — this fix is
  /// about trimming clutter, not risking a real skill being silently
  /// dropped, so the bias runs the opposite direction from the
  /// credential-vs-compliance-training check above.
  static List<dynamic> _classifySkills(List<dynamic> entries) {
    final kept = <dynamic>[];
    for (final raw in entries) {
      final e = raw as Map<String, dynamic>;
      final name = e['name'] as String? ?? '';

      var skillType = e['skillType'] as String?;
      if (skillType != 'skill' && skillType != 'course_title') {
        final looksLikeCourseTitle = ResumeSanitizer.fallbackCourseTitlePrefixes
            .any((p) => name.toLowerCase().startsWith(p));
        skillType = looksLikeCourseTitle ? 'course_title' : 'skill';
      }

      if (skillType == 'course_title') {
        devLog('[CLASSIFY] skill → course title, excluded: $name');
      } else {
        kept.add(e);
      }
    }
    return kept;
  }

  /// Splits candidate certifications (raw + those promoted from experience/
  /// education) into confident credentials and entries the model could not
  /// confidently classify. compliance_training entries are dropped — same
  /// end result as before, just decided by content instead of a keyword list.
  static ({List<dynamic> credentials, List<PendingEntryDecision> pending})
      _classifyCertifications(List<dynamic> certs) {
    final credentials = <dynamic>[];
    final pending = <PendingEntryDecision>[];

    for (final raw in certs) {
      final c = raw as Map<String, dynamic>;
      final name = c['name'] as String? ?? '';

      var certType = c['certType'] as String?;
      final fromFallback = certType != 'credential' &&
          certType != 'compliance_training' &&
          certType != 'award_recognition' &&
          certType != 'uncertain';
      if (fromFallback) {
        // award_recognition has no fallback keyword list on purpose — award
        // names vary too much by field to safely pattern-match, and this
        // fix is specifically about NOT building that kind of list. It's
        // model-classification-only; anything the model doesn't tag stays
        // on the safer, established compliance-training fallback path.
        final isCompliance = ResumeSanitizer.fallbackComplianceCertPatterns
            .any((p) => name.toLowerCase().contains(p));
        certType = isCompliance ? 'compliance_training' : 'credential';
      }

      switch (certType) {
        case 'compliance_training':
          devLog('[CLASSIFY] cert dropped as compliance training '
              '${fromFallback ? '(fallback keyword list)' : '(model)'}: $name');
        case 'award_recognition':
          // No fallback path can produce this (see comment above), so it's
          // always model-classified — no need to print the origin.
          devLog('[CLASSIFY] cert dropped as award/recognition '
              '(not a certification, model): $name');
        case 'uncertain':
          final reason = (c['certUncertaintyReason'] as String?)?.trim();
          pending.add(PendingEntryDecision(
            id: _uuid.v4(),
            rawTitle: name,
            rawCompany: c['issuer'] as String? ?? '',
            rawBullets: const [],
            uncertaintyReason: (reason == null || reason.isEmpty)
                ? 'Not sure if this is a real credential or routine compliance training.'
                : reason,
            kind: PendingDecisionKind.credentialVsCompliance,
            rawEntry: c,
          ));
          devLog('[CLASSIFY] cert → uncertain (model): $name');
        default: // 'credential'
          devLog('[CLASSIFY] cert → credential '
              '${fromFallback ? '(fallback keyword list)' : '(model)'}: $name');
          credentials.add(c);
      }
    }

    return (credentials: credentials, pending: pending);
  }

  // ── Field mapping confidence scoring ──────────────────────────────────────

  /// Parses extracted JSON and returns field mapping suggestions with
  /// confidence scores, plus any entries the model could not confidently
  /// classify (surfaced to the user via a pending-decision card — never
  /// silently guessed). Ephemeral — never persisted.
  static ExtractionParseResult parseFieldMappings(String extractedJson) {
    try {
      final cleaned = stripMarkdownFences(extractedJson);
      // Sanitize every string in the decoded response before it can reach
      // a Hive-backed content field — Claude's own rewriting can introduce
      // a blocked character (e.g. turning a source comma into a semicolon)
      // that the user never typed and can't explain when they hit the
      // field-validation error for it.
      final data = ResumeSanitizer.sanitizeAiJson(jsonDecode(cleaned))
          as Map<String, dynamic>;
      final suggestions = <Map<String, dynamic>>[];
      final pendingDecisions = <PendingEntryDecision>[];

      void addIfNotEmpty(String field, dynamic value, double confidence) {
        if (value == null) return;
        if (value is String && value.isEmpty) return;
        if (value is List && value.isEmpty) return;
        suggestions.add({
          'field': field,
          'suggestedValue': value,
          'confidence': confidence,
          'accepted': true,
        });
      }

      final contact = data['contact'] as Map<String, dynamic>? ?? {};
      addIfNotEmpty('contact.firstName', contact['firstName'], 0.95);
      addIfNotEmpty('contact.lastName', contact['lastName'], 0.95);
      addIfNotEmpty(
          'contact.professionalTitle', contact['professionalTitle'], 0.90);
      addIfNotEmpty('contact.city', contact['city'], 0.85);
      addIfNotEmpty('contact.state', contact['state'], 0.85);
      addIfNotEmpty('contact.phone', contact['phone'], 0.90);
      addIfNotEmpty('contact.email', contact['email'], 0.95);
      // A .mil email stops working after separation from service — flag it
      // as an informational nudge (never blocking) so the user thinks about
      // adding a personal/civilian address before this becomes their sole
      // contact method on the resume.
      final email = contact['email'] as String?;
      if (email != null && email.toLowerCase().trim().endsWith('.mil')) {
        final emailSuggestion = suggestions.lastWhere(
            (s) => s['field'] == 'contact.email',
            orElse: () => <String, dynamic>{});
        emailSuggestion['milEmailWarning'] = true;
      }
      addIfNotEmpty('contact.linkedInUrl', contact['linkedInUrl'], 0.85);
      addIfNotEmpty('contact.websiteUrl', contact['websiteUrl'], 0.80);
      addIfNotEmpty('contact.gitHubUrl', contact['gitHubUrl'], 0.80);
      addIfNotEmpty('summary', data['summary'], 0.85);

      // ── Single final sanitize pass ──────────────────────────────────────
      // Exactly one ordered pass over the fully merged raw lists (this is
      // the last step before Hive, regardless of whether the caller's json
      // came from a single call or a multi-chunk merge):
      //   1. classify every raw entry (entryType / certType)
      //   2. route education_training/non_degree_training OUT of
      //      experience/education and into certifications
      //   3. THEN dedup what remains in each list
      //   4. THEN cap bullets on what survives dedup
      // Steps must stay in this order — deduping before classification (or
      // capping before dedup) is exactly the ordering bug that let a bare
      // stub and a misclassified duplicate survive a fresh extraction
      // alongside a correctly-classified certification for the same event.

      // Step 1 + 2: classify and route.
      final rawExperience = data['experience'] as List<dynamic>? ?? [];
      final expResult = _classifyExperienceEntries(rawExperience);
      pendingDecisions.addAll(expResult.pending);

      final rawEducation = data['education'] as List<dynamic>? ?? [];
      final eduResult = _classifyEducationEntries(rawEducation);
      pendingDecisions.addAll(eduResult.pending);
      // Completion-aware dedup: a degree extracted at multiple levels of
      // completeness (bare, in-progress, completed) across document
      // sections collapses to one entry — the completed one wins.
      final dedupedEducation =
          ResumeSanitizer.deduplicateEducation(eduResult.degrees);
      addIfNotEmpty('education', dedupedEducation, 0.90);

      // Exclude skills classified as literal course/curriculum titles
      // (e.g. from a transcript) rather than genuine demonstrated skills.
      // Soft count guidance (surfacing when the list runs well past the
      // app's 8-12 target range) is computed at render time in
      // DocumentUploadScreen — see _MappingRow — rather than here, since a
      // multi-file merge rebuilds this suggestion row from scratch and
      // would otherwise need to separately thread this note through too.
      final rawSkills = data['skills'] as List<dynamic>? ?? [];
      final classifiedSkills = _classifySkills(rawSkills);
      addIfNotEmpty('skills', classifiedSkills, 0.85);

      final rawCerts = data['certifications'] as List<dynamic>? ?? [];
      final allCertCandidates = ResumeSanitizer.deduplicateCertifications([
        ...rawCerts,
        ...expResult.promotedCerts,
        ...eduResult.promotedCerts,
      ]);
      final certResult = _classifyCertifications(allCertCandidates);
      addIfNotEmpty('certifications', certResult.credentials, 0.88);
      pendingDecisions.addAll(certResult.pending);

      // Step 3: dedup experience — bare-stub duplicates first, then
      // substantive entries that describe the same real-world role
      // recorded twice (e.g. from different sections of the same
      // document), then entries that duplicate an event already correctly
      // classified as a certification (computed just above, so this always
      // runs against the FINAL certifications list, never an intermediate
      // one).
      final dedupedExperience =
          ResumeSanitizer.discardBareDuplicateExperience(expResult.employment);
      final mergedExperience =
          ResumeSanitizer.mergeCrossDocumentDuplicateRoles(dedupedExperience);
      final finalExperienceEntries = ResumeSanitizer.dropExperienceMatchingCertification(
          mergedExperience, certResult.credentials);

      // Step 4: normalize bullet shape on whatever survived dedup. This
      // function (parseFieldMappings) only ever runs against document-
      // upload extraction results — there is no code path that reaches it
      // for Tailored Resume generation (that flow operates on already-
      // structured ResumeRenderData, never re-extracts from documents) —
      // so this is unconditionally Master Resume construction. No bullet
      // cap here per Stage 9: Master Resumes are exhaustive with no page
      // limit. See ResumeSanitizer.capBullets's doc comment for where
      // capping legitimately still belongs (Tailored Resume paths only).
      final finalExperience = finalExperienceEntries.map((raw) {
        final e = Map<String, dynamic>.from(raw as Map<String, dynamic>);
        e['bullets'] = ResumeSanitizer.normalizeBulletList(e['bullets']);
        return e;
      }).toList();

      addIfNotEmpty('experience', finalExperience, 0.88);

      suggestions.sort((a, b) =>
          (b['confidence'] as double).compareTo(a['confidence'] as double));

      final rawUnplacedFindings =
          data['unplacedFindings'] as List<dynamic>? ?? [];
      final unplacedFindings = rawUnplacedFindings
          .map((raw) {
            final f = raw as Map<String, dynamic>;
            return UnplacedFinding(
              id: _uuid.v4(),
              value: (f['value'] as String? ?? '').trim(),
              context: (f['context'] as String? ?? '').trim(),
            );
          })
          .where((f) => f.value.isNotEmpty)
          .toList();

      final documentType = (data['documentType'] as String?)?.trim();

      devLog('[parseFieldMappings] OK — ${suggestions.length} fields mapped, '
          '${pendingDecisions.length} pending decisions, '
          '${unplacedFindings.length} unplaced findings, '
          'documentType: $documentType');
      return ExtractionParseResult(
          mappings: suggestions,
          pendingDecisions: pendingDecisions,
          unplacedFindings: unplacedFindings,
          documentType:
              (documentType != null && documentType.isNotEmpty) ? documentType : null);
    } catch (e) {
      devLog('[parseFieldMappings] PARSE ERROR: $e');
      devLog('[parseFieldMappings] raw (first 600): '
          '${extractedJson.length > 600 ? extractedJson.substring(0, 600) : extractedJson}');
      return const ExtractionParseResult(mappings: [], pendingDecisions: []);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ExtractionParseResult  (ephemeral — NEVER persisted to Hive)
// ─────────────────────────────────────────────────────────────────────────────

/// Result of [CloudflareWorkerService.parseFieldMappings]: confident field
/// mappings plus any entries the model flagged as uncertain, to be resolved
/// by the user via a pending-decision card rather than guessed.
class ExtractionParseResult {
  const ExtractionParseResult({
    required this.mappings,
    required this.pendingDecisions,
    this.unplacedFindings = const [],
    this.documentType,
  });

  final List<Map<String, dynamic>> mappings;
  final List<PendingEntryDecision> pendingDecisions;

  /// Numbers/claims Claude found but couldn't confidently map to a
  /// structured field — surfaced on the confirmation screen for the user
  /// to place or discard, never silently dropped or folded into prose.
  final List<UnplacedFinding> unplacedFindings;

  /// One of ResumeSanitizer's SourceDocType raw values ('stp', 'ncoer',
  /// 'jst', 'transcript', 'civilian_resume', 'award_recommendation',
  /// 'equipment_qualification', 'training_certificate', 'other') as
  /// reported by the extraction model for this document, or null if
  /// parsing failed before
  /// this could be read. Used to break field-level conflicts between
  /// documents by source authority — see ResumeSanitizer's priority tables.
  final String? documentType;
}

// ─────────────────────────────────────────────────────────────────────────────
// CloudflareApiException
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown instead of calling the Worker while the stored age bracket blocks AI
/// (age-assurance restricted mode). Message is the same neutral copy as the
/// one-time notice.
class AiRestrictedException extends CloudflareApiException {
  const AiRestrictedException()
      : super(AppConstants.ageRestrictionNoticeBody);
}

class CloudflareApiException implements Exception {
  const CloudflareApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The AI server answered, but not with something the app can use: the
/// endpoint is missing (404), rejects the app (401/403/405), or is failing
/// (5xx). Nothing the user can fix on their side, so the message says the
/// service is down rather than showing a raw status code.
class AiServiceUnavailableException extends CloudflareApiException {
  const AiServiceUnavailableException(this.statusCode)
      : super(AiErrorMessages.serviceUnavailable);
  final int statusCode;
}

/// The request never got an answer: no network, DNS failure, TLS failure,
/// connection reset.
class AiServiceUnreachableException extends CloudflareApiException {
  const AiServiceUnreachableException() : super(AiErrorMessages.unreachable);
}

class AiErrorMessages {
  AiErrorMessages._();

  static const String serviceUnavailable =
      "BeaconAI's AI service isn't responding right now. Nothing you've "
      'entered was lost — please try again in a little while.';
  static const String unreachable =
      "Can't reach BeaconAI's AI service. Check your internet connection "
      'and try again.';
  static const String tooManyRequests =
      'Too many requests. Please wait a moment and try again.';
  static const String badRequest =
      "The AI service couldn't process this request. Please try again.";

  /// Error for a non-200 response. Call sites handle their own special cases
  /// (e.g. 413 for oversized files) before falling back to this.
  static CloudflareApiException forStatus(int status) {
    if (status == 429) return const CloudflareApiException(tooManyRequests);
    if (status == 400 || status == 422) {
      return const CloudflareApiException(badRequest);
    }
    return AiServiceUnavailableException(status);
  }

  /// Error for a request that threw before a response arrived.
  static CloudflareApiException forTransport(Object error,
      {required String timeoutMessage}) {
    if (error is TimeoutException) {
      return CloudflareApiException(timeoutMessage);
    }
    // package:http surfaces socket, DNS and TLS failures as ClientException
    // on mobile and in the browser alike (no dart:io needed here, which
    // would break the web build).
    return const AiServiceUnreachableException();
  }
}

/// Thrown by [CloudflareWorkerService.sendPrompt] when the API's own
/// `stop_reason` field reports `max_tokens` — i.e. generation was cut off
/// mid-output because it hit the token cap, not because anything actually
/// went wrong with the request. A truncated response is not valid JSON
/// (e.g. "Unterminated string in JSON at position N", where N lines up
/// exactly with the response's char length), and downstream JSON parsing
/// would otherwise report that as a generic, indistinguishable parse
/// failure. Callers that care (see generateTailoredResume's Call 2) can
/// catch this specifically to give the user an accurate, actionable
/// message instead of a generic "something went wrong."
class CloudflareTruncatedResponseException extends CloudflareApiException {
  const CloudflareTruncatedResponseException(this.maxTokens)
      : super('Response was cut off after reaching the $maxTokens-token '
            'limit before it could finish.');
  final int maxTokens;
}
