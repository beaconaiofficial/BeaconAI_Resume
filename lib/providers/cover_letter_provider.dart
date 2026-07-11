import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/supporting_models.dart';
import '../services/hive_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CoverLetterListNotifier
// Watches the Hive box and exposes a sorted list of cover letters. Mirrors
// ResumeListNotifier's reactivity pattern (resume_provider.dart) so Home and
// My Documents pick up a newly-saved cover letter immediately, without an
// app restart, the same way they already do for resumes.
// ─────────────────────────────────────────────────────────────────────────────

class CoverLetterListNotifier extends Notifier<List<CoverLetter>> {
  late Box<CoverLetter> _box;

  @override
  List<CoverLetter> build() {
    _box = HiveService.coverLetterBox;

    final listenable = _box.listenable();
    listenable.addListener(_onBoxChanged);
    ref.onDispose(() => listenable.removeListener(_onBoxChanged));

    return _sorted(_box.values.toList());
  }

  void _onBoxChanged() {
    state = _sorted(_box.values.toList());
  }

  static List<CoverLetter> _sorted(List<CoverLetter> letters) {
    letters.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return letters;
  }
}

final coverLetterListProvider =
    NotifierProvider<CoverLetterListNotifier, List<CoverLetter>>(
  CoverLetterListNotifier.new,
);
