import 'package:flutter/material.dart';

import '../models/supporting_models.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PendingDecisionCard
//
// Surfaced anywhere the app has an entry it could not confidently classify
// as employment vs. training, or as a real credential vs. compliance
// clutter — the document-upload / wizard Path A confirmation screen at
// extraction time, and the resume editor's Certifications section for
// entries the retroactive sanitization migration flagged in already-stored
// data. Deliberately distinct from an accept/edit row: this needs an
// explicit choice, so it uses the app's warning color (a softer "needs your
// input" cue) rather than accent or error — an unresolved decision isn't a
// validation failure. Shared here (rather than duplicated per screen) so
// every surface that asks the user to resolve one of these looks and
// behaves identically.
// ─────────────────────────────────────────────────────────────────────────────

class PendingDecisionCard extends StatelessWidget {
  const PendingDecisionCard({
    super.key,
    required this.decision,
    required this.isDark,
    required this.onResolve,
  });

  final PendingEntryDecision decision;
  final bool isDark;
  final ValueChanged<EntryDecision> onResolve;

  @override
  Widget build(BuildContext context) {
    final warningColor =
        isDark ? AppColors.warningDark : AppColors.warningLight;
    final textTheme = Theme.of(context).textTheme;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    final firstBullet =
        decision.rawBullets.isNotEmpty ? decision.rawBullets.first : null;
    final subtitle = decision.rawCompany.isNotEmpty
        ? '${decision.rawTitle} · ${decision.rawCompany}'
        : decision.rawTitle;

    return Semantics(
      container: true,
      label: 'Needs your input: $subtitle. ${decision.uncertaintyReason}',
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: warningColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: warningColor.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: warningColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subtitle.isNotEmpty ? subtitle : 'Untitled entry',
                        style: textTheme.titleMedium?.copyWith(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (firstBullet != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          firstBullet,
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                            color: onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        decision.uncertaintyReason,
                        style: textTheme.bodyMedium?.copyWith(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: warningColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (decision.kind == PendingDecisionKind.employmentVsTraining)
                  OutlinedButton(
                    onPressed: () => onResolve(EntryDecision.employment),
                    child:
                        Text('Work Experience', style: textTheme.labelLarge),
                  ),
                if (decision.kind ==
                    PendingDecisionKind.degreeVsNonDegreeTraining)
                  OutlinedButton(
                    onPressed: () => onResolve(EntryDecision.education),
                    child: Text('Add as Education', style: textTheme.labelLarge),
                  ),
                OutlinedButton(
                  onPressed: () => onResolve(EntryDecision.certification),
                  child: Text(
                    switch (decision.kind) {
                      PendingDecisionKind.employmentVsTraining => 'Certification',
                      PendingDecisionKind.degreeVsNonDegreeTraining =>
                        'Add as Certification',
                      PendingDecisionKind.credentialVsCompliance =>
                        'Keep as Certification',
                    },
                    style: textTheme.labelLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => onResolve(EntryDecision.exclude),
                  child: Text('Don\'t include', style: textTheme.labelLarge),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
