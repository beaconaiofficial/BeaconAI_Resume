import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/services/resume_sanitizer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Claude's extraction API sometimes returns fields as JSON numbers instead of
// strings (documented precedent: gpa, graduationYear, startDate, endDate).
// This same quirk applies to ANY field that looks numeric to the model —
// phone numbers, credential/license IDs, and (in principle) a stray bullet
// or skill-name element. A naive `as String?` cast on one of these throws,
// and depending on where it happens that's either a silently-emptied
// extraction result or a live crash. Found via a real-document sweep
// following the Stage 1 GPA-crash fix; covers every model-layer gap found.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('ContactInfo.fromJson — phone returned as a JSON number', () {
    test('does not throw and coerces to a string', () {
      final json = {
        'firstName': 'Jane',
        'lastName': 'Doe',
        'phone': 5551234567,
      };

      expect(() => ContactInfo.fromJson(json), returnsNormally);
      final contact = ContactInfo.fromJson(json);
      expect(contact.phone, '5551234567');
    });

    test('a genuine string phone is unaffected', () {
      final contact =
          ContactInfo.fromJson({'phone': '(555) 123-4567'});
      expect(contact.phone, '(555) 123-4567');
    });
  });

  group('SkillEntry.fromJson — name returned as a JSON number', () {
    test('does not throw and coerces to a string', () {
      final json = {'id': 's1', 'name': 12345};
      expect(() => SkillEntry.fromJson(json), returnsNormally);
      expect(SkillEntry.fromJson(json).name, '12345');
    });

    test('a missing name does not throw (no more bare `as String`)', () {
      final json = {'id': 's1'};
      expect(() => SkillEntry.fromJson(json), returnsNormally);
      expect(SkillEntry.fromJson(json).name, '');
    });
  });

  group('ExperienceEntry.fromJson — a bullet element returned as a JSON '
      'number', () {
    test('does not throw and coerces the element to a string', () {
      final json = {
        'id': 'e1',
        'bullets': ['Led a team of 12', 200000, 'Shipped on time'],
      };
      expect(() => ExperienceEntry.fromJson(json), returnsNormally);
      final entry = ExperienceEntry.fromJson(json);
      expect(entry.bullets.map((b) => b.text).toList(),
          ['Led a team of 12', '200000', 'Shipped on time']);
    });
  });

  group('BulletEntry migration — legacy List<String> bullets stored before '
      'the BulletEntry schema existed', () {
    test('a legacy flat-string bullets list loses no text, and is marked '
        '"not yet evaluated" (hasQuantifiableData/metricRequested both '
        'false) rather than "confirmed missing data"', () {
      // Exact shape a pre-Stage-3 ResumeSection.data JSON string has.
      final legacyJson = {
        'id': 'e1',
        'title': 'Network Systems Engineer',
        'company': 'Acme Corp',
        'bullets': [
          'Maintained enterprise network infrastructure',
          'Led a cross-functional team of 6 engineers',
        ],
      };

      final entry = ExperienceEntry.fromJson(legacyJson);

      expect(entry.bullets.length, 2,
          reason: 'no bullet is dropped during the legacy-shape migration');
      expect(entry.bullets[0].text, 'Maintained enterprise network infrastructure');
      expect(entry.bullets[1].text, 'Led a cross-functional team of 6 engineers');
      for (final b in entry.bullets) {
        expect(b.hasQuantifiableData, isFalse,
            reason: 'legacy data is "not yet evaluated," not "confirmed '
                'no metric" — but the trigger condition for the '
                'metric-request prompt is the same either way, by design');
        expect(b.metricRequested, isFalse);
      }
    });

    test('round-tripping a legacy entry through toJson/fromJson upgrades '
        'the stored shape to objects with no data loss', () {
      final legacyJson = {
        'id': 'e1',
        'title': 'Network Systems Engineer',
        'company': 'Acme Corp',
        'bullets': ['Maintained enterprise network infrastructure'],
      };

      final entry = ExperienceEntry.fromJson(legacyJson);
      final reEncoded = entry.toJson();

      // The upgraded shape is objects, not bare strings.
      final bulletsJson = reEncoded['bullets'] as List;
      expect(bulletsJson.first, isA<Map>());
      expect((bulletsJson.first as Map)['text'],
          'Maintained enterprise network infrastructure');

      // Reading it back a second time (simulating the resume being opened
      // again after the upgraded shape was saved) preserves everything.
      final reParsed = ExperienceEntry.fromJson(reEncoded);
      expect(reParsed.bullets.length, 1);
      expect(reParsed.bullets.first.text,
          'Maintained enterprise network infrastructure');
    });

    test('an entry with no bullets field at all (very old data) does not '
        'throw and produces an empty bullet list', () {
      final json = {'id': 'e1', 'title': 'Some Role'};
      expect(() => ExperienceEntry.fromJson(json), returnsNormally);
      expect(ExperienceEntry.fromJson(json).bullets, isEmpty);
    });
  });

  group('CertificationEntry.fromJson — credentialId returned as a JSON '
      'number', () {
    test('does not throw and coerces to a string', () {
      final json = {'id': 'c1', 'name': 'PMP', 'credentialId': 4471029};
      expect(() => CertificationEntry.fromJson(json), returnsNormally);
      expect(CertificationEntry.fromJson(json).credentialId, '4471029');
    });
  });

  group('ResumeSanitizer.coerceToString', () {
    test('passes a String through unchanged', () {
      expect(ResumeSanitizer.coerceToString('3.9772'), '3.9772');
    });

    test('stringifies a num', () {
      expect(ResumeSanitizer.coerceToString(3.9772), '3.9772');
      expect(ResumeSanitizer.coerceToString(2026), '2026');
    });

    test('returns null for null and for other non-num types', () {
      expect(ResumeSanitizer.coerceToString(null), isNull);
      expect(ResumeSanitizer.coerceToString(true), isNull);
    });
  });
}
