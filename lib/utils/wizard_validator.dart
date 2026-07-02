import '../constants/app_constants.dart';

/// WizardValidator — enforces all input validation rules from
/// BeaconAI_Resume_Instructions.md §8.
///
/// Rule: validate on save tap. Never silently strip characters.
/// Show red border + inline message. Save blocked until resolved.
/// Red clears in real time as user corrects.
class WizardValidator {
  WizardValidator._();

  // ── Contact Fields (Strict) ───────────────────────────────────────────────

  /// First name / Last name — letters, hyphens, apostrophes, spaces. Max 50.
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    if (value.length > AppConstants.maxLengthName) {
      return 'Must be ${AppConstants.maxLengthName} characters or fewer.';
    }
    if (!AppConstants.namePattern.hasMatch(value)) {
      return 'Only letters, hyphens, apostrophes, and spaces allowed.';
    }
    if (AppConstants.contactBlockedPattern.hasMatch(value)) {
      return 'Contains an invalid character.';
    }
    return null;
  }

  /// Professional title — max 100 chars, blocked chars apply.
  static String? validateProfessionalTitle(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    if (value.length > AppConstants.maxLengthProfessionalTitle) {
      return 'Must be ${AppConstants.maxLengthProfessionalTitle} characters or fewer.';
    }
    if (AppConstants.contactBlockedPattern.hasMatch(value)) {
      return 'Contains an invalid character (e.g. ", /, \\, ;).';
    }
    return null;
  }

  /// City / State — letters, hyphens, spaces, periods, commas. Max 60.
  static String? validateCityState(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    if (value.length > AppConstants.maxLengthCity) {
      return 'Must be ${AppConstants.maxLengthCity} characters or fewer.';
    }
    if (!AppConstants.cityStatePattern.hasMatch(value)) {
      return 'Only letters, hyphens, spaces, periods, and commas allowed.';
    }
    return null;
  }

  /// Phone — digits, spaces, hyphens, + only. Max 20.
  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    if (value.length > AppConstants.maxLengthPhone) {
      return 'Must be ${AppConstants.maxLengthPhone} characters or fewer.';
    }
    if (!AppConstants.phonePattern.hasMatch(value)) {
      return 'Only digits, spaces, hyphens, and + allowed.';
    }
    return null;
  }

  /// Email — standard format.
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    if (!AppConstants.emailPattern.hasMatch(value.trim())) {
      return 'Enter a valid email address (e.g. you@example.com).';
    }
    return null;
  }

  /// URL — must start with http:// or https://. Max 200.
  static String? validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    if (value.length > AppConstants.maxLengthUrl) {
      return 'Must be ${AppConstants.maxLengthUrl} characters or fewer.';
    }
    if (!AppConstants.urlPattern.hasMatch(value.trim())) {
      return 'Must start with https:// or http://.';
    }
    return null;
  }

  // ── Content Fields (Light) ────────────────────────────────────────────────

  /// Professional summary — max 1500, blocked: < > ; `
  static String? validateSummary(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.length > AppConstants.maxLengthSummary) {
      return 'Must be ${AppConstants.maxLengthSummary} characters or fewer.';
    }
    if (AppConstants.contentBlockedPattern.hasMatch(value)) {
      return 'Contains an invalid character (< > ; or backtick).';
    }
    return null;
  }

  /// Job title — max 100, blocked: < > ; `
  static String? validateJobTitle(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.length > AppConstants.maxLengthJobTitle) {
      return 'Must be ${AppConstants.maxLengthJobTitle} characters or fewer.';
    }
    if (AppConstants.contentBlockedPattern.hasMatch(value)) {
      return 'Contains an invalid character.';
    }
    return null;
  }

  /// Company name — max 100, blocked: < > ; `
  static String? validateCompany(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.length > AppConstants.maxLengthCompany) {
      return 'Must be ${AppConstants.maxLengthCompany} characters or fewer.';
    }
    if (AppConstants.contentBlockedPattern.hasMatch(value)) {
      return 'Contains an invalid character.';
    }
    return null;
  }

  /// Experience bullet — max 300, blocked: < > ; `
  static String? validateBullet(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.length > AppConstants.maxLengthExperienceBullet) {
      return 'Must be ${AppConstants.maxLengthExperienceBullet} characters or fewer.';
    }
    if (AppConstants.contentBlockedPattern.hasMatch(value)) {
      return 'Contains an invalid character.';
    }
    return null;
  }

  /// Skill tag — max 60, blocked: < > ; `
  static String? validateSkill(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Skill name cannot be empty.';
    }
    if (value.length > AppConstants.maxLengthSkillTag) {
      return 'Must be ${AppConstants.maxLengthSkillTag} characters or fewer.';
    }
    if (AppConstants.contentBlockedPattern.hasMatch(value)) {
      return 'Contains an invalid character.';
    }
    return null;
  }

  /// Certification name — max 150, blocked: < > ; `
  static String? validateCertName(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.length > AppConstants.maxLengthCertName) {
      return 'Must be ${AppConstants.maxLengthCertName} characters or fewer.';
    }
    if (AppConstants.contentBlockedPattern.hasMatch(value)) {
      return 'Contains an invalid character.';
    }
    return null;
  }

  /// Generic content field — light rules only.
  static String? validateContentField(String? value, {int maxLength = 300}) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.length > maxLength) {
      return 'Must be $maxLength characters or fewer.';
    }
    if (AppConstants.contentBlockedPattern.hasMatch(value)) {
      return 'Contains an invalid character.';
    }
    return null;
  }
}
