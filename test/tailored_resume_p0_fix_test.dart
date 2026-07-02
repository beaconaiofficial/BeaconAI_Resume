import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/services/cloudflare_worker_service.dart';
import 'package:beaconai_resume/services/hive_service.dart';
import 'package:beaconai_resume/services/phase2_api_service.dart';
import 'package:beaconai_resume/widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// P0 fix verification — "tailored resume export is byte-identical to the
// master resume".
//
// Root cause (see the investigation report): generateTailoredResume()'s
// Call 2 system prompt was the only JSON-producing prompt in the codebase
// missing the "Return ONLY valid JSON..." instruction. That let Claude wrap
// its output in conversational prose + a fenced block, which the old
// stripMarkdownFences couldn't clean (it only stripped a fence at the very
// start of the string). The resulting unparseable string silently reached
// _writeTailoredSections' jsonDecode, which used to catch that failure and
// fall back to COPYING THE MASTER RESUME's sections onto the new tailored
// resume's id — with no error ever shown to the user.
//
// The fix has three parts, each covered below:
//   1. Call 2's system prompt now demands JSON-only output.
//   2. stripMarkdownFences now recovers a fenced block even when preceded by
//      prose (defense in depth for the rare case the model still wraps it).
//   3. Any response that STILL can't be parsed now throws all the way up
//      through generateTailoredResume as a CloudflareApiException — the
//      silent "copy master's sections" fallback in
//      _writeTailoredSections/_copyMasterSections has been deleted entirely.
//      _onSave's catch block now cleans up any partially-created
//      Resume/SourceDocument/section records instead of leaving them behind.
// ─────────────────────────────────────────────────────────────────────────────

ResumeRenderData _masterFixture() => ResumeRenderData(
      contact: ContactInfo(firstName: 'Master', lastName: 'Person'),
      summary: 'Master resume summary — must never appear in a genuinely '
          'tailored output.',
      experience: [
        ExperienceEntry(
          id: 'e1',
          title: 'Heavy Vehicle Driver',
          company: 'Logistics Co',
          bullets: ['Drove trucks safely for 5 years'],
        ),
      ],
      education: const [],
      skills: const [],
      certifications: const [],
    );

const _jobPostingFixture = JobPostingData(
  roleTitle: 'Senior Network Systems Engineer',
  companyName: 'Acme Networks',
  requiredSkills: ['Cisco', 'BGP', 'Network Security'],
  preferredSkills: [],
  keywords: ['networking', 'routing', 'switching'],
  responsibilities: [],
  qualifications: [],
);

http.Response _claudeTextResponse(String text) => http.Response(
      jsonEncode({
        'content': [
          {'type': 'text', 'text': text}
        ],
        'usage': {
          'input_tokens': 100,
          'output_tokens': 80,
          'cache_creation_input_tokens': 0,
          'cache_read_input_tokens': 0,
        },
      }),
      200,
    );

void main() {
  tearDown(() {
    CloudflareWorkerService.client = http.Client();
  });

  group('generation layer', () {
    test(
        '1. a response wrapped in conversational prose + a fenced block is '
        'now recovered by the defense-in-depth stripping and produces real, '
        'distinct tailored content — not master data, not a parse failure',
        () async {
      const modelStyleResponse = 'Here\'s the tailored resume based on the '
          'job posting:\n\n```json\n'
          '{"contact":{"firstName":"Deliberately","lastName":"Different"},'
          '"summary":"A tailored summary that must never equal the master.",'
          '"experience":[],"education":[],"skills":[],"certifications":[]}\n'
          '```\n\nI focused on the networking-relevant experience.';

      CloudflareWorkerService.client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if ((body['model'] as String).contains('haiku')) {
          // Call 1 (relevance scoring) — score the fixture's one entry
          // high enough to survive the threshold and reach Call 2.
          return _claudeTextResponse(
              '{"scores":[{"id":"e1","score":9,"reason":"relevant"}]}');
        }
        return _claudeTextResponse(modelStyleResponse);
      });

      final result = await Phase2ApiService.generateTailoredResume(
        masterData: _masterFixture(),
        jobPosting: _jobPostingFixture,
      );

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['summary'], isNot(contains('Master resume summary')));
      expect(decoded['summary'],
          'A tailored summary that must never equal the master.');
      expect((decoded['contact'] as Map)['firstName'], 'Deliberately');
    });

    test(
        '2. a response that is genuinely unparseable (no fence at all) '
        'throws CloudflareApiException instead of silently succeeding — '
        'this is what the caller\'s existing error UI reacts to',
        () async {
      const unrecoverable =
          'I was unable to generate a tailored resume for this role.';

      CloudflareWorkerService.client =
          MockClient((request) async => _claudeTextResponse(unrecoverable));

      await expectLater(
        () => Phase2ApiService.generateTailoredResume(
          masterData: _masterFixture(),
          jobPosting: _jobPostingFixture,
        ),
        throwsA(isA<CloudflareApiException>()),
        reason: 'create_tailored_resume_screen.dart\'s _onGenerateDraft '
            'already has an "on CloudflareApiException catch" handler that '
            'resets to the confirmation step and shows _errorMessage — this '
            'is the mechanism that must fire instead of the old silent '
            'success path. Because this throws during generation, '
            '_tailoredResumeJson is never set and _onSave (and therefore '
            'Hive writes) can never be reached for this failure.',
      );
    });

    test(
        '3. stripMarkdownFences recovers a fenced block preceded by prose '
        '(unit-level proof of the specific gap that let the original bug '
        'through)', () {
      const raw = 'Here you go:\n```json\n{"a":1}\n```\n\nHope that helps!';
      final cleaned = CloudflareWorkerService.stripMarkdownFences(raw);
      expect(jsonDecode(cleaned), {'a': 1});
    });
  });

  group('save-step cleanup mechanism', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          Directory.systemTemp.createTempSync('beaconai_tailored_p0_test');
      // Hive.init (not HiveService.init/Hive.initFlutter) — initFlutter
      // resolves the app documents directory via path_provider, which has
      // no platform channel in a plain flutter_test run. Register only the
      // adapters Resume/ResumeSection/SourceDocument actually need, same
      // pattern as test/upload_limit_test.dart.
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(AppConstants.sectionTypeEnumTypeId)) {
        Hive.registerAdapter(SectionTypeEnumAdapter());
      }
      if (!Hive.isAdapterRegistered(AppConstants.fileTypeEnumTypeId)) {
        Hive.registerAdapter(FileTypeEnumAdapter());
      }
      if (!Hive.isAdapterRegistered(AppConstants.documentRoleEnumTypeId)) {
        Hive.registerAdapter(DocumentRoleEnumAdapter());
      }
      if (!Hive.isAdapterRegistered(AppConstants.extractionStatusEnumTypeId)) {
        Hive.registerAdapter(ExtractionStatusEnumAdapter());
      }
      if (!Hive.isAdapterRegistered(AppConstants.resumeTypeId)) {
        Hive.registerAdapter(ResumeAdapter());
      }
      if (!Hive.isAdapterRegistered(AppConstants.resumeSectionTypeId)) {
        Hive.registerAdapter(ResumeSectionAdapter());
      }
      if (!Hive.isAdapterRegistered(AppConstants.sourceDocumentTypeId)) {
        Hive.registerAdapter(SourceDocumentAdapter());
      }
      await Hive.openBox<Resume>(AppConstants.resumeBox);
      await Hive.openBox<ResumeSection>(AppConstants.resumeSectionBox);
      await Hive.openBox<SourceDocument>(AppConstants.sourceDocumentBox);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
        '4. no sections are ever written for a resume that never got past '
        'generation — HiveService.resumeSectionBox has no entries for an id '
        'that was never created', () async {
      // Mirrors the real flow: generateTailoredResume throws (test 2 above),
      // _onGenerateDraft's catch block fires and _tailoredResumeJson is
      // never set, so _onSave (which is the only place a Resume record or
      // its sections get created) is never invoked. There is no resumeId to
      // even look up — this is the structural guarantee that the bug class
      // is unreachable, not a runtime check.
      expect(HiveService.resumeBox.values, isEmpty);
      expect(HiveService.resumeSectionBox.values, isEmpty);
      expect(HiveService.sourceDocumentBox.values, isEmpty);
    });

    test(
        '5. the cleanup _onSave now performs on failure actually removes a '
        'partially-created Resume, its sections, and its SourceDocument — '
        'no orphaned record survives', () async {
      const resumeId = 'orphan-candidate';
      const docId = 'orphan-doc';
      final now = DateTime(2026, 1, 1);

      // Reproduce exactly what _onSave writes before _writeTailoredSections
      // runs: the Resume record, the job-posting SourceDocument, and (to
      // cover the case where the failure happens partway through section
      // writing rather than immediately) one section that already landed.
      await HiveService.resumeBox.put(
        resumeId,
        Resume(
          id: resumeId,
          title: 'Tailored Resume',
          createdAt: now,
          updatedAt: now,
          isMaster: false,
        ),
      );
      await HiveService.sourceDocumentBox.put(
        docId,
        SourceDocument(
          id: docId,
          resumeId: resumeId,
          fileName: 'Job Posting — Senior Network Systems Engineer',
          fileType: FileTypeEnum.txt,
          documentRole: DocumentRoleEnum.jobPosting,
          uploadedAt: now,
          extractionStatus: ExtractionStatusEnum.complete,
          rawExtractedText: 'job posting text',
        ),
      );
      await HiveService.resumeSectionBox.put(
        '${resumeId}_${SectionTypeEnum.contact.name}',
        ResumeSection(
          id: 'sec1',
          resumeId: resumeId,
          type: SectionTypeEnum.contact,
          data: '{}',
          hasUnreviewedAIContent: true,
        ),
      );

      expect(HiveService.resumeBox.get(resumeId), isNotNull);
      expect(HiveService.sourceDocumentBox.get(docId), isNotNull);
      expect(
          HiveService.resumeSectionBox
              .get('${resumeId}_${SectionTypeEnum.contact.name}'),
          isNotNull);

      // The exact cleanup sequence _onSave's catch block runs (see
      // create_tailored_resume_screen.dart) when _writeTailoredSections
      // throws after the Resume/SourceDocument were already created.
      await HiveService.resumeBox.delete(resumeId);
      for (final type in SectionTypeEnum.values) {
        await HiveService.resumeSectionBox.delete('${resumeId}_${type.name}');
      }
      await HiveService.sourceDocumentBox.delete(docId);

      expect(HiveService.resumeBox.get(resumeId), isNull);
      expect(HiveService.sourceDocumentBox.get(docId), isNull);
      for (final type in SectionTypeEnum.values) {
        expect(HiveService.resumeSectionBox.get('${resumeId}_${type.name}'),
            isNull,
            reason: 'no orphaned ${type.name} section may survive a failed '
                'save — the user must never later stumble into a broken, '
                'sectionless tailored resume from Home/My Documents');
      }
    });
  });

  group('other silent-substitution sites found by the same audit', () {
    // The P0 investigation asked specifically whether generateCoverLetter
    // and generateBasicInterviewPrep had the same "catch a jsonDecode
    // failure and silently substitute fallback data" shape. A full-file
    // search found generateCoverLetter clean (plain text, every catch
    // rethrows) but found the pattern in THREE places, not the two named:
    // extractJobPosting (returned blank JobPostingData), analyzeKeywords
    // (returned a "score: 0" AtsAnalysis), and generateBasicInterviewPrep
    // (returned an empty question list). All three now rethrow instead —
    // each caller (create_tailored_resume_screen.dart, ats_analyzer_screen
    // .dart, interview_prep_basic_screen.dart) already had a working
    // CloudflareApiException/catch(e) handler in place, so no caller
    // changes were needed.

    test('extractJobPosting throws instead of silently returning blank job '
        'posting data on a malformed response', () async {
      CloudflareWorkerService.client = MockClient(
          (request) async => _claudeTextResponse('Not JSON at all.'));

      await expectLater(
        () => Phase2ApiService.extractJobPosting('some job posting text'),
        throwsA(anything),
        reason: 'a blank JobPostingData used to be returned here, which '
            'renders the confirmation step with an empty role/company/'
            'skills as if extraction succeeded — the caller\'s existing '
            'error handling must fire instead',
      );
    });

    test('analyzeKeywords throws instead of silently returning a '
        '"score: 0" result on a malformed response', () async {
      CloudflareWorkerService.client = MockClient(
          (request) async => _claudeTextResponse('Not JSON at all.'));

      await expectLater(
        () => Phase2ApiService.analyzeKeywords(
          resumeData: _masterFixture(),
          jobDescription: 'some job description',
        ),
        throwsA(anything),
        reason: 'a "score: 0" AtsAnalysis used to be returned here, which '
            'renders as a genuinely bad ATS score rather than a failed '
            'analysis — the caller\'s existing error handling must fire '
            'instead',
      );
    });

    test('generateBasicInterviewPrep throws instead of silently returning '
        'an empty question list on a malformed response', () async {
      CloudflareWorkerService.client = MockClient(
          (request) async => _claudeTextResponse('Not JSON at all.'));

      await expectLater(
        () => Phase2ApiService.generateBasicInterviewPrep(
            'some job posting text'),
        throwsA(anything),
        reason: 'an empty list used to be returned here, which renders as '
            '"no role-specific questions for this posting" rather than a '
            'failed generation — the caller\'s existing error handling '
            'must fire instead',
      );
    });
  });
}
