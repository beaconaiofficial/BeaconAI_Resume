import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:beaconai_resume/services/cloudflare_worker_service.dart';

// When the AI server was replaced (Nov 2026), every call came back
// 404 {"error":"not_found"} and users saw "API error 404. Please try again."
// or, for uploads, a claim that their file was corrupted. Server-side
// failures and network failures now get plain, accurate messages.
void main() {
  setUp(() => CloudflareWorkerService.isAiBlocked = () => false);
  tearDown(() => CloudflareWorkerService.client = http.Client());

  group('AiErrorMessages.forStatus', () {
    for (final status in [401, 403, 404, 405, 500, 502, 503]) {
      test('$status → service unavailable, no raw status code shown', () {
        final e = AiErrorMessages.forStatus(status);
        expect(e, isA<AiServiceUnavailableException>());
        expect((e as AiServiceUnavailableException).statusCode, status);
        expect(e.message, AiErrorMessages.serviceUnavailable);
        expect(e.message, isNot(contains('$status')));
      });
    }

    test('429 keeps the rate-limit message', () {
      expect(AiErrorMessages.forStatus(429).message,
          AiErrorMessages.tooManyRequests);
    });

    test('400 is a request problem, not an outage', () {
      final e = AiErrorMessages.forStatus(400);
      expect(e, isNot(isA<AiServiceUnavailableException>()));
      expect(e.message, AiErrorMessages.badRequest);
    });
  });

  group('AiErrorMessages.forTransport', () {
    test('timeouts keep the caller-specific message', () {
      final e = AiErrorMessages.forTransport(TimeoutException('x'),
          timeoutMessage: 'Request timed out. Try fewer pages.');
      expect(e.message, 'Request timed out. Try fewer pages.');
      expect(e, isNot(isA<AiServiceUnreachableException>()));
    });

    test('network failures say the service cannot be reached', () {
      final e = AiErrorMessages.forTransport(
          http.ClientException('Failed host lookup'),
          timeoutMessage: 'unused');
      expect(e, isA<AiServiceUnreachableException>());
      expect(e.message, AiErrorMessages.unreachable);
      expect(e.message, isNot(contains('Failed host lookup')));
    });
  });

  group('sendPrompt end to end with a mocked server', () {
    Future<Object?> call() async {
      try {
        await CloudflareWorkerService.sendPrompt(
            callLabel: 'test', systemPrompt: 's', userMessage: 'u');
      } catch (e) {
        return e;
      }
      return null;
    }

    test('the Nov 2026 outage response (404 not_found) → clear outage message',
        () async {
      CloudflareWorkerService.client =
          MockClient((_) async => http.Response('{"error":"not_found"}', 404));
      final e = await call();
      expect(e, isA<AiServiceUnavailableException>());
      expect((e as CloudflareApiException).message,
          AiErrorMessages.serviceUnavailable);
    });

    test('no network → unreachable message', () async {
      CloudflareWorkerService.client = MockClient(
          (_) async => throw http.ClientException('Connection refused'));
      final e = await call();
      expect(e, isA<AiServiceUnreachableException>());
    });

    test('a successful response still returns the text', () async {
      CloudflareWorkerService.client = MockClient((_) async => http.Response(
          '{"content":[{"type":"text","text":"hello"}],"stop_reason":"end_turn"}',
          200));
      expect(
          await CloudflareWorkerService.sendPrompt(
              callLabel: 'test', systemPrompt: 's', userMessage: 'u'),
          'hello');
    });
  });
}
