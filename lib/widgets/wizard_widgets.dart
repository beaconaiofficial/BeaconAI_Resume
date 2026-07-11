import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WizardProgressBar
// Always visible at the top of every wizard step.
// ─────────────────────────────────────────────────────────────────────────────

class WizardProgressBar extends StatelessWidget {
  const WizardProgressBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final track = Theme.of(context).colorScheme.outlineVariant;
    final progress = currentStep / totalSteps;

    return Semantics(
      label: 'Step $currentStep of $totalSteps',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Step $currentStep of $totalSteps',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${((progress) * 100).round()}%',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: track,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AiBadge
// Purple indicator shown on fields prefilled by Claude.
// Rule §4 & §14: ONLY used for AI-prefilled content. Clears on edit.
// ─────────────────────────────────────────────────────────────────────────────

class AiBadge extends StatelessWidget {
  const AiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.aiIndicatorDark : AppColors.aiIndicator;

    return Semantics(
      label: 'AI suggested content — tap to edit',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 10, color: color),
            const SizedBox(width: 3),
            Text(
              'AI',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WizardTextField
// Validated text field with: AI badge support, character counter,
// real-time error clearing, and proper Semantics.
// ─────────────────────────────────────────────────────────────────────────────

class WizardTextField extends StatefulWidget {
  const WizardTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.validator,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.showCounter = false,
    this.targetMin,
    this.targetMax,
    this.isAIPrefilled = false,
    this.onAIContentEdited,
    this.autofillHints,
    this.textInputAction,
    this.focusNode,
    this.nextFocusNode,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final bool showCounter;
  final int? targetMin;
  final int? targetMax;
  final bool isAIPrefilled;

  /// Called the first time the user edits an AI-prefilled field.
  /// Parent uses this to clear isAIPrefilled and update hasUnreviewedAIContent.
  final VoidCallback? onAIContentEdited;

  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;

  @override
  State<WizardTextField> createState() => _WizardTextFieldState();
}

class _WizardTextFieldState extends State<WizardTextField> {
  String? _errorText;
  bool _hasBeenEdited = false;
  late bool _showAiBadge;

  @override
  void initState() {
    super.initState();
    _showAiBadge = widget.isAIPrefilled;
  }

  void _onChanged(String value) {
    // Clear error in real time as user corrects (spec §8)
    if (_errorText != null) {
      if (widget.validator == null || widget.validator!(value) == null) {
        setState(() => _errorText = null);
      }
    }

    // Clear AI badge on first edit (Rule §4)
    if (_showAiBadge && !_hasBeenEdited) {
      setState(() {
        _showAiBadge = false;
        _hasBeenEdited = true;
      });
      widget.onAIContentEdited?.call();
    }

    widget.onChanged?.call(value);
  }

  /// Called by parent Form on save attempt.
  String? validate(String? value) {
    final error = widget.validator?.call(value);
    setState(() => _errorText = error);
    return error;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final charCount = widget.controller?.text.length ?? 0;
    final hasTarget = widget.targetMin != null && widget.targetMax != null;

    // Counter color logic
    Color counterColor = Theme.of(context).colorScheme.onSurfaceVariant;
    if (hasTarget &&
        charCount >= widget.targetMin! &&
        charCount <= widget.targetMax!) {
      counterColor = isDark ? AppColors.successDark : AppColors.successLight;
    } else if (widget.maxLength != null &&
        charCount > widget.maxLength! * 0.9) {
      counterColor = isDark ? AppColors.warningDark : AppColors.warningLight;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label row with optional AI badge
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (_showAiBadge) ...[
              const SizedBox(width: 8),
              const AiBadge(),
            ],
          ],
        ),
        const SizedBox(height: 6),

        // Text field
        Semantics(
          label: widget.label,
          hint: widget.hint,
          child: TextFormField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            keyboardType: widget.keyboardType,
            maxLines: widget.maxLines,
            maxLength: widget.maxLength,
            buildCounter: widget.maxLength != null && !widget.showCounter
                ? (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null
                : null,
            textInputAction: widget.textInputAction ??
                (widget.maxLines == 1
                    ? TextInputAction.next
                    : TextInputAction.newline),
            autofillHints: widget.autofillHints,
            onFieldSubmitted: widget.nextFocusNode != null
                ? (_) =>
                    FocusScope.of(context).requestFocus(widget.nextFocusNode)
                : null,
            decoration: InputDecoration(
              hintText: widget.hint,
              errorText: _errorText,
              // Override border color when AI prefilled
              enabledBorder: _showAiBadge
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: (isDark
                                ? AppColors.aiIndicatorDark
                                : AppColors.aiIndicator)
                            .withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    )
                  : null,
            ),
            validator: validate,
            onChanged: _onChanged,
          ),
        ),

        // Character counter / target hint
        if (widget.showCounter || hasTarget) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (hasTarget && charCount < widget.targetMin!)
                Expanded(
                  child: Text(
                    'Aim for ${widget.targetMin}–${widget.targetMax} characters',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Text(
                widget.maxLength != null
                    ? '$charCount / ${widget.maxLength}'
                    : '$charCount',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: counterColor,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SectionTipCard
// Inline contextual tip shown in scratch path for each section.
// ─────────────────────────────────────────────────────────────────────────────

class SectionTipCard extends StatefulWidget {
  const SectionTipCard({
    super.key,
    required this.tip,
    this.icon = Icons.lightbulb_outline,
  });

  final String tip;
  final IconData icon;

  @override
  State<SectionTipCard> createState() => _SectionTipCardState();
}

class _SectionTipCardState extends State<SectionTipCard> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.accentDark : AppColors.accentLightColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color:
            isDark ? AppColors.accentLightTintDark : AppColors.accentLightTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.icon, size: 16, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.tip,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            tooltip: 'Dismiss tip',
            onPressed: () => setState(() => _dismissed = true),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WizardNavBar
// Bottom nav consistent across all steps: Back / Save & Exit / Next (or Finish)
// ─────────────────────────────────────────────────────────────────────────────

class WizardNavBar extends StatelessWidget {
  const WizardNavBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.onBack,
    required this.onNext,
    required this.onSaveExit,
    this.nextLabel,
    this.isNextLoading = false,
  });

  final int currentStep;
  final int totalSteps;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSaveExit;
  final String? nextLabel;
  final bool isNextLoading;

  bool get _isFirstStep => currentStep == 1;
  bool get _isLastStep => currentStep == totalSteps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        // Base 24 preserves the existing look on devices with no reserved
        // bottom inset; the device's own inset (3-button nav bar, gesture
        // home indicator, etc.) is added on top so buttons never render
        // underneath the system navigation area.
        24 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          // Back — only takes up space when it's actually shown. Step 1 has
          // no prior step, so nothing reserves its place: an invisible
          // fixed-width placeholder here was stealing width the two Save
          // buttons needed, forcing them into much more aggressive ellipsis
          // than the flex ratios alone would predict. A few pixels of
          // horizontal shift between "no Back" and "Back present" steps is
          // a fair trade for a legible primary action.
          if (!_isFirstStep)
            OutlinedButton(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Back'),
            ),

          // Save & Exit + Save & Continue/Finish, grouped in their own
          // Expanded rather than separated by a Spacer(). A Spacer is
          // itself a flex participant (Expanded, flex: 1) — sharing a Row
          // with the Flexible buttons below meant it competed for the same
          // constrained width budget under space pressure, taking a full
          // quarter of it for literally nothing rendered. Expanded here
          // hands the *entire* remaining width (after Back's natural size)
          // to this group, with `end` alignment reproducing the original
          // "pushed to the right" look whenever there's slack to spare.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Flexible (not a bare TextButton/ElevatedButton) so the
                // Row can shrink these at large text-scale factors or on
                // narrow screens instead of overflowing horizontally. Save
                // & Exit yields space first (flex: 1 vs. 3) since Save &
                // Continue/Finish is the primary action and should stay
                // legible longer.
                //
                // FittedBox(scaleDown) is the primary defense against a
                // label not fitting: it shrinks the whole label to fit
                // available width rather than cutting it off, so "Save &
                // Continue" stays complete (just smaller) instead of
                // becoming "Save & ...". The Text's own overflow: ellipsis
                // is only a last-resort backstop for a pathological case
                // FittedBox itself can't satisfy — in practice unreachable,
                // since FittedBox always finds a scale that fits.
                //
                // Tighter padding (vs. Material's ~24dp/side default)
                // reclaims width for the label itself before FittedBox
                // ever needs to shrink anything. Even so, "Back" + "Save &
                // Exit" + "Save & Continue" together are more text than
                // reliably fits at full natural size on every phone width
                // at once — some shrink is an inherent consequence of the
                // current button copy, not a layout bug. See the widget
                // test file for the measured range across widths/scales.
                Flexible(
                  child: TextButton(
                    onPressed: onSaveExit,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Save & Exit',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Next / Finish
                Flexible(
                  flex: 3,
                  child: ElevatedButton(
                    onPressed: isNextLoading ? null : onNext,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: isNextLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _isLastStep
                                  ? (nextLabel ?? 'Finish')
                                  : (nextLabel ?? 'Save & Continue'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Month / Year picker — shared constants & helpers
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _kPickerMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const int _kPickerFirstYear = 1970;

(int month, int year)? _parseMonthYear(String text) {
  final parts = text.trim().split(' ');
  if (parts.length != 2) return null;
  final mi = _kPickerMonths.indexOf(parts[0]);
  final y = int.tryParse(parts[1]);
  if (mi < 0 || y == null) return null;
  return (mi + 1, y);
}

String _formatMonthYear(int month, int year) =>
    '${_kPickerMonths[month - 1]} $year';

// ─────────────────────────────────────────────────────────────────────────────
// MonthYearPickerField
// Tappable read-only field. Opens a bottom sheet with month grid + year wheel.
// showPresentToggle adds a "Currently here" switch (for experience end dates).
// ─────────────────────────────────────────────────────────────────────────────

class MonthYearPickerField extends StatelessWidget {
  const MonthYearPickerField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.showPresentToggle = false,
    this.isPresent = false,
    this.onPresentChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool showPresentToggle;
  final bool isPresent;
  final ValueChanged<bool>? onPresentChanged;

  void _openSheet(BuildContext context) {
    final parsed = _parseMonthYear(controller.text);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MonthYearPickerSheet(
        initialMonth: parsed?.$1,
        initialYear: parsed?.$2,
        initialIsPresent: isPresent,
        showPresentToggle: showPresentToggle,
        onDone: (month, year, present) {
          if (present) {
            onPresentChanged?.call(true);
          } else if (month != null && year != null) {
            controller.text = _formatMonthYear(month, year);
            if (showPresentToggle) onPresentChanged?.call(false);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final accent = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final showPresent = isPresent && showPresentToggle;
            final displayText = showPresent ? 'Present' : value.text;
            final hasValue = showPresent || value.text.isNotEmpty;

            return Semantics(
              label: '$label: ${hasValue ? displayText : 'not set'}',
              hint: 'Double tap to open date picker',
              button: true,
              child: GestureDetector(
                onTap: () => _openSheet(context),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.backgroundDark
                        : AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          hasValue ? displayText : (hint ?? ''),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: showPresent
                                ? accent
                                : hasValue
                                    ? Theme.of(context).colorScheme.onSurface
                                    : secondary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 18,
                        color: secondary,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MonthYearPickerSheet
// ─────────────────────────────────────────────────────────────────────────────

class _MonthYearPickerSheet extends StatefulWidget {
  const _MonthYearPickerSheet({
    required this.initialMonth,
    required this.initialYear,
    required this.initialIsPresent,
    required this.showPresentToggle,
    required this.onDone,
  });

  final int? initialMonth;
  final int? initialYear;
  final bool initialIsPresent;
  final bool showPresentToggle;
  final void Function(int? month, int? year, bool isPresent) onDone;

  @override
  State<_MonthYearPickerSheet> createState() => _MonthYearPickerSheetState();
}

class _MonthYearPickerSheetState extends State<_MonthYearPickerSheet> {
  late int? _month;
  late int _year;
  late bool _isPresent;
  late FixedExtentScrollController _yearScrollCtrl;
  late final int _yearCount;

  @override
  void initState() {
    super.initState();
    final lastYear = DateTime.now().year + 5;
    _yearCount = lastYear - _kPickerFirstYear + 1;
    _month = widget.initialMonth;
    _year = (widget.initialYear ?? DateTime.now().year)
        .clamp(_kPickerFirstYear, lastYear);
    _isPresent = widget.initialIsPresent;
    final idx = (_year - _kPickerFirstYear).clamp(0, _yearCount - 1);
    _yearScrollCtrl = FixedExtentScrollController(initialItem: idx);
  }

  @override
  void dispose() {
    _yearScrollCtrl.dispose();
    super.dispose();
  }

  void _done() {
    Navigator.pop(context);
    widget.onDone(_month, _year, _isPresent);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final outline = Theme.of(context).colorScheme.outlineVariant;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle ──────────────────────────────────────────────
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                'Select Month & Year',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 16),

              // ── Month grid (4 columns × 3 rows) ──────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  crossAxisCount: 4,
                  childAspectRatio: 2.0,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: List.generate(12, (i) {
                    final selected = _month == i + 1;
                    final dimmed = _isPresent;
                    return Semantics(
                      label: _kPickerMonths[i],
                      selected: selected,
                      button: true,
                      child: InkWell(
                        onTap: dimmed
                            ? null
                            : () => setState(() => _month = i + 1),
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected && !dimmed
                                ? accent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected && !dimmed
                                  ? accent
                                  : dimmed
                                      ? outline.withValues(alpha: 0.35)
                                      : outline,
                            ),
                          ),
                          child: Text(
                            _kPickerMonths[i],
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: selected && !dimmed
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected && !dimmed
                                  ? Colors.white
                                  : dimmed
                                      ? secondary.withValues(alpha: 0.35)
                                      : onSurface,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),

              // ── Year wheel ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Year',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 160,
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black,
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black,
                          ],
                          stops: [0.0, 0.2, 0.8, 1.0],
                        ).createShader(bounds),
                        blendMode: BlendMode.dstOut,
                        child: ListWheelScrollView.useDelegate(
                          controller: _yearScrollCtrl,
                          physics: _isPresent
                              ? const NeverScrollableScrollPhysics()
                              : const FixedExtentScrollPhysics(),
                          itemExtent: 40,
                          perspective: 0.003,
                          onSelectedItemChanged: (i) {
                            if (!_isPresent) {
                              setState(() => _year = _kPickerFirstYear + i);
                            }
                          },
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: _yearCount,
                            builder: (context, i) {
                              final y = _kPickerFirstYear + i;
                              final isSelected = _year == y;
                              return Center(
                                child: Text(
                                  '$y',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: isSelected ? 18 : 14,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: isSelected && !_isPresent
                                        ? accent
                                        : _isPresent
                                            ? secondary.withValues(alpha: 0.3)
                                            : secondary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Present toggle (end-date fields only) ─────────────────────
              if (widget.showPresentToggle) ...[
                Divider(height: 1, color: outline),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SwitchListTile.adaptive(
                    value: _isPresent,
                    onChanged: (v) => setState(() => _isPresent = v),
                    title: Text(
                      'Currently here',
                      style: GoogleFonts.inter(fontSize: 14, color: onSurface),
                    ),
                    activeThumbColor: accent,
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],

              // ── Cancel / Done ─────────────────────────────────────────────
              Divider(height: 1, color: outline),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _done,
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// YearPickerField
// Year-only picker used for Education graduation year.
// ─────────────────────────────────────────────────────────────────────────────

class YearPickerField extends StatelessWidget {
  const YearPickerField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;

  void _openSheet(BuildContext context) {
    final current = int.tryParse(controller.text.trim());
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _YearPickerSheet(
        initialYear: current,
        onDone: (year) {
          if (year != null) controller.text = '$year';
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final hasValue = value.text.isNotEmpty;
            return Semantics(
              label: '$label: ${hasValue ? value.text : 'not set'}',
              hint: 'Double tap to open year picker',
              button: true,
              child: GestureDetector(
                onTap: () => _openSheet(context),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.backgroundDark
                        : AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          hasValue ? value.text : (hint ?? ''),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: hasValue
                                ? Theme.of(context).colorScheme.onSurface
                                : secondary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 18,
                        color: secondary,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _YearPickerSheet
// ─────────────────────────────────────────────────────────────────────────────

class _YearPickerSheet extends StatefulWidget {
  const _YearPickerSheet({
    required this.initialYear,
    required this.onDone,
  });

  final int? initialYear;
  final ValueChanged<int?> onDone;

  @override
  State<_YearPickerSheet> createState() => _YearPickerSheetState();
}

class _YearPickerSheetState extends State<_YearPickerSheet> {
  late int _year;
  late FixedExtentScrollController _yearCtrl;
  late final int _yearCount;

  @override
  void initState() {
    super.initState();
    final lastYear = DateTime.now().year + 5;
    _yearCount = lastYear - _kPickerFirstYear + 1;
    _year = (widget.initialYear ?? DateTime.now().year)
        .clamp(_kPickerFirstYear, lastYear);
    final idx = (_year - _kPickerFirstYear).clamp(0, _yearCount - 1);
    _yearCtrl = FixedExtentScrollController(initialItem: idx);
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final outline = Theme.of(context).colorScheme.outlineVariant;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Select Year',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 220,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black,
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black,
                      ],
                      stops: [0.0, 0.25, 0.75, 1.0],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstOut,
                    child: ListWheelScrollView.useDelegate(
                      controller: _yearCtrl,
                      physics: const FixedExtentScrollPhysics(),
                      itemExtent: 44,
                      perspective: 0.003,
                      onSelectedItemChanged: (i) =>
                          setState(() => _year = _kPickerFirstYear + i),
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: _yearCount,
                        builder: (context, i) {
                          final y = _kPickerFirstYear + i;
                          final isSelected = _year == y;
                          return Center(
                            child: Text(
                              '$y',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: isSelected ? 22 : 16,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: isSelected ? accent : secondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Divider(height: 1, color: outline),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onDone(_year);
                        },
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
