import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/constants/app_constants.dart';
import 'package:beaconai_resume/services/resume_sanitizer.dart';
import 'package:beaconai_resume/utils/wizard_validator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PRIORITY 2 — AI-generated content must never trip the app's own
// content-field validation (blocked: < > ; and backtick). The reproduction
// case was a semicolon Claude introduced while rewriting a source
// document's comma ("...NCOs were properly trained; provided invaluable
// counseling..."), but the fix (ResumeSanitizer.sanitizeAiText /
// sanitizeAiJson) is content-agnostic — it strips/replaces the same 4
// characters regardless of what career field or wording produced them, so
// these tests use non-military example text.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('sanitizeAiText — each blocked character', () {
    test('semicolon is replaced with a comma', () {
      final result = ResumeSanitizer.sanitizeAiText(
          'Managed inventory workflows; trained 4 new hires on POS systems.');
      expect(result.contains(';'), isFalse);
      expect(result,
          'Managed inventory workflows, trained 4 new hires on POS systems.');
    });

    test('backtick is replaced with an apostrophe', () {
      final result =
          ResumeSanitizer.sanitizeAiText('Owned the store\'s `Best in Class` award submission.');
      expect(result.contains('`'), isFalse);
    });

    test('angle brackets are removed', () {
      final result = ResumeSanitizer.sanitizeAiText(
          'Improved throughput <significantly> across the fulfillment line.');
      expect(result.contains('<'), isFalse);
      expect(result.contains('>'), isFalse);
    });

    test('all four blocked characters together', () {
      final result =
          ResumeSanitizer.sanitizeAiText('A <b>`bold`</b> claim; unverified.');
      expect(AppConstants.contentBlockedPattern.hasMatch(result), isFalse);
    });

    test('text with none of the blocked characters is untouched', () {
      const clean = 'Led a team of 6 sales associates, exceeding quarterly targets.';
      expect(ResumeSanitizer.sanitizeAiText(clean), clean);
    });
  });

  group('sanitizeAiText output always passes WizardValidator', () {
    test('bullet containing a semicolon (reproduction shape, generalized)',
        () {
      const raw =
          'Coordinated cross-team logistics; ensured on-time delivery for 98% of shipments.';
      final sanitized = ResumeSanitizer.sanitizeAiText(raw);
      expect(WizardValidator.validateBullet(sanitized), isNull);
    });

    test('company name containing a backtick', () {
      const raw = "Riverside `Home Goods` Co.";
      final sanitized = ResumeSanitizer.sanitizeAiText(raw);
      expect(WizardValidator.validateCompany(sanitized), isNull);
    });

    test('summary containing angle brackets', () {
      const raw = 'Results-driven <retail operations> leader with 5 years experience.';
      final sanitized = ResumeSanitizer.sanitizeAiText(raw);
      expect(WizardValidator.validateSummary(sanitized), isNull);
    });

    test('skill tag containing a semicolon', () {
      const raw = 'Inventory Management; Forecasting';
      final sanitized = ResumeSanitizer.sanitizeAiText(raw);
      expect(WizardValidator.validateSkill(sanitized), isNull);
    });

    test('certification name containing a backtick', () {
      const raw = 'ServSafe `Food Handler` Certification';
      final sanitized = ResumeSanitizer.sanitizeAiText(raw);
      expect(WizardValidator.validateCertName(sanitized), isNull);
    });
  });

  group('sanitizeAiJson — recursive, shape-agnostic', () {
    test('sanitizes every string leaf in a nested resume-shaped map', () {
      final raw = {
        'summary': 'Builds < strong > client relationships; delivers results.',
        'experience': [
          {
            'title': 'Assistant Manager',
            'company': 'Bright`Leaf` Coffee Co.',
            'bullets': [
              'Trained baristas on espresso technique; reduced waste by 15%.',
              'No blocked characters here.',
            ],
          },
        ],
        'skills': ['Team Leadership; Coaching', 'POS Systems'],
        'certifications': [
          {'name': 'ServSafe; Manager', 'issuer': 'National Restaurant Assoc.'}
        ],
      };

      final result = ResumeSanitizer.sanitizeAiJson(raw) as Map<String, dynamic>;

      expect(AppConstants.contentBlockedPattern.hasMatch(result['summary'] as String),
          isFalse);
      final exp = (result['experience'] as List).first as Map<String, dynamic>;
      expect(AppConstants.contentBlockedPattern.hasMatch(exp['company'] as String),
          isFalse);
      for (final bullet in exp['bullets'] as List) {
        expect(AppConstants.contentBlockedPattern.hasMatch(bullet as String), isFalse);
      }
      for (final skill in result['skills'] as List) {
        expect(AppConstants.contentBlockedPattern.hasMatch(skill as String), isFalse);
      }
      final cert = (result['certifications'] as List).first as Map<String, dynamic>;
      expect(AppConstants.contentBlockedPattern.hasMatch(cert['name'] as String), isFalse);
    });

    test('non-string values (bool, null, num) pass through unchanged', () {
      final raw = {
        'isAIPrefilled': true,
        'gpa': null,
        'confidence': 0.9,
        'certType': 'credential',
      };
      final result = ResumeSanitizer.sanitizeAiJson(raw) as Map<String, dynamic>;
      expect(result['isAIPrefilled'], true);
      expect(result['gpa'], isNull);
      expect(result['confidence'], 0.9);
      expect(result['certType'], 'credential');
    });
  });
}
