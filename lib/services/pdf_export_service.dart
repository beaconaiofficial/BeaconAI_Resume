import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/resume.dart';
import '../models/resume_sections.dart';
import '../models/app_enums.dart';
import '../widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PdfExportService
//
// Generates ATS-safe PDF resumes from resume section data.
//
// Spec §11 ATS Export Rule:
//   PDF always generated from single-column content regardless of template.
//   Skills rendered as a PDF table structure (not text columns) for parseability.
//   Visual layout is a display layer only — the PDF content is always single-column.
// ─────────────────────────────────────────────────────────────────────────────

class PdfExportService {
  PdfExportService._();

  // ── Colors (PDF format — no Flutter Color) ──────────────────────────────────
  static const _navy = PdfColor.fromInt(0xFF1A1A2E);
  static const _accent = PdfColor.fromInt(0xFF2C4A7C);
  static const _gray = PdfColor.fromInt(0xFF6B7280);
  static const _lightGray = PdfColor.fromInt(0xFFE5E7EB);

  /// Generate a cover letter PDF.
  /// Produces a clean letter-format document: sender header, date, recipient,
  /// greeting, body paragraphs, and closing — all from [content].
  static Future<Uint8List> generateCoverLetterPdf({
    required String content,
    required ContactInfo senderContact,
    String? companyName,
    String? hiringManager,
  }) async {
    final doc = pw.Document(
      title: 'Cover Letter',
      author: senderContact.fullName,
    );

    final regularFont = await PdfGoogleFonts.interRegular();
    final boldFont = await PdfGoogleFonts.interBold();
    final semiBoldFont = await PdfGoogleFonts.interSemiBold();
    final italicFont = await PdfGoogleFonts.interItalic();

    // Format today's date
    final now = DateTime.now();
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';

    // Build greeting line
    final greeting = hiringManager != null && hiringManager.isNotEmpty
        ? 'Dear $hiringManager,'
        : 'Dear Hiring Team,';

    // Build closing line
    final closing = senderContact.fullName.isNotEmpty
        ? senderContact.fullName
        : 'Applicant';

    // Split body into paragraphs on blank lines; fall back to single block
    final paragraphs = content
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 56, vertical: 52),
        build: (context) => [
          // ── Sender header ──────────────────────────────────────────────
          if (senderContact.fullName.isNotEmpty)
            pw.Text(
              senderContact.fullName,
              style: pw.TextStyle(font: boldFont, fontSize: 16, color: _navy),
            ),
          if (senderContact.professionalTitle.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              senderContact.professionalTitle,
              style: pw.TextStyle(font: semiBoldFont, fontSize: 10, color: _accent),
            ),
          ],
          pw.SizedBox(height: 4),
          pw.Text(
            [
              senderContact.email,
              senderContact.phone,
              senderContact.linkedInUrl,
            ].where((s) => s != null && s.isNotEmpty).cast<String>().join('   |   '),
            style: pw.TextStyle(font: regularFont, fontSize: 9, color: _gray),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(color: _lightGray, thickness: 0.6),
          pw.SizedBox(height: 16),

          // ── Date ────────────────────────────────────────────────────────
          pw.Text(
            dateStr,
            style: pw.TextStyle(font: regularFont, fontSize: 10, color: _gray),
          ),
          pw.SizedBox(height: 16),

          // ── Recipient block ─────────────────────────────────────────────
          if (companyName != null && companyName.isNotEmpty) ...[
            pw.Text(
              companyName,
              style: pw.TextStyle(font: semiBoldFont, fontSize: 10, color: _navy),
            ),
            if (hiringManager != null && hiringManager.isNotEmpty)
              pw.Text(
                'Attn: $hiringManager',
                style: pw.TextStyle(font: regularFont, fontSize: 10, color: _navy),
              ),
            pw.SizedBox(height: 16),
          ],

          // ── Greeting ────────────────────────────────────────────────────
          pw.Text(
            greeting,
            style: pw.TextStyle(font: regularFont, fontSize: 10.5, color: _navy),
          ),
          pw.SizedBox(height: 12),

          // ── Body paragraphs ─────────────────────────────────────────────
          for (final paragraph in paragraphs) ...[
            pw.Text(
              paragraph,
              style: pw.TextStyle(
                font: regularFont,
                fontSize: 10.5,
                lineSpacing: 1.5,
                color: _navy,
              ),
            ),
            pw.SizedBox(height: 12),
          ],

          // ── Closing ─────────────────────────────────────────────────────
          pw.SizedBox(height: 4),
          pw.Text(
            'Sincerely,',
            style: pw.TextStyle(font: italicFont, fontSize: 10.5, color: _navy),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            closing,
            style: pw.TextStyle(font: semiBoldFont, fontSize: 10.5, color: _navy),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Generate a PDF document from resume data.
  /// Returns raw PDF bytes ready for saving or sharing.
  static Future<Uint8List> generateResumePdf({
    required Resume resume,
    required ResumeRenderData data,
  }) async {
    final doc = pw.Document(
      title: resume.displayTitle,
      author: data.contact.fullName,
    );

    // Load fonts
    final regularFont = await PdfGoogleFonts.interRegular();
    final boldFont = await PdfGoogleFonts.interBold();
    final semiBoldFont = await PdfGoogleFonts.interSemiBold();
    final mediumFont = await PdfGoogleFonts.interMedium();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 48),
        build: (context) => [
          // ── Contact Header ──────────────────────────────────────────────
          _buildContactHeader(
              data.contact, boldFont, regularFont, semiBoldFont),
          pw.SizedBox(height: 14),
          pw.Divider(color: _lightGray, thickness: 0.8),
          pw.SizedBox(height: 10),

          // ── Summary ────────────────────────────────────────────────────
          if (data.summary.isNotEmpty) ...[
            _sectionHeader('PROFESSIONAL SUMMARY', semiBoldFont),
            pw.Text(
              data.summary,
              style: pw.TextStyle(
                  font: regularFont,
                  fontSize: 10,
                  lineSpacing: 1.4,
                  color: _navy),
            ),
            pw.SizedBox(height: 14),
          ],

          // ── Experience ─────────────────────────────────────────────────
          if (data.experience.any((e) => e.title.isNotEmpty)) ...[
            _sectionHeader('PROFESSIONAL EXPERIENCE', semiBoldFont),
            ...data.experience.where((e) => e.title.isNotEmpty).map((e) =>
                _buildExperienceEntry(e, boldFont, regularFont, mediumFont)),
          ],

          // ── Education ──────────────────────────────────────────────────
          if (data.education.any((e) => e.institution.isNotEmpty)) ...[
            _sectionHeader('EDUCATION', semiBoldFont),
            ...data.education
                .where((e) => e.institution.isNotEmpty)
                .map((e) => _buildEducationEntry(e, boldFont, regularFont)),
          ],

          // ── Skills ─────────────────────────────────────────────────────
          // Spec: PDF renders skills as a table structure for ATS parseability
          if (data.skills.isNotEmpty) ...[
            _sectionHeader('SKILLS', semiBoldFont),
            _buildSkillsTable(data.skills, regularFont, semiBoldFont),
            pw.SizedBox(height: 14),
          ],

          // ── Certifications ─────────────────────────────────────────────
          if (data.certifications.any((c) => c.name.isNotEmpty)) ...[
            _sectionHeader('CERTIFICATIONS', semiBoldFont),
            ...data.certifications
                .where((c) => c.name.isNotEmpty)
                .map((c) => _buildCertEntry(c, boldFont, regularFont)),
          ],
        ],
      ),
    );

    return doc.save();
  }

  // ── Section builders ────────────────────────────────────────────────────────

  static pw.Widget _buildContactHeader(
    ContactInfo c,
    pw.Font boldFont,
    pw.Font regularFont,
    pw.Font semiBoldFont,
  ) {
    final contactParts = [
      c.cityState,
      c.phone,
      c.email,
      c.linkedInUrl,
    ].where((s) => s != null && s.isNotEmpty).cast<String>().join('   |   ');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (c.fullName.isNotEmpty)
          pw.Text(
            c.fullName,
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 22,
              color: _navy,
            ),
          ),
        if (c.professionalTitle.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            c.professionalTitle,
            style: pw.TextStyle(
              font: semiBoldFont,
              fontSize: 12,
              color: _accent,
            ),
          ),
        ],
        if (contactParts.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            contactParts,
            style: pw.TextStyle(
              font: regularFont,
              fontSize: 9,
              color: _gray,
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _sectionHeader(String title, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            font: font,
            fontSize: 9,
            letterSpacing: 1.2,
            color: _accent,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Divider(color: _lightGray, thickness: 0.6),
        pw.SizedBox(height: 6),
      ],
    );
  }

  static pw.Widget _buildExperienceEntry(
    ExperienceEntry e,
    pw.Font boldFont,
    pw.Font regularFont,
    pw.Font mediumFont,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Title | Company | Location + Date
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  [e.title, e.company, e.location]
                      .where((s) => s.isNotEmpty)
                      .join('  |  '),
                  style: pw.TextStyle(
                      font: boldFont, fontSize: 10.5, color: _navy),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                e.dateRange,
                style:
                    pw.TextStyle(font: regularFont, fontSize: 9, color: _gray),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          // Bullets
          ...e.bullets.where((b) => b.isNotEmpty).map(
                (b) => pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2, left: 10),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('•  ',
                          style: pw.TextStyle(
                              font: regularFont, fontSize: 10, color: _gray)),
                      pw.Expanded(
                        child: pw.Text(
                          b,
                          style: pw.TextStyle(
                              font: regularFont,
                              fontSize: 10,
                              lineSpacing: 1.3,
                              color: _navy),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  static pw.Widget _buildEducationEntry(
    EducationEntry e,
    pw.Font boldFont,
    pw.Font regularFont,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  e.institution,
                  style: pw.TextStyle(
                      font: boldFont, fontSize: 10.5, color: _navy),
                ),
                pw.Text(
                  [e.degree, e.fieldOfStudy]
                      .where((s) => s.isNotEmpty)
                      .join(', '),
                  style: pw.TextStyle(
                      font: regularFont, fontSize: 10, color: _gray),
                ),
                if (e.gpa != null && e.gpa!.isNotEmpty)
                  pw.Text('GPA: ${e.gpa}',
                      style: pw.TextStyle(
                          font: regularFont, fontSize: 9, color: _gray)),
              ],
            ),
          ),
          pw.Text(
            e.graduationYear,
            style: pw.TextStyle(font: regularFont, fontSize: 9, color: _gray),
          ),
        ],
      ),
    );
  }

  /// Skills as a PDF table for ATS parseability.
  /// Spec: two-column grouped by category. Rendered as PDF table structure.
  static pw.Widget _buildSkillsTable(
    List<SkillEntry> skills,
    pw.Font regularFont,
    pw.Font semiBoldFont,
  ) {
    // Group by category
    final grouped = <SkillCategoryEnum, List<SkillEntry>>{};
    for (final s in skills) {
      grouped.putIfAbsent(s.category, () => []).add(s);
    }

    final rows = <pw.TableRow>[];

    for (final entry in grouped.entries) {
      final categoryName = entry.key.displayName;
      final skillNames = entry.value.map((s) => s.name).join(', ');

      rows.add(pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            child: pw.Text(
              categoryName,
              style:
                  pw.TextStyle(font: semiBoldFont, fontSize: 9, color: _accent),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            child: pw.Text(
              skillNames,
              style:
                  pw.TextStyle(font: regularFont, fontSize: 9.5, color: _navy),
            ),
          ),
        ],
      ));
    }

    if (rows.isEmpty) {
      // Flat list fallback
      return pw.Text(
        skills.map((s) => s.name).join('   ·   '),
        style: pw.TextStyle(font: regularFont, fontSize: 10, color: _navy),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _lightGray, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(3),
      },
      children: rows,
    );
  }

  static pw.Widget _buildCertEntry(
    CertificationEntry c,
    pw.Font boldFont,
    pw.Font regularFont,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              '${c.name}  —  ${c.issuer}',
              style: pw.TextStyle(font: boldFont, fontSize: 10.5, color: _navy),
            ),
          ),
          pw.Text(
            c.dateEarned,
            style: pw.TextStyle(font: regularFont, fontSize: 9, color: _gray),
          ),
        ],
      ),
    );
  }
}
