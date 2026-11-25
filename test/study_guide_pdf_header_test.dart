import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/services/study_guide_pdf_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Interview Study Guide PDF: the title + role/company header must repeat on
// every page (MultiPage header:), not only the first. Builds a guide long
// enough for 3+ pages with built-in fonts (no network) and reads each page's
// text back with syncfusion's extractor.
//
// Set WRITE_STUDY_GUIDE_SAMPLE=<path> to also save the generated PDF.
// ─────────────────────────────────────────────────────────────────────────────

InterviewStudyGuide sampleGuide({int questions = 14}) {
  const categories = QuestionCategoryEnum.values;
  return InterviewStudyGuide(
    id: 'guide-1',
    resumeId: 'resume-1',
    companyName: 'Northwind Logistics',
    roleTitle: 'Senior Operations Analyst',
    generatedAt: DateTime(2026, 11, 25),
    questions: [
      for (var i = 0; i < questions; i++)
        InterviewQuestion(
          id: 'q$i',
          category: categories[i % categories.length],
          questionText: 'Question ${i + 1}: Tell me about a time you improved '
              'an operational process under a tight deadline. What did you '
              'change, and how did you measure the result?',
          answerGuide: 'Use the STAR method. Situation: name the team, the '
              'process and why it was slow. Task: what you owned. Action: the '
              'specific changes you made, the data you looked at, and who you '
              'brought along. Result: a number, such as hours saved per week, error '
              'rate before and after, or cost avoided. Close with what you '
              'would do differently and how it applies to this role at '
              'Northwind Logistics, where on-time delivery and warehouse '
              'throughput are the metrics the hiring manager will care about. '
              'Keep it under two minutes and leave room for a follow-up.',
        ),
    ],
  );
}

List<String> pageTexts(Uint8List bytes) {
  final doc = sf.PdfDocument(inputBytes: bytes);
  try {
    final extractor = sf.PdfTextExtractor(doc);
    return [
      for (var i = 0; i < doc.pages.count; i++)
        extractor.extractText(startPageIndex: i, endPageIndex: i),
    ];
  } finally {
    doc.dispose();
  }
}

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  test('header repeats on every page of a 3+ page study guide', () async {
    final guide = sampleGuide();
    final bytes = await StudyGuidePdfService.build(guide,
        fonts: StudyGuidePdfFonts.builtIn());

    final sample = Platform.environment['WRITE_STUDY_GUIDE_SAMPLE'];
    if (sample != null && sample.isNotEmpty) {
      File(sample).writeAsBytesSync(bytes);
    }

    final pages = pageTexts(bytes);
    expect(pages.length, greaterThanOrEqualTo(3),
        reason: 'fixture must span 3+ pages to prove the header repeats');

    final subtitle = StudyGuidePdfService.subtitleFor(guide);
    expect(subtitle, 'Senior Operations Analyst at Northwind Logistics');
    for (var i = 0; i < pages.length; i++) {
      final text = _squash(pages[i]);
      expect(text, contains(StudyGuidePdfService.headerTitle),
          reason: 'page ${i + 1} is missing the header title');
      expect(text, contains(subtitle),
          reason: 'page ${i + 1} is missing the role/company line');
      // Header appears once per page, not duplicated into the body.
      expect(StudyGuidePdfService.headerTitle.allMatches(text).length, 1,
          reason: 'page ${i + 1}');
    }

    // Every question made it into the document, in order.
    final all = _squash(pages.join(' '));
    var from = 0;
    for (var i = 1; i <= guide.questions.length; i++) {
      final at = all.indexOf('Question $i:', from);
      expect(at, isNot(-1), reason: 'Question $i missing');
      from = at;
    }
  });

  test('subtitle drops empty role or company', () {
    final g = sampleGuide(questions: 0)..companyName = '';
    expect(StudyGuidePdfService.subtitleFor(g), 'Senior Operations Analyst');
    g
      ..companyName = 'Acme'
      ..roleTitle = '';
    expect(StudyGuidePdfService.subtitleFor(g), 'Acme');
  });
}
