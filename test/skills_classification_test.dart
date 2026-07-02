import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:beaconai_resume/services/cloudflare_worker_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PRIORITY 5 — skills classification (exclude course titles) + count
// guidance.
//
// Reproduction case involved a Computer Science-flavored transcript
// ("Object Oriented Design", "Fundamentals of Programming", etc.) — this
// test uses a different field (nursing) to prove the fix is general
// content classification, not a CS-specific keyword list, plus keeps one
// CS-shaped case to mirror the original report closely.
// ─────────────────────────────────────────────────────────────────────────────

String _resumeJsonWithSkills(List<Map<String, dynamic>> skills) {
  return jsonEncode({
    'contact': {'firstName': 'Test', 'lastName': 'User'},
    'summary': 'A summary.',
    'experience': <dynamic>[],
    'education': <dynamic>[],
    'skills': skills,
    'certifications': <dynamic>[],
  });
}

void main() {
  group('Model-classified skillType', () {
    test('course titles are excluded, genuine skills are kept', () {
      final json = _resumeJsonWithSkills([
        {'id': 's1', 'name': 'Python', 'category': 'technical', 'skillType': 'skill'},
        {
          'id': 's2',
          'name': 'Object Oriented Design',
          'category': 'technical',
          'skillType': 'course_title',
        },
        {
          'id': 's3',
          'name': 'Fundamentals of Programming',
          'category': 'technical',
          'skillType': 'course_title',
        },
        {'id': 's4', 'name': 'Database Management', 'category': 'technical', 'skillType': 'skill'},
      ]);

      final result = CloudflareWorkerService.parseFieldMappings(json);
      final skillsRow =
          result.mappings.where((m) => m['field'] == 'skills').toList();
      final skills = skillsRow.first['suggestedValue'] as List;

      expect(skills.map((s) => s['name']), containsAll(['Python', 'Database Management']));
      expect(skills.any((s) => s['name'] == 'Object Oriented Design'), isFalse);
      expect(skills.any((s) => s['name'] == 'Fundamentals of Programming'), isFalse);
    });
  });

  group('Non-military transcript fixture (nursing) — proves generality', () {
    test('literal course titles from a nursing transcript are excluded, '
        'demonstrated clinical skills survive', () {
      final json = _resumeJsonWithSkills([
        {'id': 's1', 'name': 'Patient Care', 'category': 'technical', 'skillType': 'skill'},
        {'id': 's2', 'name': 'IV Insertion', 'category': 'technical', 'skillType': 'skill'},
        {
          'id': 's3',
          'name': 'Introduction to Pharmacology',
          'category': 'technical',
          'skillType': 'course_title',
        },
        {
          'id': 's4',
          'name': 'Fundamentals of Nursing Practice',
          'category': 'technical',
          'skillType': 'course_title',
        },
        {
          'id': 's5',
          'name': 'Anatomy and Physiology II',
          'category': 'technical',
          'skillType': 'course_title',
        },
      ]);

      final result = CloudflareWorkerService.parseFieldMappings(json);
      final skillsRow =
          result.mappings.where((m) => m['field'] == 'skills').toList();
      final skills = skillsRow.first['suggestedValue'] as List;

      expect(skills.length, 2);
      expect(skills.map((s) => s['name']), containsAll(['Patient Care', 'IV Insertion']));
    });
  });

  group('Fallback path (no skillType) — structural, not field-specific', () {
    test('generic academic-phrasing prefixes are excluded regardless of field', () {
      final json = _resumeJsonWithSkills([
        {'id': 's1', 'name': 'Project Management', 'category': 'technical'},
        {'id': 's2', 'name': 'Introduction to Financial Accounting', 'category': 'technical'},
        {'id': 's3', 'name': 'Principles of Marketing', 'category': 'technical'},
        {'id': 's4', 'name': 'Excel', 'category': 'technical'},
      ]);

      final result = CloudflareWorkerService.parseFieldMappings(json);
      final skillsRow =
          result.mappings.where((m) => m['field'] == 'skills').toList();
      final skills = skillsRow.first['suggestedValue'] as List;

      expect(skills.map((s) => s['name']), containsAll(['Project Management', 'Excel']));
      expect(skills.any((s) => s['name'] == 'Introduction to Financial Accounting'), isFalse);
      expect(skills.any((s) => s['name'] == 'Principles of Marketing'), isFalse);
    });

    test('an ambiguous/unclassified skill defaults to KEEP, not exclude', () {
      final json = _resumeJsonWithSkills([
        {'id': 's1', 'name': 'Customer Relationship Management', 'category': 'technical'},
      ]);
      final result = CloudflareWorkerService.parseFieldMappings(json);
      final skillsRow =
          result.mappings.where((m) => m['field'] == 'skills').toList();
      final skills = skillsRow.first['suggestedValue'] as List;
      expect(skills, hasLength(1),
          reason: 'the fix trims clutter — it must not risk dropping a real '
              'skill it is not confident is a course title');
    });
  });
}
