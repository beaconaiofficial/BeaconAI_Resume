import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/phase2_api_service.dart';
import 'package:beaconai_resume/widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIX A/B/C — production logging showed Call 1 (relevance scoring) has
// never once succeeded: it hits the identical fence-wrapped JSON bug the P0
// fix already solved for Call 2, and silently falls back to "include
// everything" — even though the scores it computed before failing were
// correct (Motor Transport 0/10, network entries 9-10/10). This is the
// likely true root cause of the "tailored resume includes irrelevant
// entries" complaint, not a scoring-quality problem.
//
//   FIX A: Call 1's prompt now demands JSON-only output, its parsing now
//          goes through the same hardened stripMarkdownFences as Call 2,
//          and a genuine parse failure (after one retry) now throws
//          instead of silently using unfiltered/arbitrary entries.
//   FIX B: a Call 2-only retry no longer re-invokes Call 1 — the caller
//          caches Call 1's result and passes it back in.
//   FIX C: Call 2's max_tokens raised (2500 → 4096) after a real run
//          truncated at 7348 chars; stop_reason == 'max_tokens' now throws
//          a distinguishable CloudflareTruncatedResponseException instead
//          of surfacing as a generic, indistinguishable parse failure.
// ─────────────────────────────────────────────────────────────────────────────

ResumeRenderData _threeEntryMasterFixture() => ResumeRenderData(
      contact: ContactInfo(firstName: 'Test', lastName: 'Veteran'),
      summary: 'A generalist background spanning logistics and IT.',
      experience: [
        ExperienceEntry(
          id: 'net',
          title: 'Network Systems Engineer',
          company: 'US Army',
          bullets: ['Configured and maintained tactical network switches'],
        ),
        ExperienceEntry(
          id: 'helpdesk',
          title: 'Help Desk Technician',
          company: 'US Army',
          bullets: ['Resolved end-user hardware and software tickets'],
        ),
        ExperienceEntry(
          id: 'motor',
          title: 'Motor Transport Operator',
          company: 'US Army',
          bullets: ['Operated and maintained heavy tactical vehicles'],
        ),
      ],
      education: const [],
      skills: const [],
      certifications: const [],
    );

const _jobPosting = JobPostingData(
  roleTitle: 'Senior Network Systems Engineer',
  companyName: 'Acme Networks',
  requiredSkills: ['Cisco', 'BGP', 'Network Security'],
  preferredSkills: [],
  keywords: ['networking', 'routing', 'switching'],
  responsibilities: [],
  qualifications: [],
);

http.Response _claudeTextResponse(String text,
    {String stopReason = 'end_turn'}) {
  return http.Response(
    jsonEncode({
      'content': [
        {'type': 'text', 'text': text}
      ],
      'stop_reason': stopReason,
      'usage': {
        'input_tokens': 100,
        'output_tokens': 80,
        'cache_creation_input_tokens': 0,
        'cache_read_input_tokens': 0,
      },
    }),
    200,
  );
}

const _fenceWrappedScores = 'Here are the relevance scores:\n\n```json\n'
    '{"scores": [\n'
    '  {"id": "net", "score": 9, "reason": "Directly matches the target role"},\n'
    '  {"id": "helpdesk", "score": 6, "reason": "Transferable IT support skills"},\n'
    '  {"id": "motor", "score": 0, "reason": "No relevance to networking"}\n'
    ']}\n```\n\nLet me know if you need anything else.';

const _validDraftJson =
    '{"contact":{"firstName":"Test","lastName":"Veteran"},'
    '"summary":"Tailored summary.","experience":[],"education":[],'
    '"skills":[],"certifications":[]}';

void main() {
  tearDown(() {
    CloudflareWorkerService.client = http.Client();
  });

  group('FIX A — Call 1 fence-wrapped JSON parsing', () {
    test('a fence-wrapped Call 1 response now parses successfully and its '
        'scores are actually applied — the 0-scored entry never reaches '
        "Call 2's payload", () async {
      String? call2RequestBody;
      CloudflareWorkerService.client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final model = body['model'] as String;
        if (model.contains('haiku')) {
          return _claudeTextResponse(_fenceWrappedScores);
        }
        call2RequestBody = request.body;
        return _claudeTextResponse(_validDraftJson);
      });

      await Phase2ApiService.generateTailoredResume(
        masterData: _threeEntryMasterFixture(),
        jobPosting: _jobPosting,
      );

      expect(call2RequestBody, isNotNull,
          reason: 'Call 1 must have succeeded and let the pipeline reach '
              'Call 2 at all');
      expect(call2RequestBody, contains('Network Systems Engineer'));
      expect(call2RequestBody, contains('Help Desk Technician'));
      expect(call2RequestBody, isNot(contains('Motor Transport Operator')),
          reason: 'a genuinely 0-scored entry must be fully excluded from '
              "what's sent to Call 2, not merely deprioritized — this is "
              'the actual relevance filtering the whole two-call '
              'architecture exists to do');
    });

    test('a genuinely unparseable Call 1 response (even after retry) '
        'throws instead of silently using unfiltered/arbitrary entries',
        () async {
      var haikuCallCount = 0;
      CloudflareWorkerService.client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if ((body['model'] as String).contains('haiku')) {
          haikuCallCount++;
          return _claudeTextResponse('I could not score these entries.');
        }
        fail('Call 2 must never be reached when Call 1 fails permanently — '
            'that would mean unfiltered/arbitrary entries silently made it '
            'into generation');
      });

      await expectLater(
        () => Phase2ApiService.generateTailoredResume(
          masterData: _threeEntryMasterFixture(),
          jobPosting: _jobPosting,
        ),
        throwsA(isA<CloudflareApiException>()),
      );
      expect(haikuCallCount, 2,
          reason: 'one retry is expected before giving up — see '
              '_scoreAndSelectEntriesWithRetry');
    });
  });

  group('FIX B — a Call 2-only retry does not re-invoke Call 1', () {
    test('Call 1 succeeds once; Call 2 fails, then a retry passing back '
        'the cached scores succeeds — Call 1 is invoked exactly once '
        'across both attempts', () async {
      var haikuCallCount = 0;
      var sonnetCallCount = 0;
      CloudflareWorkerService.client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if ((body['model'] as String).contains('haiku')) {
          haikuCallCount++;
          return _claudeTextResponse(_fenceWrappedScores);
        }
        sonnetCallCount++;
        if (sonnetCallCount == 1) {
          return http.Response('Internal error', 500);
        }
        return _claudeTextResponse(_validDraftJson);
      });

      List<ExperienceEntry>? cachedTop3;
      await expectLater(
        () => Phase2ApiService.generateTailoredResume(
          masterData: _threeEntryMasterFixture(),
          jobPosting: _jobPosting,
          onEntriesSelected: (entries) => cachedTop3 = entries,
        ),
        throwsA(isA<CloudflareApiException>()),
        reason: "Call 2's first attempt fails (mocked 500)",
      );
      expect(cachedTop3, isNotNull,
          reason: 'Call 1 succeeded before Call 2 failed, so its result '
              'must have been captured for a retry to reuse');

      // Simulates the user tapping "Generate Tailored Resume" again after
      // the visible failure — create_tailored_resume_screen.dart passes
      // the cached entries back in on this second attempt.
      final result = await Phase2ApiService.generateTailoredResume(
        masterData: _threeEntryMasterFixture(),
        jobPosting: _jobPosting,
        cachedTop3: cachedTop3,
      );

      expect(result, isNotEmpty);
      expect(haikuCallCount, 1,
          reason: 'Call 1 (relevance scoring) must not be re-invoked on a '
              'retry that only needs to redo Call 2 — re-scoring relevance '
              'from scratch is redundant cost and gives Call 1 another '
              'unnecessary chance to hit the FIX A parsing bug');
      expect(sonnetCallCount, 2,
          reason: 'Call 2 legitimately needs a second attempt after its '
              'first one failed');
    });
  });

  group('FIX C — Call 2 truncation detection', () {
    test('a response with stop_reason "max_tokens" throws a distinguishable '
        'CloudflareTruncatedResponseException, not a generic parse failure',
        () async {
      CloudflareWorkerService.client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if ((body['model'] as String).contains('haiku')) {
          return _claudeTextResponse(_fenceWrappedScores);
        }
        // Truncated mid-string, exactly like the real production log.
        return _claudeTextResponse(
          '{"contact":{"firstName":"Test","lastName":"Vet',
          stopReason: 'max_tokens',
        );
      });

      await expectLater(
        () => Phase2ApiService.generateTailoredResume(
          masterData: _threeEntryMasterFixture(),
          jobPosting: _jobPosting,
        ),
        throwsA(isA<CloudflareTruncatedResponseException>()),
        reason: 'a max_tokens cutoff must be distinguishable from a '
            'generic unparseable-response failure so it can eventually be '
            'handled distinctly (e.g. a clearer user-facing message) '
            'rather than lumped in with every other parse failure',
      );
    });

    test('Call 2 requests a 4096-token ceiling, not the old 2500 that '
        'truncated a real production run at 7348 chars', () async {
      String? call2Body;
      CloudflareWorkerService.client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if ((body['model'] as String).contains('haiku')) {
          return _claudeTextResponse(_fenceWrappedScores);
        }
        call2Body = request.body;
        return _claudeTextResponse(_validDraftJson);
      });

      await Phase2ApiService.generateTailoredResume(
        masterData: _threeEntryMasterFixture(),
        jobPosting: _jobPosting,
      );

      final decoded = jsonDecode(call2Body!) as Map<String, dynamic>;
      expect(decoded['max_tokens'], 4096);
    });
  });
}
