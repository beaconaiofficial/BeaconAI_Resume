import 'dart:convert';
import '../services/cloudflare_worker_service.dart';
import '../services/resume_sanitizer.dart';
import '../widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Phase3ApiService
//
// Pro-tier Claude API calls for the AI Suggestions panel.
// Rule §1: All calls go through CloudflareWorkerService — never direct to Anthropic.
// Rule §3: User always reviews and taps to accept — no auto-overwrite.
// Spec §9: Bullet rewriter returns 3 alternatives. Summary generator needs
//          target role, top skills, achievement, JD keywords. Skill gap
//          analysis compares resume skills vs JD, suggests additions.
// ─────────────────────────────────────────────────────────────────────────────

class Phase3ApiService {
  Phase3ApiService._();

  // ── Bullet Rewriter ────────────────────────────────────────────────────────

  /// Returns 2-3 alternative phrasings of a single experience bullet.
  /// Each alternative preserves the underlying facts — never invents new claims.
  static Future<List<String>> rewriteBullet({
    required String currentBullet,
    required String jobTitle,
    String? targetJobDescription,
  }) async {
    const systemPrompt = '''
You are an expert resume writer. Rewrite the given bullet point using the STAR method
(Situation, Task, Action, Result) to make it more impactful, while preserving every
factual claim exactly as given — never invent new accomplishments, numbers, or scope.

Return ONLY a valid JSON array of 3 alternative phrasings, no explanation, no markdown.

JSON structure:
["alternative 1", "alternative 2", "alternative 3"]

Guidelines:
- Each alternative should take a different angle: one emphasizing the action taken,
  one emphasizing the measurable result, one emphasizing the scope/scale
- Use strong action verbs, avoid passive voice
- Keep each alternative roughly the same length as the original
- If a target job description is provided, naturally weave in relevant terminology
  from it — but only where it accurately describes what the bullet already says
- Never add numbers, percentages, or metrics that were not present in the original bullet

${ResumeSanitizer.noBlockedCharsPromptRule}
''';

    final sanitizedBullet = CloudflareWorkerService.sanitize(currentBullet);
    final sanitizedTitle = CloudflareWorkerService.sanitize(jobTitle);

    var userMessage =
        'Original bullet (for job title "${CloudflareWorkerService.wrap(sanitizedTitle)}"):\n'
        '${CloudflareWorkerService.wrap(sanitizedBullet)}';

    if (targetJobDescription != null && targetJobDescription.isNotEmpty) {
      final sanitizedJD =
          CloudflareWorkerService.sanitize(targetJobDescription);
      userMessage +=
          '\n\nTarget job description for context:\n${CloudflareWorkerService.wrap(sanitizedJD)}';
    }

    final response = await CloudflareWorkerService.sendPrompt(
      systemPrompt: systemPrompt,
      userMessage: '$userMessage\n\nGenerate 3 alternative phrasings:',
      maxTokens: 800,
    );

    try {
      final list = jsonDecode(response) as List<dynamic>;
      return list
          .map((e) => ResumeSanitizer.sanitizeAiText(e.toString()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Summary Generator ──────────────────────────────────────────────────────

  /// Generates 2-3 alternative professional summaries.
  /// Spec §9: needs target role, top skills, achievement, JD keywords.
  static Future<List<String>> generateSummaryOptions({
    required String targetRole,
    required List<String> topSkills,
    required String keyAchievement,
    List<String> jdKeywords = const [],
  }) async {
    const systemPrompt = '''
You are an expert resume writer. Write 3 alternative professional summaries (elevator pitches).

Each summary must be 3-4 sentences and include: years of experience or seniority level
(infer reasonably from context if not explicit), top skills, one key accomplishment,
and a forward-looking statement about what the candidate brings to a new role.

Return ONLY a valid JSON array of 3 summary alternatives, no explanation, no markdown.

JSON structure:
["summary 1", "summary 2", "summary 3"]

Guidelines:
- Each alternative should have a distinct opening approach: one leading with role/title,
  one leading with the key achievement, one leading with core skill set
- Integrate the provided keywords naturally — never keyword-stuff
- Never invent accomplishments, years of experience, or skills not provided
- Keep each summary between 300-500 characters

${ResumeSanitizer.noBlockedCharsPromptRule}
''';

    final sanitizedRole = CloudflareWorkerService.sanitize(targetRole);
    final sanitizedSkills =
        CloudflareWorkerService.sanitize(topSkills.join(', '));
    final sanitizedAchievement =
        CloudflareWorkerService.sanitize(keyAchievement);
    final sanitizedKeywords =
        CloudflareWorkerService.sanitize(jdKeywords.join(', '));

    final userMessage = '''
Target role: ${CloudflareWorkerService.wrap(sanitizedRole)}
Top skills: ${CloudflareWorkerService.wrap(sanitizedSkills)}
Key achievement: ${CloudflareWorkerService.wrap(sanitizedAchievement)}
${jdKeywords.isNotEmpty ? 'Keywords to integrate: ${CloudflareWorkerService.wrap(sanitizedKeywords)}' : ''}

Generate 3 summary alternatives:
''';

    final response = await CloudflareWorkerService.sendPrompt(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      maxTokens: 1000,
    );

    try {
      final list = jsonDecode(response) as List<dynamic>;
      return list
          .map((e) => ResumeSanitizer.sanitizeAiText(e.toString()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Skill Gap Analysis ─────────────────────────────────────────────────────

  /// Compares the resume's current skills against a job description and
  /// suggests additions the candidate may be missing. Never auto-applies —
  /// returns suggestions for the user to review and add manually.
  static Future<SkillGapResult> analyzeSkillGap({
    required ResumeRenderData resumeData,
    required String jobDescription,
  }) async {
    final currentSkills = resumeData.skills.map((s) => s.name).toList();
    final experienceSummary =
        resumeData.experience.expand((e) => [e.title, ...e.bullets]).join(' ');

    const systemPrompt = '''
You are an expert career coach analyzing skill alignment between a candidate's resume
and a target job description.

Return ONLY valid JSON with no explanation, no markdown, no code fences.

JSON structure:
{
  "matchedSkills": [],
  "missingSkills": [],
  "suggestedAdditions": [],
  "transferableSkills": []
}

Where:
- matchedSkills: skills already listed on the resume that match the job description
- missingSkills: important skills/technologies from the JD that are NOT in the resume's
  skills list, but where the experience bullets suggest the candidate likely has the
  skill and simply didn't list it explicitly — these are safe, evidence-based suggestions
- suggestedAdditions: skills explicitly required by the JD with no supporting evidence
  in the resume at all — flagged as a gap the candidate may want to address, not
  something to silently add
- transferableSkills: skills the candidate has that aren't explicitly requested in the
  JD but are highly relevant and worth highlighting

CRITICAL: Only include a skill in missingSkills if there is clear supporting evidence
in the experience bullets that the candidate has used or demonstrated it. Do not guess
or assume skills the candidate has not demonstrated.

${ResumeSanitizer.noBlockedCharsPromptRule}
''';

    final sanitizedSkills =
        CloudflareWorkerService.sanitize(currentSkills.join(', '));
    final sanitizedExperience =
        CloudflareWorkerService.sanitize(experienceSummary);
    final sanitizedJD = CloudflareWorkerService.sanitize(jobDescription);

    final userMessage = '''
Current resume skills: ${CloudflareWorkerService.wrap(sanitizedSkills)}

Resume experience content: ${CloudflareWorkerService.wrap(sanitizedExperience)}

Target job description: ${CloudflareWorkerService.wrap(sanitizedJD)}

Analyze the skill gap:
''';

    final response = await CloudflareWorkerService.sendPrompt(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      maxTokens: 1200,
    );

    try {
      final data = ResumeSanitizer.sanitizeAiJson(jsonDecode(response))
          as Map<String, dynamic>;
      return SkillGapResult.fromJson(data);
    } catch (_) {
      return const SkillGapResult(
        matchedSkills: [],
        missingSkills: [],
        suggestedAdditions: [],
        transferableSkills: [],
      );
    }
  }

  // ── Pro Interview Guide ────────────────────────────────────────────────────

  /// Generates 10-15 personalized interview questions for Pro users.
  /// Uses web search to research the actual company and role before writing
  /// company-specific questions. Categories match QuestionCategoryEnum:
  /// "behavioral" (~4-5), "roleSpecific" (~4-5), "companySpecific" (~2-3).
  static Future<List<RawInterviewQuestion>> generateProInterviewGuide({
    required String jobDescription,
    required String resumeSummary,
    required List<String> resumeSkills,
    required String resumeExperience,
  }) async {
    const systemPrompt = '''
You are an expert career coach preparing candidates for job interviews.

STEP 1 — Research: Use web_search to look up the company and role from the job
description. Find recent news, the company's mission, culture, products, and any
known interview style. NEVER invent or guess company details — only use what you
actually find via search.

STEP 2 — Generate exactly 10-15 interview questions, distributed as follows:
  - 4-5 questions with category "behavioral"
  - 4-5 questions with category "roleSpecific"
  - 2-3 questions with category "companySpecific" (grounded in your search findings)

STEP 3 — For every question, write an answerGuide that:
  - References specific content from the candidate's resume (named skills, actual
    experience bullets, job titles) — never give generic advice
  - For behavioral questions: structure the guide around STAR (Situation, Task,
    Action, Result) and call out a real experience from the resume to draw from
  - For companySpecific questions: reference what you found about the company in
    your search

Return ONLY a valid JSON array with NO surrounding text, NO markdown, NO code fences.

Exact JSON structure (use these exact category string values):
[
  {
    "category": "behavioral",
    "questionText": "...",
    "answerGuide": "..."
  },
  {
    "category": "roleSpecific",
    "questionText": "...",
    "answerGuide": "..."
  },
  {
    "category": "companySpecific",
    "questionText": "...",
    "answerGuide": "..."
  }
]

Category values MUST be exactly one of: "behavioral", "roleSpecific", "companySpecific".
Never fabricate resume facts or company facts not found via search.

${ResumeSanitizer.noBlockedCharsPromptRule}
''';

    final sanitizedSummary = CloudflareWorkerService.sanitize(resumeSummary);
    final sanitizedSkills =
        CloudflareWorkerService.sanitize(resumeSkills.join(', '));
    final sanitizedExperience =
        CloudflareWorkerService.sanitize(resumeExperience);
    final sanitizedJD = CloudflareWorkerService.sanitize(jobDescription);

    final userMessage = '''
Candidate summary: ${CloudflareWorkerService.wrap(sanitizedSummary)}

Candidate skills: ${CloudflareWorkerService.wrap(sanitizedSkills)}

Candidate experience: ${CloudflareWorkerService.wrap(sanitizedExperience)}

Job description: ${CloudflareWorkerService.wrap(sanitizedJD)}

Generate interview questions:
''';

    final response = await CloudflareWorkerService.sendPromptWithWebSearch(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      maxTokens: 4500,
    );

    try {
      final jsonStart = response.indexOf('[');
      final jsonEnd = response.lastIndexOf(']');
      final jsonStr = (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart)
          ? response.substring(jsonStart, jsonEnd + 1)
          : response;
      final list = ResumeSanitizer.sanitizeAiJson(jsonDecode(jsonStr)) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(RawInterviewQuestion.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Company / Role Extractor ───────────────────────────────────────────────

  /// Extracts company name and job title from raw job posting text.
  /// Returns a map with keys "company" and "role"; either may be empty if
  /// the information cannot be determined from the posting.
  static Future<Map<String, String>> extractCompanyAndRole({
    required String jobPostingText,
  }) async {
    const systemPrompt = '''
Extract the company name and job title from the job posting.

Return ONLY valid JSON with no explanation, no markdown.

JSON structure:
{"company": "...", "role": "..."}

If either value cannot be determined, use an empty string.

${ResumeSanitizer.noBlockedCharsPromptRule}
''';

    final sanitizedText = CloudflareWorkerService.sanitize(jobPostingText);

    final response = await CloudflareWorkerService.sendPrompt(
      systemPrompt: systemPrompt,
      userMessage: CloudflareWorkerService.wrap(sanitizedText),
      maxTokens: 200,
    );

    try {
      final data = ResumeSanitizer.sanitizeAiJson(jsonDecode(response))
          as Map<String, dynamic>;
      return {
        'company': data['company'] as String? ?? '',
        'role': data['role'] as String? ?? '',
      };
    } catch (_) {
      return {'company': '', 'role': ''};
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RawInterviewQuestion
// ─────────────────────────────────────────────────────────────────────────────

class RawInterviewQuestion {
  const RawInterviewQuestion({
    required this.category,
    required this.questionText,
    this.answerGuide,
  });

  final String category;
  final String questionText;
  final String? answerGuide;

  factory RawInterviewQuestion.fromJson(Map<String, dynamic> json) {
    return RawInterviewQuestion(
      category: json['category'] as String? ?? '',
      questionText: json['questionText'] as String? ?? '',
      answerGuide: json['answerGuide'] as String?,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class SkillGapResult {
  const SkillGapResult({
    required this.matchedSkills,
    required this.missingSkills,
    required this.suggestedAdditions,
    required this.transferableSkills,
  });

  final List<String> matchedSkills;
  final List<String> missingSkills;
  final List<String> suggestedAdditions;
  final List<String> transferableSkills;

  factory SkillGapResult.fromJson(Map<String, dynamic> json) {
    List<String> toList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : [];

    return SkillGapResult(
      matchedSkills: toList(json['matchedSkills']),
      missingSkills: toList(json['missingSkills']),
      suggestedAdditions: toList(json['suggestedAdditions']),
      transferableSkills: toList(json['transferableSkills']),
    );
  }
}
