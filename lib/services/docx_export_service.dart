import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

import '../models/resume.dart';
import '../models/resume_sections.dart';
import '../models/app_enums.dart';
import '../widgets/resume_template_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DocxExportService
//
// Generates an ATS-safe, single-column .docx file using raw OOXML.
// A .docx file is a ZIP archive containing XML parts — this builds the
// minimum valid structure: [Content_Types].xml, _rels, word/document.xml,
// word/_rels/document.xml.rels, word/styles.xml.
//
// Spec §11 ATS Export Rule: DOCX always single-column regardless of template,
// matching the same rule applied to PDF export.
// Spec §4: DOCX export gated to Basic+.
// ─────────────────────────────────────────────────────────────────────────────

class DocxExportService {
  DocxExportService._();

  static Future<Uint8List> generateResumeDocx({
    required Resume resume,
    required ResumeRenderData data,
  }) async {
    final documentXml = _buildDocumentXml(data);

    final archive = Archive();

    archive.addFile(_textFile('[Content_Types].xml', _contentTypesXml));
    archive.addFile(_textFile('_rels/.rels', _rootRelsXml));
    archive.addFile(_textFile('word/document.xml', documentXml));
    archive
        .addFile(_textFile('word/_rels/document.xml.rels', _documentRelsXml));
    archive.addFile(_textFile('word/styles.xml', _stylesXml));
    archive.addFile(_textFile('docProps/core.xml', _coreXml(resume, data)));
    archive.addFile(_textFile('docProps/app.xml', _appXml));

    final zipBytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipBytes!);
  }

  static ArchiveFile _textFile(String path, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(path, bytes.length, bytes);
  }

  // ── XML escaping ────────────────────────────────────────────────────────────

  static String _esc(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  // ── Document body builder ───────────────────────────────────────────────────

  static String _buildDocumentXml(ResumeRenderData data) {
    final buffer = StringBuffer();

    buffer.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buffer.writeln(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');
    buffer.writeln('<w:body>');

    // ── Contact header ─────────────────────────────────────────────────────
    if (data.contact.fullName.isNotEmpty) {
      buffer.writeln(_heading(data.contact.fullName, level: 1, size: 32));
    }
    if (data.contact.professionalTitle.isNotEmpty) {
      buffer.writeln(_paragraph(data.contact.professionalTitle,
          size: 22, color: '2C4A7C'));
    }
    final contactLine = [
      data.contact.cityState,
      data.contact.phone,
      data.contact.email,
      data.contact.linkedInUrl,
    ].where((s) => s != null && s.isNotEmpty).join('   |   ');
    if (contactLine.isNotEmpty) {
      buffer.writeln(_paragraph(contactLine, size: 18, color: '6B7280'));
    }

    buffer.writeln(_horizontalRule());

    // ── Summary ───────────────────────────────────────────────────────────
    if (data.summary.isNotEmpty) {
      buffer.writeln(_sectionHeading('PROFESSIONAL SUMMARY'));
      buffer.writeln(_paragraph(data.summary, size: 20));
    }

    // ── Experience ────────────────────────────────────────────────────────
    final exp = data.experience.where((e) => e.title.isNotEmpty).toList();
    if (exp.isNotEmpty) {
      buffer.writeln(_sectionHeading('PROFESSIONAL EXPERIENCE'));
      for (final e in exp) {
        final titleLine = [e.title, e.company, e.location]
            .where((s) => s.isNotEmpty)
            .join('  |  ');
        buffer.writeln(_paragraph(
          '$titleLine\t${e.dateRange}',
          size: 21,
          bold: true,
          tabRight: true,
        ));
        for (final b in e.bullets.where((b) => b.isNotEmpty)) {
          buffer.writeln(_bulletParagraph(b, size: 20));
        }
        buffer.writeln(_spacerParagraph());
      }
    }

    // ── Education ─────────────────────────────────────────────────────────
    final edu = data.education.where((e) => e.institution.isNotEmpty).toList();
    if (edu.isNotEmpty) {
      buffer.writeln(_sectionHeading('EDUCATION'));
      for (final e in edu) {
        buffer.writeln(_paragraph(
          '${e.institution}\t${e.graduationYear}',
          size: 21,
          bold: true,
          tabRight: true,
        ));
        final degreeLine =
            [e.degree, e.fieldOfStudy].where((s) => s.isNotEmpty).join(', ');
        if (degreeLine.isNotEmpty) {
          buffer.writeln(_paragraph(degreeLine, size: 20, color: '6B7280'));
        }
        if (e.gpa != null && e.gpa!.isNotEmpty) {
          buffer
              .writeln(_paragraph('GPA: ${e.gpa}', size: 18, color: '6B7280'));
        }
        buffer.writeln(_spacerParagraph());
      }
    }

    // ── Skills ────────────────────────────────────────────────────────────
    // ATS rule: rendered as a table structure, same as PDF export.
    if (data.skills.isNotEmpty) {
      buffer.writeln(_sectionHeading('SKILLS'));
      buffer.writeln(_skillsTable(data.skills));
    }

    // ── Certifications ────────────────────────────────────────────────────
    final certs = data.certifications.where((c) => c.name.isNotEmpty).toList();
    if (certs.isNotEmpty) {
      buffer.writeln(_sectionHeading('CERTIFICATIONS'));
      for (final c in certs) {
        buffer.writeln(_paragraph(
          '${c.name}  —  ${c.issuer}\t${c.dateEarned}',
          size: 21,
          bold: true,
          tabRight: true,
        ));
      }
    }

    // Section properties — US Letter, 1 inch margins
    buffer.writeln('<w:sectPr>');
    buffer.writeln('<w:pgSz w:w="12240" w:h="15840"/>');
    buffer.writeln(
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>');
    buffer.writeln('</w:sectPr>');

    buffer.writeln('</w:body>');
    buffer.writeln('</w:document>');

    return buffer.toString();
  }

  // ── XML fragment builders ───────────────────────────────────────────────────

  static String _heading(String text, {required int level, required int size}) {
    return '<w:p><w:pPr><w:spacing w:after="60"/></w:pPr>'
        '<w:r><w:rPr><w:b/><w:sz w:val="$size"/></w:rPr>'
        '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>';
  }

  static String _sectionHeading(String text) {
    return '<w:p><w:pPr><w:spacing w:before="240" w:after="80"/>'
        '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="4" w:color="E5E7EB"/></w:pBdr>'
        '</w:pPr>'
        '<w:r><w:rPr><w:b/><w:sz w:val="18"/><w:color w:val="2C4A7C"/>'
        '<w:spacing w:val="20"/></w:rPr>'
        '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>';
  }

  static String _paragraph(
    String text, {
    required int size,
    bool bold = false,
    String? color,
    bool tabRight = false,
  }) {
    final boldTag = bold ? '<w:b/>' : '';
    final colorTag = color != null ? '<w:color w:val="$color"/>' : '';
    final tabDef =
        tabRight ? '<w:tabs><w:tab w:val="right" w:pos="9360"/></w:tabs>' : '';

    if (tabRight && text.contains('\t')) {
      final parts = text.split('\t');
      return '<w:p><w:pPr>$tabDef<w:spacing w:after="40"/></w:pPr>'
          '<w:r><w:rPr>$boldTag<w:sz w:val="$size"/>$colorTag</w:rPr>'
          '<w:t xml:space="preserve">${_esc(parts[0])}</w:t></w:r>'
          '<w:r><w:rPr><w:sz w:val="${size - 2}"/><w:color w:val="6B7280"/></w:rPr>'
          '<w:tab/><w:t xml:space="preserve">${_esc(parts.length > 1 ? parts[1] : '')}</w:t></w:r>'
          '</w:p>';
    }

    return '<w:p><w:pPr><w:spacing w:after="40"/></w:pPr>'
        '<w:r><w:rPr>$boldTag<w:sz w:val="$size"/>$colorTag</w:rPr>'
        '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>';
  }

  static String _bulletParagraph(String text, {required int size}) {
    return '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>'
        '<w:spacing w:after="30"/><w:ind w:left="360"/></w:pPr>'
        '<w:r><w:rPr><w:sz w:val="$size"/></w:rPr>'
        '<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>';
  }

  static String _spacerParagraph() {
    return '<w:p><w:pPr><w:spacing w:after="80"/></w:pPr></w:p>';
  }

  static String _horizontalRule() {
    return '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="6" w:color="E5E7EB"/></w:pBdr>'
        '<w:spacing w:after="160"/></w:pPr></w:p>';
  }

  /// Skills rendered as an actual Word table — same ATS-table principle as PDF.
  static String _skillsTable(List<SkillEntry> skills) {
    final grouped = <SkillCategoryEnum, List<SkillEntry>>{};
    for (final s in skills) {
      grouped.putIfAbsent(s.category, () => []).add(s);
    }

    if (grouped.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('<w:tbl>');
    buffer.writeln('<w:tblPr>'
        '<w:tblW w:w="9360" w:type="dxa"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:color="E5E7EB"/>'
        '<w:left w:val="single" w:sz="4" w:color="E5E7EB"/>'
        '<w:bottom w:val="single" w:sz="4" w:color="E5E7EB"/>'
        '<w:right w:val="single" w:sz="4" w:color="E5E7EB"/>'
        '<w:insideH w:val="single" w:sz="4" w:color="E5E7EB"/>'
        '<w:insideV w:val="single" w:sz="4" w:color="E5E7EB"/>'
        '</w:tblBorders>'
        '</w:tblPr>');
    buffer.writeln('<w:tblGrid>'
        '<w:gridCol w:w="2340"/>'
        '<w:gridCol w:w="7020"/>'
        '</w:tblGrid>');

    for (final entry in grouped.entries) {
      final categoryName = entry.key.displayName;
      final skillNames = entry.value.map((s) => s.name).join(', ');

      buffer.writeln('<w:tr>');
      buffer.writeln('<w:tc><w:tcPr><w:tcW w:w="2340" w:type="dxa"/></w:tcPr>'
          '<w:p><w:r><w:rPr><w:b/><w:sz w:val="18"/><w:color w:val="2C4A7C"/></w:rPr>'
          '<w:t xml:space="preserve">${_esc(categoryName)}</w:t></w:r></w:p></w:tc>');
      buffer.writeln('<w:tc><w:tcPr><w:tcW w:w="7020" w:type="dxa"/></w:tcPr>'
          '<w:p><w:r><w:rPr><w:sz w:val="19"/></w:rPr>'
          '<w:t xml:space="preserve">${_esc(skillNames)}</w:t></w:r></w:p></w:tc>');
      buffer.writeln('</w:tr>');
    }

    buffer.writeln('</w:tbl>');
    buffer.writeln('<w:p><w:pPr><w:spacing w:after="120"/></w:pPr></w:p>');
    return buffer.toString();
  }

  // ── Static OOXML package parts ──────────────────────────────────────────────

  static const String _contentTypesXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''';

  static const String _rootRelsXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''';

  static const String _documentRelsXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

  static const String _stylesXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults>
<w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="20"/></w:rPr></w:rPrDefault>
</w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal">
<w:name w:val="Normal"/>
</w:style>
</w:styles>''';

  static String _coreXml(Resume resume, ResumeRenderData data) {
    final now = DateTime.now().toIso8601String();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<dc:title>${_esc(resume.displayTitle)}</dc:title>
<dc:creator>${_esc(data.contact.fullName)}</dc:creator>
<dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>
<dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>
</cp:coreProperties>''';
  }

  static const String _appXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
<Application>BeaconAI Resume</Application>
</Properties>''';
}
