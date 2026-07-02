import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/resume_sections.dart';
import '../services/cloudflare_worker_service.dart';
import '../services/resume_sanitizer.dart';
import '../widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Phase2ApiService
//
// All Claude API calls for Phase 2 features.
// Rule §1: All calls go through CloudflareWorkerService — never direct to Anthropic.
// Rule §3: User always reviews before applying — no auto-overwrite.
// Rule §9: Always validate input on save — never silently strip.
// ─────────────────────────────────────────────────────────────────────────────

class Phase2ApiService {
  Phase2ApiService._();

  // ── Job Posting Extraction ─────────────────────────────────────────────────

  /// Extracts role title, required skills, keywords, and company name
  /// from a job posting text. Basic+ feature.
  static Future<JobPostingData> extractJobPosting(String jobPostingText) async {
    const systemPrompt = '''
You are an expert job posting analyzer. Extract structured data from the job posting provided.

Return ONLY valid JSON with no explanation, no markdown, no code fences.

JSON structure:
{
  "roleTitle": "",
  "companyName": "",
  "requiredSkills": [],
  "preferredSkills": [],
  "keywords": [],
  "responsibilities": [],
  "qualifications": []
}

Guidelines:
- roleTitle: the exact job title as written in the posting
- companyName: the hiring company name (empty string if not found)
- requiredSkills: skills explicitly listed as required or must-have
- preferredSkills: skills listed as preferred, nice-to-have, or a plus
- keywords: ATS-critical terms — specific software, certifications, methodologies, industry terms
- responsibilities: key job duties (up to 8, concise phrases)
- qualifications: education/experience requirements (up to 6)

${ResumeSanitizer.noBlockedCharsPromptRule}
''';

    final sanitized = CloudflareWorkerService.sanitize(jobPostingText);
    final response = await CloudflareWorkerService.sendPrompt(
      systemPrompt: systemPrompt,
      userMessage:
          'Extract structured data from this job posting:\n\n${CloudflareWorkerService.wrap(sanitized)}',
      maxTokens: 1500,
    );

    try {
      final data =
          ResumeSanitizer.sanitizeAiJson(jsonDecode(response)) as Map<String, dynamic>;
      return JobPostingData.fromJson(data);
    } catch (_) {
      return const JobPostingData(
        roleTitle: '',
        companyName: '',
        requiredSkills: [],
        preferredSkills: [],
        keywords: [],
        responsibilities: [],
        qualifications: [],
      );
    }
  }

  // ── Tailored Resume Generation ─────────────────────────────────────────────

  /// Two-call architecture:
  ///   Pre-processing (Dart): classify and filter experience entries.
  ///   Call 1 (Haiku): score filtered entries for relevance.
  ///   Call 2 (Sonnet): generate resume from top 3 pre-selected entries.
  /// Rule §3: User reviews the draft before it is saved.
  static Future<String> generateTailoredResume({
    required ResumeRenderData masterData,
    required JobPostingData jobPosting,
    void Function(String message)? onProgress,
  }) async {
    // ── PRE-PROCESSING ────────────────────────────────────────────────────────
    final original = masterData.experience;

    // Companies matching these patterns are training institutions, not
    // employers. This is now a defensive fallback, not the primary
    // mechanism — training-vs-employment classification already happens
    // during extraction (see ResumeSanitizer / CloudflareWorkerService),
    // so a master resume should rarely contain a training entry by the time
    // it reaches tailored-resume generation. This list exists for entries a
    // user typed in manually, or that predate that classification.
    const trainingPatterns = [
      'academy', 'school', 'training center', 'training command', 'course',
      'university', 'college', 'institute',
    ];

    final droppedAsTraining = <ExperienceEntry>[];
    final droppedAsEmpty = <ExperienceEntry>[];
    final droppedAsDupe = <ExperienceEntry>[];

    // Step 1: Remove training entries by company name.
    final nonTraining = <ExperienceEntry>[];
    for (final e in original) {
      final companyLower = e.company.toLowerCase();
      if (trainingPatterns.any((p) => companyLower.contains(p))) {
        droppedAsTraining.add(e);
      } else {
        nonTraining.add(e);
      }
    }

    // Step 2: Remove entries with no bullets.
    final withBullets = <ExperienceEntry>[];
    for (final e in nonTraining) {
      if (e.bullets.isEmpty) {
        droppedAsEmpty.add(e);
      } else {
        withBullets.add(e);
      }
    }

    // Step 3: Deduplicate — same title + company; keep the one with more bullets.
    final dupeMap = <String, ExperienceEntry>{};
    for (final e in withBullets) {
      final key =
          '${e.title.toLowerCase().trim()}|${e.company.toLowerCase().trim()}';
      if (dupeMap.containsKey(key)) {
        final existing = dupeMap[key]!;
        if (e.bullets.length > existing.bullets.length) {
          droppedAsDupe.add(existing);
          dupeMap[key] = e;
        } else {
          droppedAsDupe.add(e);
        }
      } else {
        dupeMap[key] = e;
      }
    }
    final filtered = dupeMap.values.toList();

    debugPrint('[PRE-PROCESS] ${original.length} entries in → '
        '${filtered.length} entries after filtering');
    debugPrint('[PRE-PROCESS] Dropped as training: '
        '${droppedAsTraining.map((e) => e.title).toList()}');
    debugPrint('[PRE-PROCESS] Dropped as empty: '
        '${droppedAsEmpty.map((e) => e.title).toList()}');
    debugPrint('[PRE-PROCESS] Dropped as duplicate: '
        '${droppedAsDupe.map((e) => e.title).toList()}');

    // ── CALL 1: RELEVANCE SCORING (Haiku) ─────────────────────────────────────
    onProgress?.call('Analyzing job requirements...');

    List<ExperienceEntry> top3;
    if (filtered.isEmpty) {
      top3 = [];
    } else {
      try {
        top3 = await _scoreAndSelectEntries(jobPosting, filtered);
      } catch (e) {
        debugPrint('[CALL 1] Failed ($e) — '
            'using all ${filtered.length} filtered entries as fallback');
        top3 = filtered.take(3).toList();
      }
    }

    // ── BUILD TRIMMED PAYLOAD ─────────────────────────────────────────────────
    onProgress?.call('Building your tailored resume...');

    // Build formatted job posting text for prompts and skill matching.
    final jobPostingText = [
      'Role: ${jobPosting.roleTitle}',
      if (jobPosting.companyName.isNotEmpty) 'Company: ${jobPosting.companyName}',
      if (jobPosting.requiredSkills.isNotEmpty)
        'Required Skills: ${jobPosting.requiredSkills.join(', ')}',
      if (jobPosting.preferredSkills.isNotEmpty)
        'Preferred Skills: ${jobPosting.preferredSkills.join(', ')}',
      if (jobPosting.keywords.isNotEmpty)
        'Keywords: ${jobPosting.keywords.join(', ')}',
      if (jobPosting.responsibilities.isNotEmpty)
        'Responsibilities:\n${jobPosting.responsibilities.map((r) => '- $r').join('\n')}',
      if (jobPosting.qualifications.isNotEmpty)
        'Qualifications:\n${jobPosting.qualifications.map((q) => '- $q').join('\n')}',
    ].join('\n');

    // Skills: job-posting-matched first, fill remaining slots up to 10.
    final jobPostingLower = jobPostingText.toLowerCase();
    final allSkills = masterData.skills;
    final matchedSkills = allSkills
        .where((s) => jobPostingLower.contains(s.name.toLowerCase()))
        .toList();
    final unmatchedSkills =
        allSkills.where((s) => !matchedSkills.contains(s)).toList();
    final trimmedSkills =
        [...matchedSkills, ...unmatchedSkills].take(10).toList();

    // Certifications: a lightweight keyword pass trims obvious compliance
    // clutter before the payload is built, purely so the prompt doesn't
    // waste space on it — the real credential-vs-compliance-training
    // judgment happens in Call 2's system prompt below, where Sonnet reads
    // what each certification actually is rather than matching its name
    // against a fixed list. This keeps the fallback list short and generic
    // on purpose so it can't mistake a real credential (e.g. a HAZMAT
    // endorsement, a medical certification) for clutter.
    final trimmedCerts = masterData.certifications
        .where((c) => !ResumeSanitizer.fallbackComplianceCertPatterns
            .any((p) => c.name.toLowerCase().contains(p)))
        .take(8)
        .toList();

    // Experience: cap bullets at 4 in Dart.
    final trimmedExperience = top3
        .map((e) => {...e.toJson(), 'bullets': e.bullets.take(4).toList()})
        .toList();

    final trimmedResumeJson = jsonEncode({
      'contact': masterData.contact.toJson(),
      'summary': masterData.summary,
      'experience': trimmedExperience,
      'education': masterData.education.map((e) => e.toJson()).toList(),
      'skills': trimmedSkills.map((s) => s.toJson()).toList(),
      'certifications': trimmedCerts.map((c) => c.toJson()).toList(),
    });

    final sanitizedJob = CloudflareWorkerService.sanitize(jobPostingText);
    final sanitizedResume = CloudflareWorkerService.sanitize(trimmedResumeJson);

    final userMessage =
        'JOB POSTING:\n${CloudflareWorkerService.wrap(sanitizedJob)}\n\n'
        'RESUME DATA (use only what is provided here):\n'
        '${CloudflareWorkerService.wrap(sanitizedResume)}\n\n'
        'Return the tailored resume as JSON matching the input schema exactly.';

    debugPrint('[CALL 2] Prompt size: ${userMessage.length} chars');
    debugPrint('[CALL 2] Experience entries: ${top3.length}');
    debugPrint('[CALL 2] Skills: ${trimmedSkills.length}');
    debugPrint('[CALL 2] Certs: ${trimmedCerts.length}');

    // ── CALL 2: RESUME GENERATION (Sonnet) ────────────────────────────────────
    const systemPrompt = '''
You are an expert resume writer creating a targeted one-page resume.

Rules — follow every one of these exactly:

1. Use ONLY the experience entries provided. Do not add, invent, or reference any other experience.
2. Rewrite the professional summary in 3 sentences max: who this person is, their most relevant qualification for THIS role, and one quantifiable achievement. Integrate keywords from the job posting naturally.
3. Rewrite experience bullets to mirror the language and keywords of the job posting. Each bullet must be relevant to the target role. If a bullet is not relevant, omit it — do not pad to reach 4 bullets.
4. Output a maximum of 4 bullets per experience entry. If fewer are relevant, output fewer.
5. Output only the skills provided. Do not add skills not in the list.
6. For every certification you output, add a "certType" field set to one of "credential" (a genuine license, industry certification, or named professional qualification with real resume value), "compliance_training" (generic, low-signal compliance or administrative training — e.g. annual harassment-prevention training, generic safety briefings, onboarding compliance modules — regardless of what field it comes from), "award_recognition" (recognizes performance, service, or merit rather than certifying a skill or completing a program — e.g. an employee-of-the-month award, a sales/performance award, a medal or badge — regardless of what field it comes from), or "uncertain" (you cannot confidently tell which). This tag is what actually determines whether the certification appears on the final resume, so tag every certification honestly rather than simply omitting the ones you'd exclude — do not add a certification that was not provided.
7. Translate dense, role-specific jargon, abbreviations, and internal tool/system names into language a hiring manager outside that field would understand — this applies to medical, legal, technical, military, or any other specialized field — UNLESS that exact term appears in the job posting, in which case keep it verbatim.
8. Be ruthlessly concise. Every word must earn its place. This resume must fit on one page when formatted. If content does not serve the application for this specific role, omit it.
9. Do not include a skills category label if only 1–2 skills fall under it. Merge into a flat list instead.
10. Output the result as JSON matching the resume data schema provided, with one addition: every object in the "certifications" array must include the "certType" field described in rule 6.

${ResumeSanitizer.noBlockedCharsPromptRule}
''';

    final tStart = DateTime.now();
    try {
      final rawResult = await CloudflareWorkerService.sendPrompt(
        systemPrompt: systemPrompt,
        userMessage: userMessage,
        maxTokens: 2500,
      );
      final ms = DateTime.now().difference(tStart).inMilliseconds;
      debugPrint('[CALL 2] Generation complete in ${ms}ms');
      debugPrint('[CALL 2] Output size: ${rawResult.length} chars');

      // Filter certifications by the model's own certType tag (structured
      // signal, not a prose-only instruction) — compliance_training is
      // dropped, credential and uncertain are both kept since this flow
      // must stay fast and never stop to ask the user. Falls back to the
      // generic keyword list only if certType is missing/malformed.
      final result = _filterCertTypeInResponse(rawResult);
      return result;
    } on TimeoutException catch (e) {
      final ms = e.duration?.inMilliseconds ??
          DateTime.now().difference(tStart).inMilliseconds;
      debugPrint('[CALL 2] TIMEOUT after ${ms}ms');
      throw const CloudflareApiException(
        'Resume generation is taking longer than expected. '
        'Please check your connection and try again.',
      );
    } on CloudflareApiException {
      rethrow;
    } catch (e) {
      debugPrint('[CALL 2] UNKNOWN ERROR: ${e.runtimeType} — $e');
      throw const CloudflareApiException(
        'Something went wrong building your resume. Please try again.',
      );
    }
  }

  /// Parses Call 2's raw JSON response, sanitizes every generated string
  /// (Claude's own rewriting can introduce a blocked character the user
  /// never typed), and applies
  /// [ResumeSanitizer.filterGeneratedCertifications] to its certifications
  /// array using the model's own certType tag. If the response can't be
  /// parsed as JSON, logs and returns it unmodified rather than failing the
  /// whole generation over a filtering step.
  static String _filterCertTypeInResponse(String rawResult) {
    try {
      var cleaned = rawResult.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned
            .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
            .replaceFirst(RegExp(r'\s*```$'), '')
            .trim();
      }
      final decoded = ResumeSanitizer.sanitizeAiJson(jsonDecode(cleaned))
          as Map<String, dynamic>;
      final filtered = ResumeSanitizer.filterGeneratedCertifications(decoded);
      return jsonEncode(filtered);
    } catch (e) {
      debugPrint('[CALL 2] Could not parse response to filter certType '
          '($e) — returning raw result unfiltered');
      return rawResult;
    }
  }

  /// Scores filtered experience entries using Haiku and returns the top 3.
  /// Threshold: ≥5 (strict). Falls back to ≥3 if fewer than 2 qualify.
  /// Throws on API or parse failure — caller falls back to unscored entries.
  static Future<List<ExperienceEntry>> _scoreAndSelectEntries(
    JobPostingData jobPosting,
    List<ExperienceEntry> entries,
  ) async {
    if (entries.isEmpty) return [];

    final jobText = [
      'Role: ${jobPosting.roleTitle}',
      if (jobPosting.companyName.isNotEmpty) 'Company: ${jobPosting.companyName}',
      if (jobPosting.requiredSkills.isNotEmpty)
        'Required Skills: ${jobPosting.requiredSkills.join(', ')}',
      if (jobPosting.preferredSkills.isNotEmpty)
        'Preferred Skills: ${jobPosting.preferredSkills.join(', ')}',
      if (jobPosting.keywords.isNotEmpty)
        'Keywords: ${jobPosting.keywords.join(', ')}',
      if (jobPosting.responsibilities.isNotEmpty)
        'Responsibilities:\n${jobPosting.responsibilities.map((r) => '- $r').join('\n')}',
      if (jobPosting.qualifications.isNotEmpty)
        'Qualifications:\n${jobPosting.qualifications.map((q) => '- $q').join('\n')}',
    ].join('\n');

    // 2-bullet summary per entry keeps the scoring prompt small and cheap.
    final entriesText = entries
        .map((e) =>
            'ID: ${e.id}\n'
            'Title: ${e.title}\n'
            'Company: ${e.company}\n'
            'Summary: ${e.bullets.take(2).join('. ')}')
        .join('\n\n');

    const scoreSystemPrompt =
        'You are a resume expert. Score each experience entry for relevance to '
        'the provided job posting.\n'
        'Return ONLY valid JSON with no other text, no markdown, no code blocks.\n'
        'Schema: {"scores": [{"id": "string", "score": 0, "reason": "string"}]}\n'
        'Score 0–10:\n'
        '10 = directly matches the job title and core responsibilities\n'
        '7–9 = strong keyword and skill overlap with the job posting\n'
        '4–6 = transferable skills that support the role\n'
        '1–3 = minimal connection to this specific role\n'
        '0 = no relevance whatsoever\n'
        'Be strict. A score of 5 or above means this entry belongs on a targeted '
        'resume for this role. Most entries in a diverse background should score '
        'below 5 against any specific posting.';

    final scoreResponse = await CloudflareWorkerService.sendPrompt(
      systemPrompt: scoreSystemPrompt,
      userMessage:
          'JOB POSTING:\n$jobText\n\nEXPERIENCE ENTRIES TO SCORE:\n$entriesText',
      maxTokens: 800,
      model: 'claude-haiku-4-5-20251001',
      timeout: const Duration(seconds: 30),
    );

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(scoreResponse) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[CALL 1] JSON parse failed: $e');
      debugPrint('[CALL 1] Raw response: $scoreResponse');
      rethrow;
    }

    final scoresList = (parsed['scores'] as List).cast<Map<String, dynamic>>();
    final scoreMap = {
      for (final s in scoresList)
        s['id'] as String: (s['score'] as num).toInt()
    };

    debugPrint('[CALL 1] Scored ${scoreMap.length} entries');
    debugPrint('[CALL 1] Scores: '
        '${scoreMap.entries.map((e) => "${e.key}: ${e.value}").toList()}');

    final scored = entries
        .where((e) => scoreMap.containsKey(e.id))
        .toList()
      ..sort((a, b) => (scoreMap[b.id] ?? 0).compareTo(scoreMap[a.id] ?? 0));

    // Primary threshold ≥5. If fewer than 2 qualify, fall back to ≥3.
    final above5 = scored.where((e) => (scoreMap[e.id] ?? 0) >= 5).toList();
    final List<ExperienceEntry> result;
    if (above5.length >= 2) {
      result = above5.take(3).toList();
    } else {
      final above3 = scored.where((e) => (scoreMap[e.id] ?? 0) >= 3).toList();
      result = (above3.isEmpty ? scored : above3).take(3).toList();
    }

    debugPrint('[CALL 1] Selected ${result.length} entries after threshold + cap:');
    for (final e in result) {
      debugPrint('[CALL 1]   → ${e.title} at ${e.company} '
          '(score: ${scoreMap[e.id] ?? 0}, bullets: ${e.bullets.length})');
    }

    return result;
  }

  // ── ATS Keyword Scanner ────────────────────────────────────────────────────

  /// Compares resume content against a job description.
  /// Returns matched keywords, missing keywords, and a keyword density score.
  static Future<AtsAnalysis> analyzeKeywords({
    required ResumeRenderData resumeData,
    required String jobDescription,
  }) async {
    // Build flat resume text for comparison
    final resumeText = [
      resumeData.summary,
      ...resumeData.experience
          .expand((e) => [e.title, e.company, ...e.bullets]),
      ...resumeData.skills.map((s) => s.name),
      ...resumeData.certifications.map((c) => c.name),
    ].join(' ');

    const systemPrompt = '''
You are an ATS (Applicant Tracking System) expert. Analyze how well the resume matches the job description.

Return ONLY valid JSON with no explanation, no markdown, no code fences.

JSON structure:
{
  "score": 0,
  "matchedKeywords": [],
  "missingKeywords": [],
  "partialMatches": [],
  "suggestions": []
}

Where:
- score: integer 0-100 representing keyword match percentage
- matchedKeywords: exact keywords/phrases from JD found in resume
- missingKeywords: important keywords from JD NOT found in resume  
- partialMatches: keywords that appear in similar but not exact form
- suggestions: up to 5 specific, actionable suggestions to improve the score

Focus on: specific skills, software names, certifications, methodologies, job titles, industry terms.
Ignore common words (the, and, etc.), generic phrases, and stop words.
Weight required skills more heavily than preferred skills.

${ResumeSanitizer.noBlockedCharsPromptRule}
''';

    final sanitizedResume = CloudflareWorkerService.sanitize(resumeText);
    final sanitizedJD = CloudflareWorkerService.sanitize(jobDescription);

    final response = await CloudflareWorkerService.sendPrompt(
      systemPrompt: systemPrompt,
      userMessage:
          'Resume content:\n${CloudflareWorkerService.wrap(sanitizedResume)}\n\n'
          'Job description:\n${CloudflareWorkerService.wrap(sanitizedJD)}\n\n'
          'Analyze keyword match:',
      maxTokens: 1500,
    );

    try {
      final data = ResumeSanitizer.sanitizeAiJson(jsonDecode(response))
          as Map<String, dynamic>;
      return AtsAnalysis.fromJson(data);
    } catch (_) {
      return const AtsAnalysis(
        score: 0,
        matchedKeywords: [],
        missingKeywords: [],
        partialMatches: [],
        suggestions: ['Unable to analyze — please try again.'],
      );
    }
  }

  // ── Interview Prep Basic ───────────────────────────────────────────────────

  /// Generates 5-8 role-specific interview questions from the job posting.
  /// No web search. No resume personalization. Basic tier.
  static Future<List<InterviewQA>> generateBasicInterviewPrep(
      String jobPostingText) async {
    const systemPrompt = '''
You are an expert interview coach. Based on the job posting provided, generate 5-8 role-specific interview questions that a candidate is likely to face in an interview for this position.

Return ONLY valid JSON array with no explanation, no markdown, no code fences.

JSON structure (array of objects):
[
  {
    "question": "...",
    "tips": "..."
  }
]

Guidelines:
- Questions should be specific to the role requirements, NOT generic behavioral questions
- Tips should be 2-3 sentences explaining what the interviewer is looking for and how to structure a strong answer
- Focus on technical skills, role-specific scenarios, and industry knowledge required by this job
- Do NOT include universal behavioral questions (tell me about yourself, strengths/weaknesses etc.) — those are already in the app

${ResumeSanitizer.noBlockedCharsPromptRule}
''';

    final sanitized = CloudflareWorkerService.sanitize(jobPostingText);
    final response = await CloudflareWorkerService.sendPrompt(
      systemPrompt: systemPrompt,
      userMessage:
          'Generate role-specific interview questions for this job posting:\n\n'
          '${CloudflareWorkerService.wrap(sanitized)}',
      maxTokens: 2000,
    );

    try {
      final list = ResumeSanitizer.sanitizeAiJson(jsonDecode(response)) as List<dynamic>;
      return list
          .map((item) => InterviewQA.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Cover Letter Generation ────────────────────────────────────────────────

  /// Generates a full cover letter from resume data + job posting.
  /// Pro tier (unlimited) or any tier via $0.99 add-on.
  static Future<String> generateCoverLetter({
    required ResumeRenderData resumeData,
    required String jobDescription,
    required String companyName,
    String? hiringManagerName,
  }) async {
    final resumeSummary = jsonEncode({
      'name': resumeData.contact.fullName,
      'title': resumeData.contact.professionalTitle,
      'summary': resumeData.summary,
      'topExperience': resumeData.experience
          .take(2)
          .map((e) => {
                'title': e.title,
                'company': e.company,
                'highlights': e.bullets.take(3).toList(),
              })
          .toList(),
      'topSkills': resumeData.skills.take(8).map((s) => s.name).toList(),
    });

    final salutation = hiringManagerName != null && hiringManagerName.isNotEmpty
        ? 'Dear $hiringManagerName,'
        : 'Dear Hiring Manager,';

    const systemPrompt = '''
You are an expert cover letter writer. Write a compelling, professional cover letter.

Structure (follow exactly):
1. Opening paragraph: hook + why this specific company/role excites the candidate
2. Middle paragraph 1: 1-2 most relevant accomplishments with specific metrics
3. Middle paragraph 2: how the candidate's skills directly match the role requirements
4. Closing paragraph: call to action, express enthusiasm, professional sign-off

Rules:
- Under 400 words total
- Professional but not stiff — warm and direct
- Use specific details from the resume — no generic filler
- Integrate keywords from the job description naturally
- Never start a paragraph with "I"
- Return ONLY the cover letter text, starting with the salutation provided

${ResumeSanitizer.noBlockedCharsPromptRule}
''';

    final sanitizedResume = CloudflareWorkerService.sanitize(resumeSummary);
    final sanitizedJD = CloudflareWorkerService.sanitize(jobDescription);
    final sanitizedCompany = CloudflareWorkerService.sanitize(companyName);

    final clStart = DateTime.now();
    debugPrint('[COVER_LETTER] Starting generation');
    try {
      final clResult = await CloudflareWorkerService.sendPrompt(
        systemPrompt: systemPrompt,
        userMessage:
            'Candidate information:\n${CloudflareWorkerService.wrap(sanitizedResume)}\n\n'
            'Company: ${CloudflareWorkerService.wrap(sanitizedCompany)}\n\n'
            'Job description:\n${CloudflareWorkerService.wrap(sanitizedJD)}\n\n'
            'Salutation to use: $salutation\n\n'
            'Write the cover letter:',
        maxTokens: 1000,
      );
      debugPrint('[COVER_LETTER] SUCCESS — '
          '${DateTime.now().difference(clStart).inMilliseconds} ms, '
          '${clResult.length} chars');
      return ResumeSanitizer.sanitizeAiText(clResult);
    } on TimeoutException catch (e) {
      debugPrint('[COVER_LETTER] FLUTTER TIMEOUT after '
          '${e.duration?.inMilliseconds ?? DateTime.now().difference(clStart).inMilliseconds} ms');
      rethrow;
    } on CloudflareApiException catch (e) {
      debugPrint('[COVER_LETTER] API ERROR: ${e.message} after '
          '${DateTime.now().difference(clStart).inMilliseconds} ms');
      rethrow;
    } catch (e) {
      debugPrint('[COVER_LETTER] UNKNOWN ERROR: ${e.runtimeType} — $e '
          'after ${DateTime.now().difference(clStart).inMilliseconds} ms');
      rethrow;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models (ephemeral — not persisted to Hive directly)
// ─────────────────────────────────────────────────────────────────────────────

class JobPostingData {
  const JobPostingData({
    required this.roleTitle,
    required this.companyName,
    required this.requiredSkills,
    required this.preferredSkills,
    required this.keywords,
    required this.responsibilities,
    required this.qualifications,
  });

  final String roleTitle;
  final String companyName;
  final List<String> requiredSkills;
  final List<String> preferredSkills;
  final List<String> keywords;
  final List<String> responsibilities;
  final List<String> qualifications;

  factory JobPostingData.fromJson(Map<String, dynamic> json) => JobPostingData(
        roleTitle: json['roleTitle'] as String? ?? '',
        companyName: json['companyName'] as String? ?? '',
        requiredSkills: _toStringList(json['requiredSkills']),
        preferredSkills: _toStringList(json['preferredSkills']),
        keywords: _toStringList(json['keywords']),
        responsibilities: _toStringList(json['responsibilities']),
        qualifications: _toStringList(json['qualifications']),
      );

  static List<String> _toStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  bool get isEmpty => roleTitle.isEmpty && companyName.isEmpty;
}

class AtsAnalysis {
  const AtsAnalysis({
    required this.score,
    required this.matchedKeywords,
    required this.missingKeywords,
    required this.partialMatches,
    required this.suggestions,
  });

  final int score;
  final List<String> matchedKeywords;
  final List<String> missingKeywords;
  final List<String> partialMatches;
  final List<String> suggestions;

  factory AtsAnalysis.fromJson(Map<String, dynamic> json) => AtsAnalysis(
        score: (json['score'] as num?)?.toInt() ?? 0,
        matchedKeywords: JobPostingData._toStringList(json['matchedKeywords']),
        missingKeywords: JobPostingData._toStringList(json['missingKeywords']),
        partialMatches: JobPostingData._toStringList(json['partialMatches']),
        suggestions: JobPostingData._toStringList(json['suggestions']),
      );
}

class InterviewQA {
  const InterviewQA({required this.question, required this.tips});

  final String question;
  final String tips;

  factory InterviewQA.fromJson(Map<String, dynamic> json) => InterviewQA(
        question: json['question'] as String? ?? '',
        tips: json['tips'] as String? ?? '',
      );
}
