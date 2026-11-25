import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/app_enums.dart';
import '../models/supporting_models.dart';

/// The three weights the Interview Study Guide PDF uses.
class StudyGuidePdfFonts {
  const StudyGuidePdfFonts({
    required this.regular,
    required this.semiBold,
    required this.bold,
  });

  final pw.Font regular;
  final pw.Font semiBold;
  final pw.Font bold;

  /// Inter, as shipped in the app. Downloaded (and cached) by `printing`.
  static Future<StudyGuidePdfFonts> inter() async => StudyGuidePdfFonts(
        regular: await PdfGoogleFonts.interRegular(),
        semiBold: await PdfGoogleFonts.interSemiBold(),
        bold: await PdfGoogleFonts.interBold(),
      );

  /// Built-in PDF fonts: no network. Used by tests.
  static StudyGuidePdfFonts builtIn() => StudyGuidePdfFonts(
        regular: pw.Font.helvetica(),
        semiBold: pw.Font.helveticaBold(),
        bold: pw.Font.helveticaBold(),
      );
}

/// Builds the Pro Interview Prep study guide PDF.
class StudyGuidePdfService {
  StudyGuidePdfService._();

  static const String headerTitle = 'Interview Preparation Guide';

  /// The role/company line under the header title, e.g.
  /// "Product Manager at Acme". Empty parts are dropped.
  static String subtitleFor(InterviewStudyGuide guide) =>
      [guide.roleTitle, guide.companyName]
          .where((s) => s.isNotEmpty)
          .join(' at ');

  static Future<Uint8List> build(
    InterviewStudyGuide guide, {
    StudyGuidePdfFonts? fonts,
  }) async {
    final f = fonts ?? await StudyGuidePdfFonts.inter();
    final doc = pw.Document(
      title: 'Interview Prep — ${guide.roleTitle}',
    );

    const navy = PdfColor.fromInt(0xFF1A1A2E);
    const accent = PdfColor.fromInt(0xFF2C4A7C);
    const gray = PdfColor.fromInt(0xFF6B7280);
    const lightGray = PdfColor.fromInt(0xFFE5E7EB);

    pw.Widget categoryBadge(QuestionCategoryEnum category) {
      final label = switch (category) {
        QuestionCategoryEnum.behavioral => 'BEHAVIORAL',
        QuestionCategoryEnum.roleSpecific => 'ROLE-SPECIFIC',
        QuestionCategoryEnum.companySpecific => 'COMPANY-SPECIFIC',
      };
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: pw.BoxDecoration(
          color: accent,
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Text(label,
            style: pw.TextStyle(
                font: f.bold, fontSize: 7, color: PdfColors.white)),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 48),
        // Repeats on every page — see the matching comment in
        // PdfExportService.generateResumePdf for why this must be header:,
        // not the first item in build:.
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(headerTitle,
                style: pw.TextStyle(font: f.bold, fontSize: 22, color: navy)),
            pw.SizedBox(height: 4),
            pw.Text(
              subtitleFor(guide),
              style:
                  pw.TextStyle(font: f.semiBold, fontSize: 13, color: accent),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(color: lightGray, thickness: 0.8),
            pw.SizedBox(height: 16),
          ],
        ),
        build: (context) => [
          for (final q in guide.questions) ...[
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 16),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: lightGray, width: 0.8),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  categoryBadge(q.category),
                  pw.SizedBox(height: 6),
                  pw.Text(q.questionText,
                      style: pw.TextStyle(
                          font: f.semiBold, fontSize: 12, color: navy)),
                  if (q.answerGuide.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text('How to answer:',
                        style: pw.TextStyle(
                            font: f.semiBold, fontSize: 9, color: accent)),
                    pw.SizedBox(height: 3),
                    pw.Text(q.answerGuide,
                        style: pw.TextStyle(
                            font: f.regular,
                            fontSize: 10,
                            color: gray,
                            lineSpacing: 2)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }
}
