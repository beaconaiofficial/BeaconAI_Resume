import 'dart:convert';

import 'package:flutter/foundation.dart'
    show debugPrint, DebugPrintCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:beaconai_resume/services/cloudflare_worker_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FIX 9 (efficiency audit) — per-call cost/token logging. Verifies the log
// line is produced from fields already present in the API response (no
// extra network call to compute cost), and that every real call site now
// supplies a callLabel (a missing one is a compile error, enforced by the
// required parameter — see the FIX 9 implementation notes).
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late List<String> capturedLogs;
  late DebugPrintCallback originalDebugPrint;
  late int requestCount;

  setUp(() {
    capturedLogs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) capturedLogs.add(message);
    };

    requestCount = 0;
    CloudflareWorkerService.client = MockClient((request) async {
      requestCount++;
      return http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': '{}'}
          ],
          'usage': {
            'input_tokens': 3330,
            'output_tokens': 120,
            'cache_creation_input_tokens': 0,
            'cache_read_input_tokens': 0,
          },
        }),
        200,
      );
    });
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    CloudflareWorkerService.client = http.Client();
  });

  test('one extraction call makes exactly one network request and logs '
      'usage — no extra request to look up pricing', () async {
    await CloudflareWorkerService.extractResumeFields('Some resume text.');

    expect(requestCount, 1,
        reason: 'cost estimation reads fields already in the response; it '
            'must never trigger a second request');

    final costLog =
        capturedLogs.where((l) => l.startsWith('[COST]')).toList();
    expect(costLog.length, 1);
    expect(costLog.first, contains('extractResumeFields'));
    expect(costLog.first, contains('claude-haiku-4-5-20251001'));
    expect(costLog.first, contains('in=3330'));
    expect(costLog.first, contains('out=120'));
    expect(costLog.first, contains('cacheWrite=0'));
    expect(costLog.first, contains('cacheRead=0'));
    // Haiku: $1/MTok in, $5/MTok out → 3330*1e-6 + 120*5e-6 = 0.003930
    expect(costLog.first, contains(r'$0.00393'));
  });

  test('a response with no usage block does not throw and logs nothing',
      () async {
    CloudflareWorkerService.client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': '{}'}
          ],
        }),
        200,
      );
    });

    await CloudflareWorkerService.extractResumeFields('Some resume text.');

    final costLog =
        capturedLogs.where((l) => l.startsWith('[COST]')).toList();
    expect(costLog, isEmpty);
  });
}
