import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/resume.dart';
import '../services/hive_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ResumeListNotifier
// Watches the Hive box and exposes a sorted list of resumes.
// ─────────────────────────────────────────────────────────────────────────────

class ResumeListNotifier extends Notifier<List<Resume>> {
  late Box<Resume> _box;

  @override
  List<Resume> build() {
    _box = HiveService.resumeBox;

    // Re-build state whenever Hive box changes
    final listenable = _box.listenable();
    listenable.addListener(_onBoxChanged);
    ref.onDispose(() => listenable.removeListener(_onBoxChanged));

    return _sorted(_box.values.toList());
  }

  void _onBoxChanged() {
    state = _sorted(_box.values.toList());
  }

  static List<Resume> _sorted(List<Resume> resumes) {
    resumes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return resumes;
  }

  // ── Convenience getters ─────────────────────────────────────────────────────

  /// The active (non-archived) master resume, or null if none exists yet.
  Resume? get activeMaster {
    try {
      return state.firstWhere((r) => r.isMaster && !r.isArchived);
    } catch (_) {
      return null;
    }
  }

  /// All non-archived tailored resumes, most recently edited first.
  List<Resume> get activeTailored =>
      state.where((r) => !r.isMaster && !r.isArchived).toList();

  /// All archived resumes (soft-reset masters + any archived tailored).
  List<Resume> get archived => state.where((r) => r.isArchived).toList();

  // ── Mutations ───────────────────────────────────────────────────────────────

  Future<void> archiveResume(String id) async {
    final resume = _box.get(id);
    if (resume != null) {
      resume.archive(); // sets isArchived = true, saves to Hive
      state = _sorted(_box.values.toList());
    }
  }

  Future<void> renameResume(String id, String newTitle) async {
    final resume = _box.get(id);
    if (resume != null) {
      resume.title = newTitle;
      resume.updatedAt = DateTime.now();
      await resume.save();
      state = _sorted(_box.values.toList());
    }
  }

  Future<void> deleteResume(String id) async {
    // Rule §2: we never hard-delete user data from inside the app.
    // This method archives instead of deletes.
    await archiveResume(id);
  }
}

final resumeListProvider = NotifierProvider<ResumeListNotifier, List<Resume>>(
  ResumeListNotifier.new,
);

/// Convenience: active master resume only.
final activeMasterResumeProvider = Provider<Resume?>((ref) {
  final notifier = ref.watch(resumeListProvider.notifier);
  ref.watch(resumeListProvider); // rebuild when list changes
  return notifier.activeMaster;
});

/// Convenience: active tailored resumes only.
final activeTailoredResumesProvider = Provider<List<Resume>>((ref) {
  final notifier = ref.watch(resumeListProvider.notifier);
  ref.watch(resumeListProvider);
  return notifier.activeTailored;
});

// ─────────────────────────────────────────────────────────────────────────────
// ATS Score Provider
// Computes a simple section-completeness ATS score (0–100) for a resume.
// Phase 1: completeness only. Phase 3: keyword density added.
// ─────────────────────────────────────────────────────────────────────────────

final atsScoreProvider = Provider.family<int, String>((ref, resumeId) {
  ref.watch(resumeListProvider); // rebuild when resumes change
  return _computeAtsScore(resumeId);
});

int _computeAtsScore(String resumeId) {
  final sectionBox = HiveService.resumeSectionBox;
  int score = 0;
  const perSection = 100 ~/ 6; // ~16 points per section

  for (final key in [
    '${resumeId}_contact',
    '${resumeId}_summary',
    '${resumeId}_experience',
    '${resumeId}_education',
    '${resumeId}_skills',
    '${resumeId}_certifications',
  ]) {
    final section = sectionBox.get(key);
    if (section != null && section.data.length > 10) {
      score += perSection;
    }
  }

  return score.clamp(0, 100);
}

// ─────────────────────────────────────────────────────────────────────────────
// Document filter/sort enums (used by My Documents)
// ─────────────────────────────────────────────────────────────────────────────

enum DocFilterType {
  all,
  masterResume,
  tailoredResume,
  coverLetter,
  studyGuide
}

enum DocSortOrder { newest, oldest, companyAZ }

extension DocFilterTypeX on DocFilterType {
  String get label {
    return switch (this) {
      DocFilterType.all => 'All',
      DocFilterType.masterResume => 'Master Resume',
      DocFilterType.tailoredResume => 'Tailored Resumes',
      DocFilterType.coverLetter => 'Cover Letters',
      DocFilterType.studyGuide => 'Study Guides',
    };
  }
}

extension DocSortOrderX on DocSortOrder {
  String get label {
    return switch (this) {
      DocSortOrder.newest => 'Newest first',
      DocSortOrder.oldest => 'Oldest first',
      DocSortOrder.companyAZ => 'Company A–Z',
    };
  }
}
