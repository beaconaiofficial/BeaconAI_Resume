import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/phase2_api_service.dart';
import 'package:beaconai_resume/widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fix: generateTailoredResume's pre-processing used to silently discard
// whichever same-title+company experience entry had fewer bullets (Step 3,
// phase2_api_service.dart) — invisible to the user, same failure category as
// the markdown-fence parsing bug and the _saveSection() data-loss bug this
// project treats as P0. Neither colliding entry may be dropped without the
// caller explicitly choosing — see onDuplicateRoleCollision's doc comment.
// ─────────────────────────────────────────────────────────────────────────────

ResumeRenderData _collidingMasterFixture() => ResumeRenderData(
      contact: ContactInfo(firstName: 'Test', lastName: 'Veteran'),
      summary: 'A generalist background in network operations.',
      experience: [
        ExperienceEntry(
          id: 'dup1',
          title: 'Network Systems Engineer',
          company: 'US Army',
          bullets: ['Configured tactical network switches for a battalion']
              .map((s) => BulletEntry(text: s))
              .toList(),
        ),
        ExperienceEntry(
          id: 'dup2',
          title: 'network systems engineer', // same key, different casing
          company: 'US Army',
          bullets: [
            'Led a 6-person team maintaining battalion network infrastructure',
            'Reduced network outage response time by 30 percent',
            'Migrated legacy switching hardware to a modern platform',
          ].map((s) => BulletEntry(text: s)).toList(),
        ),
      ],
      education: const [],
      skills: const [],
      certifications: const [],
    );

const _jobPosting = JobPostingData(
  roleTitle: 'Senior Network Systems Engineer',
  companyName: 'Acme Networks',
  requiredSkills: ['Cisco', 'Network Security'],
  preferredSkills: [],
  keywords: ['networking', 'switching'],
  responsibilities: [],
  qualifications: [],
);

http.Response _claudeTextResponse(String text) {
  return http.Response(
    jsonEncode({
      'content': [
        {'type': 'text', 'text': text}
      ],
      'stop_reason': 'end_turn',
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

// Both entries score well above the ≥5 threshold, so both survive relevance
// scoring and both should reach Call 2's payload — the only question this
// test is about is whether Step 3's pre-processing already silently
// discarded one of them before scoring ever ran.
const _bothHighScores = '{"scores": [\n'
    '  {"id": "dup1", "score": 8, "reason": "Directly matches the role"},\n'
    '  {"id": "dup2", "score": 9, "reason": "Directly matches the role"}\n'
    ']}';

const _validDraftJson =
    '{"contact":{"firstName":"Test","lastName":"Veteran"},'
    '"summary":"Tailored summary.","experience":[],"education":[],'
    '"skills":[],"certifications":[]}';

void main() {
  tearDown(() {
    CloudflareWorkerService.client = http.Client();
  });

  group('Step 3 duplicate-role collision — never silently drop a colliding '
      'entry', () {
    test('with no onDuplicateRoleCollision hook supplied, both colliding '
        'entries survive pre-processing and both reach Call 2', () async {
      String? call2RequestBody;
      CloudflareWorkerService.client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final model = body['model'] as String;
        if (model.contains('haiku')) {
          return _claudeTextResponse(_bothHighScores);
        }
        call2RequestBody = request.body;
        return _claudeTextResponse(_validDraftJson);
      });

      await Phase2ApiService.generateTailoredResume(
        masterData: _collidingMasterFixture(),
        jobPosting: _jobPosting,
      );

      expect(call2RequestBody, isNotNull);
      expect(call2RequestBody,
          contains('Configured tactical network switches for a battalion'),
          reason: 'the fewer-bullets entry must not be silently dropped '
              'just because the other colliding entry has more bullets');
      expect(
          call2RequestBody,
          contains(
              'Led a 6-person team maintaining battalion network infrastructure'),
          reason: 'the more-bullets entry must also survive');
    });

    test('a caller-supplied onDuplicateRoleCollision hook receives every '
        'colliding entry, most-bullets-first, and its return value is what '
        'actually proceeds — proves the hook is a real decision point, not '
        'decorative', () async {
      List<ExperienceEntry>? seenCollision;
      CloudflareWorkerService.client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final model = body['model'] as String;
        if (model.contains('haiku')) {
          return _claudeTextResponse(_bothHighScores);
        }
        return _claudeTextResponse(_validDraftJson);
      });

      await Phase2ApiService.generateTailoredResume(
        masterData: _collidingMasterFixture(),
        jobPosting: _jobPosting,
        onDuplicateRoleCollision: (colliding) async {
          seenCollision = colliding;
          return [colliding.first]; // caller resolves down to one
        },
      );

      expect(seenCollision, isNotNull);
      expect(seenCollision!.length, 2,
          reason: 'the hook must see every colliding entry, not a '
              'pre-filtered subset');
      expect(seenCollision!.first.id, 'dup2',
          reason: 'the entry with more bullets is presented first as the '
              'pre-selected default');
    });

    test('three entries sharing the same title+company all collide into '
        'one group — generalizes beyond exactly two', () async {
      final threeWay = ResumeRenderData(
        contact: ContactInfo(firstName: 'Test', lastName: 'Veteran'),
        summary: '',
        experience: [
          ExperienceEntry(
            id: 'a',
            title: 'Supply Chain Coordinator',
            company: 'US Army',
            bullets: ['One bullet'].map((s) => BulletEntry(text: s)).toList(),
          ),
          ExperienceEntry(
            id: 'b',
            title: 'Supply Chain Coordinator',
            company: 'US Army',
            bullets: ['One bullet', 'Two bullet']
                .map((s) => BulletEntry(text: s))
                .toList(),
          ),
          ExperienceEntry(
            id: 'c',
            title: 'Supply Chain Coordinator',
            company: 'US Army',
            bullets: ['One bullet', 'Two bullet', 'Three bullet']
                .map((s) => BulletEntry(text: s))
                .toList(),
          ),
        ],
        education: const [],
        skills: const [],
        certifications: const [],
      );

      List<ExperienceEntry>? seenCollision;
      CloudflareWorkerService.client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final model = body['model'] as String;
        if (model.contains('haiku')) {
          return _claudeTextResponse('{"scores": [\n'
              '  {"id": "a", "score": 8, "reason": "match"},\n'
              '  {"id": "b", "score": 8, "reason": "match"},\n'
              '  {"id": "c", "score": 8, "reason": "match"}\n'
              ']}');
        }
        return _claudeTextResponse(_validDraftJson);
      });

      await Phase2ApiService.generateTailoredResume(
        masterData: threeWay,
        jobPosting: _jobPosting,
        onDuplicateRoleCollision: (colliding) async {
          seenCollision = colliding;
          return colliding;
        },
      );

      expect(seenCollision, isNotNull);
      expect(seenCollision!.length, 3);
      expect(seenCollision!.map((e) => e.id).toList(), ['c', 'b', 'a'],
          reason: 'sorted most-bullets-first regardless of group size');
    });
  });
}
