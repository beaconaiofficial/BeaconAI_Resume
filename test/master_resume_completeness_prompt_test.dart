import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/session_extraction_cache.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Stage 9 — Master Resume anti-conciseness prompt block.
//
// A real Master Resume built by hand came out condensed (merged similar-
// but-distinct achievements, dropped a whole employment period as "not
// relevant") despite an existing rule that Master Resumes are exhaustive —
// a single stated rule lost to the much stronger default resume-writing
// instinct toward brevity. This is a prompt-only fix, so it's verified the
// same way FIX 9's cost-logging tests verify prompt behavior: mock the HTTP
// client, capture the outgoing request body, and assert on the actual
// system prompt text sent to Claude — no live API call, no data-model or
// merge-logic involved.
//
// Also covers Stage 8's document-type-taxonomy additions, which touch the
// same shared prompt constants (_kEntryClassificationRules /
// _kMilitaryDocumentParsingRules).
//
// Extension: the prompt fix alone was a no-op in practice — a code-level
// pass, ResumeSanitizer.capBullets (max 6), still ran unconditionally on
// every Master Resume experience entry regardless of what the model was
// told. That's now gated on Resume.isMaster (see
// resume_migration_service_test.dart for the data-level coverage — the
// only call site that genuinely needed gating, since the other two
// (CloudflareWorkerService.parseFieldMappings,
// DocumentUploadScreen._resolvePendingDecision) are unambiguously
// Master-Resume-only and no longer call capBullets at all).
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late String? capturedSystemPrompt;

  setUp(() {
    // Text-path extraction is memoized by SessionExtractionCache keyed on a
    // hash of the raw input text — every test below calls
    // extractResumeFields with the identical literal string, so without
    // resetting the cache only the first test would ever actually reach
    // the mocked HTTP client.
    SessionExtractionCache.resetForTesting();
    capturedSystemPrompt = null;
    CloudflareWorkerService.client = MockClient((request) async {
      final decoded = jsonDecode(request.body) as Map<String, dynamic>;
      capturedSystemPrompt = decoded['system'] as String?;
      return http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': '{}'}
          ],
          'usage': {
            'input_tokens': 10,
            'output_tokens': 10,
            'cache_creation_input_tokens': 0,
            'cache_read_input_tokens': 0,
          },
        }),
        200,
      );
    });
  });

  tearDown(() {
    CloudflareWorkerService.client = http.Client();
  });

  group('Stage 9 — master-resume-completeness block reaches every '
      'extraction call site', () {
    test('extractResumeFields (text path) system prompt keeps every '
        'distinct achievement and never drops a period as "not relevant"',
        () async {
      await CloudflareWorkerService.extractResumeFields('Some resume text.');

      expect(capturedSystemPrompt, isNotNull);
      final prompt = capturedSystemPrompt!;

      expect(prompt, contains('MASTER RESUME COMPLETENESS'));
      expect(prompt, contains('NO PAGE LIMIT'));
      expect(prompt, contains('keep BOTH'));
      expect(
        prompt,
        contains('NEVER omit an entire employment period'),
      );
      expect(prompt, contains('REMINDER: THIS IS A MASTER RESUME'));
    });

    test('extractResumeFieldsFromPdf system prompt carries the same '
        'completeness block (shared constant, not re-typed per call site)',
        () async {
      await CloudflareWorkerService.extractResumeFieldsFromPdf([1, 2, 3]);

      expect(capturedSystemPrompt, contains('MASTER RESUME COMPLETENESS'));
      expect(capturedSystemPrompt, contains('NO PAGE LIMIT'));
    });

    test('extractResumeFieldsFromImage system prompt carries the same '
        'completeness block (shared constant, not re-typed per call site)',
        () async {
      await CloudflareWorkerService.extractResumeFieldsFromImage(
          [1, 2, 3], 'image/png');

      expect(capturedSystemPrompt, contains('MASTER RESUME COMPLETENESS'));
      expect(capturedSystemPrompt, contains('NO PAGE LIMIT'));
    });

    test('the old contradictory bullet-count caps are gone — a prompt '
        'telling the model to keep every achievement can no longer also '
        'tell it to cap at 6 or select down to 4-6', () async {
      await CloudflareWorkerService.extractResumeFields('Some resume text.');

      final prompt = capturedSystemPrompt!;
      expect(prompt, isNot(contains('Maximum 6 bullets')));
      expect(prompt, isNot(contains('select the 4-6')));
    });
  });

  group('Stage 8 — document-type taxonomy reaches the extraction prompt',
      () {
    test('award_recommendation, equipment_qualification, and '
        'training_certificate are recognized documentType values, with '
        'document-specific extraction guidance', () async {
      await CloudflareWorkerService.extractResumeFields('Some resume text.');
      final prompt = capturedSystemPrompt!;

      expect(prompt, contains('"award_recommendation"'));
      expect(prompt, contains('"equipment_qualification"'));
      expect(prompt, contains('"training_certificate"'));
      expect(prompt, contains('DA FORM 638'));
      expect(prompt, contains('DA FORM 348'));
      expect(prompt, contains('STANDALONE TRAINING CERTIFICATE'));
    });

    test('award-recommendation guidance ties its narrative to the same '
        'role as an NCOER/STP entry, not just a standalone certification',
        () async {
      await CloudflareWorkerService.extractResumeFields('Some resume text.');
      final prompt = capturedSystemPrompt!;

      expect(
        prompt,
        contains('NCOER or STP entry for that period would use'),
      );
    });
  });
}
