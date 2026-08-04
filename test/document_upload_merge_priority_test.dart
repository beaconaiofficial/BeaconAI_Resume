import 'package:flutter_test/flutter_test.dart';

import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/screens/document_upload_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Closing item 2 — Stage 1's one deliberately-left-open gap.
//
// Stage 1's document-type source-of-truth priority (STP > NCOER > JST for
// duty dates/station; NCOER > JST > STP for duty narrative) has only ever
// been proven at the ResumeSanitizer unit level — resume_sanitizer_test.dart
// calls mergeCrossDocumentDuplicateRoles/_preferredSide directly with
// hand-built, already-_sourceDocType-stamped maps. That proves the ALGORITHM
// works; it has never proven that DocumentUploadScreen's real merge path
// (mergeResults) actually WIRES a file's self-reported documentType onto its
// entries and calls that algorithm at all — a stamping bug (wrong field
// name, wrong timing, silently skipped) wouldn't be caught by a unit test
// that already assumes the stamp is present.
//
// mergeResults was a private instance method (_mergeResults) with no
// reachable seam for this until now — it never touched instance state
// (widget/ref/setState), so it was moved to a static method on
// DocumentUploadScreen (same treatment as the pre-existing
// remainingUploadSlots), making it directly callable here with real
// FileExtractionResult fixtures — the actual production entry point, not a
// re-implementation of it.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  test(
      'two documents with the same normalized experience title, different '
      'documentType, and a genuine duty-station conflict — the Stage 1 '
      'priority tiebreak fires through the real mergeResults path, not just '
      'at the ResumeSanitizer unit level', () {
    const stpFile = FileExtractionResult(
      fileName: 'stp.pdf',
      fileType: FileTypeEnum.pdf,
      rawText: '',
      documentType: 'stp',
      mappings: [
        {
          'field': 'experience',
          'confidence': 0.9,
          'suggestedValue': [
            {
              'title': 'Network Communications Systems Operator',
              'company': 'U.S. Army',
              'location': 'Fort Hood, TX',
              'startDate': '2019',
              'endDate': null,
              'isCurrent': true,
              'bullets': [
                'Managed current assignment\'s network operations',
              ],
            },
          ],
        },
      ],
      pendingDecisions: [],
      unplacedFindings: [],
    );

    const ncoerFile = FileExtractionResult(
      fileName: 'ncoer.pdf',
      fileType: FileTypeEnum.pdf,
      rawText: '',
      documentType: 'ncoer',
      mappings: [
        {
          'field': 'experience',
          'confidence': 0.85,
          'suggestedValue': [
            {
              // Same title after normalization (case/whitespace) — crosses
              // the exact-title-match bar _isConfidentCrossDocumentDuplicateRole
              // requires to treat these as the same real-world role.
              'title': 'network communications systems operator',
              'company': 'U.S. Army',
              // Genuinely different real place, not a formatting variant —
              // the real conflict this fixture is designed to cross.
              'location': 'Fort Bragg, NC',
              'startDate': '2019',
              'endDate': null,
              'isCurrent': true,
              'bullets': [
                'Led a team of 6 in daily network operations',
                'Reduced outage response time by 30%',
              ],
            },
          ],
        },
      ],
      pendingDecisions: [],
      unplacedFindings: [],
    );

    final mappings =
        DocumentUploadScreen.mergeResults([stpFile, ncoerFile]);

    final experienceRow =
        mappings.firstWhere((m) => m['field'] == 'experience');
    final experience =
        (experienceRow['suggestedValue'] as List).cast<Map<String, dynamic>>();

    expect(experience.length, 1,
        reason: 'same real-world role recorded across two documents must '
            'cluster into one entry, not survive as two duplicates — proves '
            'mergeResults actually invokes '
            'ResumeSanitizer.mergeCrossDocumentDuplicateRoles rather than '
            'just unioning raw entries');

    final merged = experience.first;
    expect(merged['location'], 'Fort Hood, TX',
        reason: 'STP outranks NCOER for duty station per the Stage 1 '
            'priority table — this only fires if mergeResults correctly '
            'stamped _sourceDocType onto each entry from the file\'s own '
            'self-reported documentType (stp/ncoer) before handing off to '
            'the sanitizer; a stamping bug would silently fall back to the '
            'unknown-type heuristic and this would fail');

    final bulletTexts = (merged['bullets'] as List)
        .map((b) => (b as Map<String, dynamic>)['text'] as String)
        .toList();
    expect(
      bulletTexts,
      containsAll([
        'Managed current assignment\'s network operations',
        'Led a team of 6 in daily network operations',
        'Reduced outage response time by 30%',
      ]),
      reason: 'both documents\' bullets must survive the merge regardless of '
          'which document won the duty-station tiebreak — priority only '
          'decides identity fields, never drops content',
    );
  });
}
