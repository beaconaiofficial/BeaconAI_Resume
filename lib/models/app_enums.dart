import 'package:hive_ce/hive.dart';
import '../constants/app_constants.dart';

part 'app_enums.g.dart';

// ── Tier ─────────────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.tierEnumTypeId)
enum TierEnum {
  @HiveField(0)
  free,

  @HiveField(1)
  basic,

  @HiveField(2)
  pro,
}

extension TierEnumX on TierEnum {
  bool get isFree => this == TierEnum.free;
  bool get isBasic => this == TierEnum.basic;
  bool get isPro => this == TierEnum.pro;
  bool get isPaid => this == TierEnum.basic || this == TierEnum.pro;

  int get uploadLimit {
    switch (this) {
      case TierEnum.free:
        return AppConstants.uploadLimitFree;
      case TierEnum.basic:
        return AppConstants.uploadLimitBasic;
      case TierEnum.pro:
        return -1; // unlimited
    }
  }

  /// Maximum pages per uploaded document. null = no limit (Pro).
  int? get maxPagesPerDocument {
    switch (this) {
      case TierEnum.free:
        return AppConstants.freeMaxPagesPerDocument;
      case TierEnum.basic:
        return AppConstants.basicMaxPagesPerDocument;
      case TierEnum.pro:
        return null;
    }
  }

  String get displayName {
    switch (this) {
      case TierEnum.free:
        return 'Free';
      case TierEnum.basic:
        return 'Basic';
      case TierEnum.pro:
        return 'Pro';
    }
  }
}

// ── Source Document File Type ─────────────────────────────────────────────────

@HiveType(typeId: AppConstants.fileTypeEnumTypeId)
enum FileTypeEnum {
  @HiveField(0)
  pdf,

  @HiveField(1)
  docx,

  @HiveField(2)
  txt,

  @HiveField(3)
  image,
}

extension FileTypeEnumX on FileTypeEnum {
  String get displayName {
    switch (this) {
      case FileTypeEnum.pdf:
        return 'PDF';
      case FileTypeEnum.docx:
        return 'DOCX';
      case FileTypeEnum.txt:
        return 'TXT';
      case FileTypeEnum.image:
        return 'Image';
    }
  }
}

// ── Document Role ─────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.documentRoleEnumTypeId)
enum DocumentRoleEnum {
  @HiveField(0)
  sourceResume,

  @HiveField(1)
  jobPosting, // drives tailored resume creation flow

  @HiveField(2)
  certificate,

  @HiveField(3)
  other,
}

// ── Extraction Status ─────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.extractionStatusEnumTypeId)
enum ExtractionStatusEnum {
  @HiveField(0)
  pending,

  @HiveField(1)
  complete,

  @HiveField(2)
  failed,
}

// ── Resume Section Type ───────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.sectionTypeEnumTypeId)
enum SectionTypeEnum {
  @HiveField(0)
  contact,

  @HiveField(1)
  summary,

  @HiveField(2)
  experience,

  @HiveField(3)
  education,

  @HiveField(4)
  skills,

  @HiveField(5)
  certifications,

  @HiveField(6)
  custom,
}

extension SectionTypeEnumX on SectionTypeEnum {
  String get displayName {
    switch (this) {
      case SectionTypeEnum.contact:
        return 'Contact Info';
      case SectionTypeEnum.summary:
        return 'Professional Summary';
      case SectionTypeEnum.experience:
        return 'Work Experience';
      case SectionTypeEnum.education:
        return 'Education';
      case SectionTypeEnum.skills:
        return 'Skills';
      case SectionTypeEnum.certifications:
        return 'Certifications';
      case SectionTypeEnum.custom:
        return 'Custom Section';
    }
  }

  // Fixed wizard step order — sections are never reordered (Rule §11)
  int get wizardStep {
    switch (this) {
      case SectionTypeEnum.contact:
        return 1;
      case SectionTypeEnum.summary:
        return 2;
      case SectionTypeEnum.experience:
        return 3;
      case SectionTypeEnum.education:
        return 4;
      case SectionTypeEnum.skills:
        return 5;
      case SectionTypeEnum.certifications:
        return 6;
      case SectionTypeEnum.custom:
        return 7;
    }
  }
}

// ── Skill Category ────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.skillCategoryEnumTypeId)
enum SkillCategoryEnum {
  @HiveField(0)
  technical,

  @HiveField(1)
  softSkill,

  @HiveField(2)
  toolsSoftware,

  @HiveField(3)
  uncategorized,
}

extension SkillCategoryEnumX on SkillCategoryEnum {
  String get displayName {
    switch (this) {
      case SkillCategoryEnum.technical:
        return 'Technical';
      case SkillCategoryEnum.softSkill:
        return 'Soft Skills';
      case SkillCategoryEnum.toolsSoftware:
        return 'Tools & Software';
      case SkillCategoryEnum.uncategorized:
        return 'Skills';
    }
  }
}

// ── Interview Question Category ───────────────────────────────────────────────

@HiveType(typeId: AppConstants.questionCategoryEnumTypeId)
enum QuestionCategoryEnum {
  @HiveField(0)
  behavioral,

  @HiveField(1)
  roleSpecific,

  @HiveField(2)
  companySpecific,
}

// ── Add-On Purchase Type ──────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.addOnTypeEnumTypeId)
enum AddOnTypeEnum {
  @HiveField(0)
  coverLetterTailoredCombo, // extensible for future add-ons
}

// ── Export Format ─────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.exportFormatEnumTypeId)
enum ExportFormatEnum {
  @HiveField(0)
  pdf, // all tiers

  @HiveField(1)
  docx, // Basic+

  @HiveField(2)
  plainText, // Pro only
}

extension ExportFormatEnumX on ExportFormatEnum {
  String get displayName {
    switch (this) {
      case ExportFormatEnum.pdf:
        return 'PDF';
      case ExportFormatEnum.docx:
        return 'Word (.docx)';
      case ExportFormatEnum.plainText:
        return 'Plain Text (.txt)';
    }
  }

  TierEnum get minimumTier {
    switch (this) {
      case ExportFormatEnum.pdf:
        return TierEnum.free;
      case ExportFormatEnum.docx:
        return TierEnum.basic;
      case ExportFormatEnum.plainText:
        return TierEnum.pro;
    }
  }
}

// ── App Theme Preference ──────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.appThemeEnumTypeId)
enum AppThemeEnum {
  @HiveField(0)
  system,

  @HiveField(1)
  light,

  @HiveField(2)
  dark,
}
