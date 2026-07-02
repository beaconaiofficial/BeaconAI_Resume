import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/session_extraction_cache.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Session-scoped extraction cache — prevents re-billing an extraction call
// for content that already succeeded earlier in the same app session
// (retry after a downstream failure, backing out and re-uploading the same
// file), plus in-flight request dedup for rapid double-taps. Tested through
// the real CloudflareWorkerService.extractResumeFields call site (not just
// the cache service in isolation) since that's what actually needs to
// behave correctly end to end.
// ─────────────────────────────────────────────────────────────────────────────

http.Response _successResponse({int inputTokens = 100, int outputTokens = 50}) {
  return http.Response(
    jsonEncode({
      'content': [
        {'type': 'text', 'text': '{"contact":{}}'}
      ],
      'usage': {
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'cache_creation_input_tokens': 0,
        'cache_read_input_tokens': 0,
      },
    }),
    200,
  );
}

void main() {
  setUp(() {
    // Requirement 5: the cache must be a fresh empty structure on every
    // run — this reproduces that guarantee for each test rather than
    // relying on test execution order.
    SessionExtractionCache.resetForTesting();
  });

  tearDown(() {
    CloudflareWorkerService.client = http.Client();
  });

  test('1. retry after a downstream failure (extraction itself already '
      'succeeded) hits the cache, not the network', () async {
    var requestCount = 0;
    CloudflareWorkerService.client = MockClient((request) async {
      requestCount++;
      return _successResponse();
    });

    final first = await CloudflareWorkerService.extractResumeFields(
        'Same resume text, extracted once.');

    // Simulates the caller finding the extraction result unusable
    // downstream (parsing/sanitization/UI error) and retrying with the
    // identical source content — the extraction call itself already
    // succeeded once, so a retry must not re-bill it.
    final retried = await CloudflareWorkerService.extractResumeFields(
        'Same resume text, extracted once.');

    expect(requestCount, 1,
        reason: 'the second call is a retry of already-successfully-'
            'extracted content — it must be served from the session cache');
    expect(retried, first);
  });

  test('2. a genuinely failed/errored extraction is never cached — retry '
      'hits the network again', () async {
    var requestCount = 0;
    CloudflareWorkerService.client = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) {
        return http.Response('Internal error', 500);
      }
      return _successResponse();
    });

    await expectLater(
      () => CloudflareWorkerService.extractResumeFields(
          'This call will fail the first time.'),
      throwsA(isA<CloudflareApiException>()),
    );
    expect(requestCount, 1);

    // Retry with the identical content — nothing was cached from the
    // failure, so this must be a genuine second network attempt.
    final result = await CloudflareWorkerService.extractResumeFields(
        'This call will fail the first time.');

    expect(requestCount, 2,
        reason: 'a failed call must never populate the cache; retrying '
            'identical content after a failure must reach the network');
    expect(result, isNotEmpty);
  });

  test('3. rapid double-tap before the first call resolves collapses into '
      'one network request via in-flight dedup', () async {
    var requestCount = 0;
    final gate = Completer<void>();
    CloudflareWorkerService.client = MockClient((request) async {
      requestCount++;
      // Holds the response open until the test releases it, so both
      // "taps" are guaranteed to be in flight simultaneously before
      // either resolves — this is what makes the dedup path (rather than
      // the already-cached path) the one under test.
      await gate.future;
      return _successResponse();
    });

    final firstTap = CloudflareWorkerService.extractResumeFields(
        'Double-tapped upload content.');
    final secondTap = CloudflareWorkerService.extractResumeFields(
        'Double-tapped upload content.');

    // Let both calls reach the (still-blocked) mock client before
    // releasing the gate.
    await Future<void>.delayed(Duration.zero);
    gate.complete();

    final results = await Future.wait([firstTap, secondTap]);

    expect(requestCount, 1,
        reason: 'two concurrent requests for identical content must '
            'collapse into a single network call, not fire two');
    expect(results[0], results[1]);
  });

  test('4. different content sent to the same extraction function always '
      'produces real (mocked) API calls — no false-positive cache hits',
      () async {
    var requestCount = 0;
    CloudflareWorkerService.client = MockClient((request) async {
      requestCount++;
      return _successResponse();
    });

    await CloudflareWorkerService.extractResumeFields('Resume A content.');
    await CloudflareWorkerService.extractResumeFields('Resume B content.');

    expect(requestCount, 2,
        reason: 'different source content must never share a cache entry');
  });

  test('5. the cache starts empty for content never seen before in this '
      'test run', () async {
    var requestCount = 0;
    CloudflareWorkerService.client = MockClient((request) async {
      requestCount++;
      return _successResponse();
    });

    await CloudflareWorkerService.extractResumeFields(
        'Content unique to this test, never cached before.');

    expect(requestCount, 1,
        reason: 'brand-new content must not spuriously hit a cache entry '
            'left over from another test or a prior run — there is no '
            'persistence mechanism to have populated one');
  });
}
