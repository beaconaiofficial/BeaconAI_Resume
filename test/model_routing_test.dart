import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/phase2_api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Efficiency audit FIX 1 / FIX 2 — model routing regressions.
//
// These assert the exact model string reaching the request body, not output
// quality — verifying "does Haiku still extract this PDF well" would require
// a real, billed API call, which the audit and the surrounding cost-reduction
// work this session are explicitly trying to avoid making casually during
// testing. Haiku is already proven on this identical extraction task via
// extractResumeFields/extractResumeFieldsFromImage; this only confirms the
// third (PDF) path now routes to the same model instead of Sonnet, and that
// the job-posting extractor does too.
// ─────────────────────────────────────────────────────────────────────────────

const _haiku = 'claude-haiku-4-5-20251001';

void main() {
  group('FIX 1 — extractResumeFieldsFromPdf routes to Haiku, not Sonnet', () {
    late Map<String, dynamic> capturedBody;

    setUp(() {
      CloudflareWorkerService.client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            '{"content":[{"type":"text","text":"{}"}]}', 200);
      });
    });

    tearDown(() {
      CloudflareWorkerService.client = http.Client();
    });

    test('request body model field is the Haiku extraction model', () async {
      // Minimal valid-enough byte sequence — the mock never forwards this
      // anywhere real, so it just needs to be present and base64-encodable.
      final fakePdfBytes = List<int>.generate(32, (i) => i);

      await CloudflareWorkerService.extractResumeFieldsFromPdf(fakePdfBytes);

      expect(capturedBody['model'], _haiku,
          reason: 'PDF-vision extraction does the identical task as the '
              'text and image extraction paths, both of which already use '
              'Haiku — it must not be left on the more expensive model');
    });
  });

  group('FIX 2 — Phase2ApiService.extractJobPosting routes to Haiku', () {
    late Map<String, dynamic> capturedBody;

    setUp(() {
      CloudflareWorkerService.client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            '{"content":[{"type":"text","text":"{}"}]}', 200);
      });
    });

    tearDown(() {
      CloudflareWorkerService.client = http.Client();
    });

    test('request body model field is the Haiku extraction model', () async {
      try {
        await Phase2ApiService.extractJobPosting('Some job posting text.');
      } catch (_) {
        // The mock's empty-object response won't parse into JobPostingData —
        // irrelevant here, we only need the outbound request body.
      }

      expect(capturedBody['model'], _haiku,
          reason: 'job posting extraction is pure structured-JSON '
              'extraction, not generation, and should not default to the '
              'more expensive generation-tier model');
    });
  });
}
