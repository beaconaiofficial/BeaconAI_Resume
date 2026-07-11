import 'dart:convert';
import 'package:uuid/uuid.dart';

import '../models/app_enums.dart';
import '../models/resume_sections.dart';
import '../utils/app_logger.dart';
import 'hive_service.dart';
import 'resume_sanitizer.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// ResumeMigrationService
//
// Retroactive cleanup for resumes stored before the entry-classification
// pass existed. Extraction-time sanitization (dedup, bullet cap,
// training-vs-employment classification) only ever ran going forward — any
// resume already in Hive kept its old-shape data indefinitely. This runs
// once, applies the same structural heuristics used as the fallback path
// when a model classification is missing, and stops there: nothing here
// requires a Claude call, so nothing here is confident enough to silently
// delete a certification the way the old bug did. Likely-compliance-training
// certs are flagged for the user to resolve, never removed by the migration
// itself.
//
// Version-gated via UserSettings.experienceSanitizedVersion so it runs
// exactly once per version bump, and is safe to interrupt: each resume's
// sections are saved to Hive as soon as that resume is processed, not
// batched into one all-or-nothing transaction. If the app is killed
// mid-run, the version flag is only set after every resume completes, so
// the next launch simply retries — already-clean resumes are a no-op on
// re-run (see idempotency notes on _sanitizeResume).
// ─────────────────────────────────────────────────────────────────────────────

class ResumeMigrationService {
  ResumeMigrationService._();

  /// Runs the migration if UserSettings.experienceSanitizedVersion is
  /// behind ResumeSanitizer.currentSanitizationVersion. No-op otherwise.
  static Future<void> runIfNeeded() async {
    final settings = HiveService.settings;
    if (settings.experienceSanitizedVersion >=
        ResumeSanitizer.currentSanitizationVersion) {
      return;
    }

    devLog('[MIGRATION] Starting retroactive sanitization '
        '(v${settings.experienceSanitizedVersion} → '
        'v${ResumeSanitizer.currentSanitizationVersion})');

    var resumesTouched = 0;
    var resumesFailed = 0;
    var entriesReclassified = 0;
    var entriesDeduped = 0;
    var entriesBulletCapped = 0;
    var certsFlagged = 0;
    var educationDeduped = 0;

    // .toList() — iterate a snapshot, not the live box, since sanitizing
    // can write to the section box while we're mid-loop over resumes.
    final resumeIds = HiveService.resumeBox.values.map((r) => r.id).toList();

    for (final resumeId in resumeIds) {
      try {
        final result = await _sanitizeResume(resumeId);
        if (result.changed) resumesTouched++;
        entriesReclassified += result.reclassified;
        entriesDeduped += result.deduped;
        entriesBulletCapped += result.bulletCapped;
        certsFlagged += result.certsFlagged;
        educationDeduped += result.educationDeduped;
      } catch (e, st) {
        resumesFailed++;
        devLog('[MIGRATION] Failed to sanitize resume $resumeId: $e');
        devLog('[MIGRATION] stacktrace: $st');
        // Continue with the remaining resumes — one bad resume shouldn't
        // block the rest, and since the version flag is only advanced
        // after the full loop, a failure here just means this resume gets
        // retried (along with everything else) on the next launch too.
      }
    }

    settings.experienceSanitizedVersion =
        ResumeSanitizer.currentSanitizationVersion;
    await HiveService.saveSettings(settings);

    devLog('[MIGRATION] Complete — ${resumeIds.length} resume(s) '
        'scanned, $resumesTouched touched, $resumesFailed failed, '
        '$entriesReclassified entries reclassified (training → '
        'certification), $entriesDeduped bare-duplicate/duplicate-of-cert '
        'entries removed, $entriesBulletCapped entries bullet-capped, '
        '$certsFlagged certification(s) flagged for review, '
        '$educationDeduped education entries deduplicated');
  }

  /// Sanitizes one resume's stored experience and certification sections.
  /// Idempotent: re-running against already-clean data produces the same
  /// result with zero further changes (training reclassification finds
  /// nothing left to reclassify, dedup finds no bare stubs, bullet cap is a
  /// no-op under the cap, and cert flags are only ever set once and then
  /// left alone on subsequent runs).
  static Future<_ResumeSanitizeResult> _sanitizeResume(String resumeId) async {
    final box = HiveService.resumeSectionBox;
    var reclassified = 0;
    var deduped = 0;
    var crossDocMerged = 0;
    var crossReferenceDropped = 0;
    var bulletCapped = 0;
    var certsFlagged = 0;
    var educationDeduped = 0;
    var changed = false;

    // Same ordered pass as the live extraction pipeline
    // (CloudflareWorkerService.parseFieldMappings): reclassify/route, THEN
    // build the final certifications list, THEN dedup experience against
    // it (bare stubs, then same-event-as-a-cert), THEN cap bullets.
    // Getting this order right is exactly what Priority 3 fixed — running
    // dedup before the final certifications list exists (or capping
    // bullets before dedup) is how a bare stub and a misclassified
    // duplicate survived a fresh extraction in the first place.

    // ── Experience: load + reclassify (routing only, no dedup/cap yet) ──
    final expKey = '${resumeId}_${SectionTypeEnum.experience.name}';
    final expSection = box.get(expKey);
    final promotedFromExperience = <dynamic>[];
    List<dynamic> expKept = [];

    if (expSection != null) {
      List<dynamic> entries;
      try {
        entries = jsonDecode(expSection.data) as List<dynamic>;
      } catch (_) {
        entries = [];
      }

      // Reclassify obvious training entries using the same fallback
      // keyword heuristic applied at extraction time when the model
      // didn't return an entryType — this is a structural read of the
      // entry's own company field, not a new judgment call, so it's safe
      // to auto-apply without asking.
      for (final raw in entries) {
        final e = raw as Map<String, dynamic>;
        final company = (e['company'] as String? ?? '').toLowerCase();
        final isTraining = ResumeSanitizer.fallbackTrainingCompanyPatterns
            .any((p) => company.contains(p));
        if (isTraining) {
          promotedFromExperience.add({
            'id': 'uuid-placeholder',
            'name': e['title'] as String? ?? '',
            'issuer': e['company'] as String? ?? '',
            'dateEarned': e['startDate'] as String? ?? '',
            'expiresDate': null,
            'credentialId': null,
            'isAIPrefilled': e['isAIPrefilled'] as bool? ?? false,
          });
          reclassified++;
        } else {
          expKept.add(e);
        }
      }
    }

    // ── Certifications: build the FINAL list before touching experience ─
    final certKey = '${resumeId}_${SectionTypeEnum.certifications.name}';
    final certSection = box.get(certKey);
    List<dynamic> certEntries = [];
    if (certSection != null) {
      try {
        certEntries = jsonDecode(certSection.data) as List<dynamic>;
      } catch (_) {
        certEntries = [];
      }
    }

    if (promotedFromExperience.isNotEmpty) {
      certEntries = ResumeSanitizer.deduplicateCertifications(
          [...certEntries, ...promotedFromExperience]);
    }

    // Flag (never delete) likely-compliance-training certs so the user
    // resolves them via a pending-decision card the next time they open
    // this resume's Certifications section. Already-flagged entries are
    // left alone so re-running the migration doesn't reset a decision that
    // hasn't been made yet, and doesn't touch certs the user already
    // resolved (resolving clears the flag — see ResumeEditorScreen).
    final flaggedEntries = certEntries.map((raw) {
      final c = Map<String, dynamic>.from(raw as Map<String, dynamic>);
      if (c['needsComplianceReview'] != true) {
        final name = (c['name'] as String? ?? '').toLowerCase();
        final isLikelyCompliance = ResumeSanitizer.fallbackComplianceCertPatterns
            .any((p) => name.contains(p));
        if (isLikelyCompliance) {
          c['needsComplianceReview'] = true;
          c['complianceReviewReason'] = 'This looks like it might be routine '
              'compliance or administrative training rather than a '
              'standalone credential — flagged during a data-quality update. '
              'It was NOT removed automatically.';
          certsFlagged++;
        }
      }
      return c;
    }).toList();

    if (promotedFromExperience.isNotEmpty || certsFlagged > 0) {
      changed = true;
      if (certSection != null) {
        certSection.data = jsonEncode(flaggedEntries);
        await certSection.save();
      } else if (flaggedEntries.isNotEmpty) {
        await box.put(
          certKey,
          ResumeSection(
            id: _uuid.v4(),
            resumeId: resumeId,
            type: SectionTypeEnum.certifications,
            data: jsonEncode(flaggedEntries),
            hasUnreviewedAIContent: false,
          ),
        );
      }
    }

    // ── Experience: NOW dedup against the final certifications list ────
    if (expSection != null && expKept.isNotEmpty) {
      // Discard bare-stub duplicates when a fuller entry with the same
      // title exists.
      final afterBareDedup = ResumeSanitizer.discardBareDuplicateExperience(expKept);
      deduped += expKept.length - afterBareDedup.length;

      // Merge substantive entries that confidently describe the same
      // real-world role recorded twice (same fuzzy-matched company + title
      // + genuine date-range overlap) — the case discardBareDuplicateExperience
      // deliberately leaves alone (see its own doc comment).
      final afterCrossDocMerge =
          ResumeSanitizer.mergeCrossDocumentDuplicateRoles(afterBareDedup);
      crossDocMerged += afterBareDedup.length - afterCrossDocMerge.length;

      // Drop entries that duplicate an event already correctly classified
      // as a certification above (same title, cert date within range).
      final afterCrossRef = ResumeSanitizer.dropExperienceMatchingCertification(
          afterCrossDocMerge, flaggedEntries);
      crossReferenceDropped += afterCrossDocMerge.length - afterCrossRef.length;

      // Cap bullets on whatever survived dedup.
      final afterCap = afterCrossRef.map((raw) {
        final e = Map<String, dynamic>.from(raw as Map<String, dynamic>);
        final bullets = (e['bullets'] as List<dynamic>?)
                ?.map((b) => b.toString())
                .toList() ??
            [];
        final capped = ResumeSanitizer.capBullets(bullets);
        if (capped.length < bullets.length) bulletCapped++;
        e['bullets'] = capped;
        return e;
      }).toList();

      if (reclassified > 0 ||
          deduped > 0 ||
          crossDocMerged > 0 ||
          crossReferenceDropped > 0 ||
          bulletCapped > 0) {
        changed = true;
        expSection.data = jsonEncode(afterCap);
        await expSection.save();
      }
    }

    // ── Education: completion-aware dedup ───────────────────────────────
    final eduKey = '${resumeId}_${SectionTypeEnum.education.name}';
    final eduSection = box.get(eduKey);
    if (eduSection != null) {
      List<dynamic> eduEntries;
      try {
        eduEntries = jsonDecode(eduSection.data) as List<dynamic>;
      } catch (_) {
        eduEntries = [];
      }
      if (eduEntries.isNotEmpty) {
        final dedupedEducation = ResumeSanitizer.deduplicateEducation(eduEntries);
        if (dedupedEducation.length < eduEntries.length) {
          educationDeduped += eduEntries.length - dedupedEducation.length;
          changed = true;
          eduSection.data = jsonEncode(dedupedEducation);
          await eduSection.save();
        }
      }
    }

    return _ResumeSanitizeResult(
      changed: changed,
      reclassified: reclassified,
      deduped: deduped + crossDocMerged + crossReferenceDropped,
      bulletCapped: bulletCapped,
      certsFlagged: certsFlagged,
      educationDeduped: educationDeduped,
    );
  }
}

class _ResumeSanitizeResult {
  const _ResumeSanitizeResult({
    required this.changed,
    required this.reclassified,
    required this.deduped,
    required this.bulletCapped,
    required this.certsFlagged,
    required this.educationDeduped,
  });

  final bool changed;
  final int reclassified;
  final int deduped;
  final int bulletCapped;
  final int certsFlagged;
  final int educationDeduped;
}
