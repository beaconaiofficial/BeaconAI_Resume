import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/resume_sections.dart';
import '../../constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../utils/wizard_validator.dart';
import 'wizard_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 — Contact Info
// ─────────────────────────────────────────────────────────────────────────────

class WizardStepContact extends StatefulWidget {
  const WizardStepContact({
    super.key,
    required this.data,
    required this.isUploadPath,
    required this.formKey,
    required this.onChanged,
  });

  final ContactInfo data;
  final bool isUploadPath;
  final GlobalKey<FormState> formKey;
  final ValueChanged<ContactInfo> onChanged;

  @override
  State<WizardStepContact> createState() => _WizardStepContactState();
}

class _WizardStepContactState extends State<WizardStepContact> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _stateCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _linkedInCtrl;
  late final TextEditingController _websiteCtrl;
  late final TextEditingController _githubCtrl;

  // Focus nodes for keyboard navigation
  final _lastNameFocus = FocusNode();
  final _titleFocus = FocusNode();
  final _cityFocus = FocusNode();
  final _stateFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _linkedInFocus = FocusNode();
  final _websiteFocus = FocusNode();
  final _githubFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _firstNameCtrl = TextEditingController(text: d.firstName);
    _lastNameCtrl = TextEditingController(text: d.lastName);
    _titleCtrl = TextEditingController(text: d.professionalTitle);
    _cityCtrl = TextEditingController(text: d.city);
    _stateCtrl = TextEditingController(text: d.state);
    _phoneCtrl = TextEditingController(text: d.phone);
    _emailCtrl = TextEditingController(text: d.email);
    _linkedInCtrl = TextEditingController(text: d.linkedInUrl ?? '');
    _websiteCtrl = TextEditingController(text: d.websiteUrl ?? '');
    _githubCtrl = TextEditingController(text: d.gitHubUrl ?? '');

    // Keep parent state in sync on every keystroke
    for (final ctrl in [
      _firstNameCtrl,
      _lastNameCtrl,
      _titleCtrl,
      _cityCtrl,
      _stateCtrl,
      _phoneCtrl,
      _emailCtrl,
      _linkedInCtrl,
      _websiteCtrl,
      _githubCtrl,
    ]) {
      ctrl.addListener(_notifyParent);
    }
  }

  @override
  void dispose() {
    for (final ctrl in [
      _firstNameCtrl,
      _lastNameCtrl,
      _titleCtrl,
      _cityCtrl,
      _stateCtrl,
      _phoneCtrl,
      _emailCtrl,
      _linkedInCtrl,
      _websiteCtrl,
      _githubCtrl,
    ]) {
      ctrl.dispose();
    }
    for (final node in [
      _lastNameFocus,
      _titleFocus,
      _cityFocus,
      _stateFocus,
      _phoneFocus,
      _emailFocus,
      _linkedInFocus,
      _websiteFocus,
      _githubFocus,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  void _notifyParent() {
    widget.onChanged(ContactInfo(
      firstName: _firstNameCtrl.text,
      lastName: _lastNameCtrl.text,
      professionalTitle: _titleCtrl.text,
      city: _cityCtrl.text,
      state: _stateCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
      linkedInUrl: _linkedInCtrl.text.isEmpty ? null : _linkedInCtrl.text,
      websiteUrl: _websiteCtrl.text.isEmpty ? null : _websiteCtrl.text,
      gitHubUrl: _githubCtrl.text.isEmpty ? null : _githubCtrl.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isAI = widget.isUploadPath;

    return Form(
      key: widget.formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          // Tip (scratch path only)
          if (!widget.isUploadPath)
            const SectionTipCard(
              tip: 'Use your full legal name. City and State are enough — '
                  'no street address on a resume.',
            ),

          // Name row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: WizardTextField(
                  label: 'First Name *',
                  hint: 'Jane',
                  controller: _firstNameCtrl,
                  validator: WizardValidator.validateName,
                  isAIPrefilled: isAI && widget.data.firstName.isNotEmpty,
                  autofillHints: const [AutofillHints.givenName],
                  nextFocusNode: _lastNameFocus,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: WizardTextField(
                  label: 'Last Name *',
                  hint: 'Smith',
                  controller: _lastNameCtrl,
                  validator: WizardValidator.validateName,
                  isAIPrefilled: isAI && widget.data.lastName.isNotEmpty,
                  focusNode: _lastNameFocus,
                  nextFocusNode: _titleFocus,
                  autofillHints: const [AutofillHints.familyName],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          WizardTextField(
            label: 'Professional Title',
            hint: 'e.g. Senior Software Engineer',
            controller: _titleCtrl,
            validator: WizardValidator.validateProfessionalTitle,
            isAIPrefilled: isAI && widget.data.professionalTitle.isNotEmpty,
            focusNode: _titleFocus,
            nextFocusNode: _cityFocus,
            maxLength: AppConstants.maxLengthProfessionalTitle,
          ),
          const SizedBox(height: 18),

          // City / State row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: WizardTextField(
                  label: 'City',
                  hint: 'Austin',
                  controller: _cityCtrl,
                  validator: WizardValidator.validateCityState,
                  isAIPrefilled: isAI && widget.data.city.isNotEmpty,
                  focusNode: _cityFocus,
                  nextFocusNode: _stateFocus,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: WizardTextField(
                  label: 'State',
                  hint: 'TX',
                  controller: _stateCtrl,
                  validator: WizardValidator.validateCityState,
                  isAIPrefilled: isAI && widget.data.state.isNotEmpty,
                  focusNode: _stateFocus,
                  nextFocusNode: _phoneFocus,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Shown on your resume as "City, State".',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),

          WizardTextField(
            label: 'Phone',
            hint: '+1 512 555 0100',
            controller: _phoneCtrl,
            validator: WizardValidator.validatePhone,
            keyboardType: TextInputType.phone,
            isAIPrefilled: isAI && widget.data.phone.isNotEmpty,
            focusNode: _phoneFocus,
            nextFocusNode: _emailFocus,
            autofillHints: const [AutofillHints.telephoneNumber],
          ),
          const SizedBox(height: 18),

          WizardTextField(
            label: 'Email',
            hint: 'jane.smith@email.com',
            controller: _emailCtrl,
            validator: WizardValidator.validateEmail,
            keyboardType: TextInputType.emailAddress,
            isAIPrefilled: isAI && widget.data.email.isNotEmpty,
            focusNode: _emailFocus,
            nextFocusNode: _linkedInFocus,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 24),

          const _SectionDivider(label: 'Online Presence (optional)'),
          const SizedBox(height: 18),

          WizardTextField(
            label: 'LinkedIn URL',
            hint: 'https://linkedin.com/in/yourname',
            controller: _linkedInCtrl,
            validator: WizardValidator.validateUrl,
            keyboardType: TextInputType.url,
            isAIPrefilled:
                isAI && (widget.data.linkedInUrl?.isNotEmpty ?? false),
            focusNode: _linkedInFocus,
            nextFocusNode: _websiteFocus,
          ),
          const SizedBox(height: 18),

          WizardTextField(
            label: 'Website / Portfolio',
            hint: 'https://yoursite.com',
            controller: _websiteCtrl,
            validator: WizardValidator.validateUrl,
            keyboardType: TextInputType.url,
            isAIPrefilled:
                isAI && (widget.data.websiteUrl?.isNotEmpty ?? false),
            focusNode: _websiteFocus,
            nextFocusNode: _githubFocus,
          ),
          const SizedBox(height: 18),

          WizardTextField(
            label: 'GitHub URL',
            hint: 'https://github.com/yourname',
            controller: _githubCtrl,
            validator: WizardValidator.validateUrl,
            keyboardType: TextInputType.url,
            isAIPrefilled: isAI && (widget.data.gitHubUrl?.isNotEmpty ?? false),
            focusNode: _githubFocus,
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 — Professional Summary
// ─────────────────────────────────────────────────────────────────────────────

class WizardStepSummary extends StatefulWidget {
  const WizardStepSummary({
    super.key,
    required this.initialText,
    required this.isAIPrefilled,
    required this.formKey,
    required this.onChanged,
    required this.onAIEdited,
  });

  final String initialText;
  final bool isAIPrefilled;
  final GlobalKey<FormState> formKey;
  final ValueChanged<String> onChanged;
  final VoidCallback onAIEdited;

  @override
  State<WizardStepSummary> createState() => _WizardStepSummaryState();
}

class _WizardStepSummaryState extends State<WizardStepSummary> {
  late final TextEditingController _ctrl;
  late bool _showAiBadge;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _showAiBadge = widget.isAIPrefilled;
    _ctrl.addListener(() {
      widget.onChanged(_ctrl.text);
      if (_showAiBadge) {
        setState(() => _showAiBadge = false);
        widget.onAIEdited();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final charCount = _ctrl.text.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Form(
      key: widget.formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          const SectionTipCard(
            tip: 'Think of this as your elevator pitch. '
                '3–4 sentences: how many years of experience you have, '
                'your top skills, one key accomplishment, and what you bring to the role.',
          ),

          // Label + AI badge
          Row(
            children: [
              Expanded(
                child: Text(
                  'Professional Summary',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (_showAiBadge) const AiBadge(),
            ],
          ),
          const SizedBox(height: 6),

          // Summary text area
          TextFormField(
            controller: _ctrl,
            maxLines: 8,
            maxLength: AppConstants.maxLengthSummary,
            buildCounter: (_,
                    {required currentLength, required isFocused, maxLength}) =>
                null, // we render our own counter below
            decoration: InputDecoration(
              hintText:
                  'e.g. Results-driven software engineer with 6 years of experience '
                  'building scalable web applications…',
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
            validator: WizardValidator.validateSummary,
          ),
          const SizedBox(height: 6),

          // Character counter with target range feedback
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Range guidance
              _CharRangeHint(
                current: charCount,
                min: AppConstants.summaryTargetMinChars,
                max: AppConstants.summaryTargetMaxChars,
                isDark: isDark,
              ),
              // Count
              Text(
                '$charCount / ${AppConstants.maxLengthSummary}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child:
                Divider(color: Theme.of(context).colorScheme.outlineVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
            child:
                Divider(color: Theme.of(context).colorScheme.outlineVariant)),
      ],
    );
  }
}

class _CharRangeHint extends StatelessWidget {
  const _CharRangeHint({
    required this.current,
    required this.min,
    required this.max,
    required this.isDark,
  });

  final int current;
  final int min;
  final int max;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final inRange = current >= min && current <= max;
    final color = inRange
        ? (isDark ? AppColors.successDark : AppColors.successLight)
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (inRange) Icon(Icons.check_circle_outline, size: 12, color: color),
        if (!inRange)
          Icon(Icons.radio_button_unchecked, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          'Target: $min–$max characters',
          style: GoogleFonts.inter(fontSize: 11, color: color),
        ),
      ],
    );
  }
}
