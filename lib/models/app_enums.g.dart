// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_enums.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TierEnumAdapter extends TypeAdapter<TierEnum> {
  @override
  final int typeId = 20;

  @override
  TierEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TierEnum.free;
      case 1:
        return TierEnum.basic;
      case 2:
        return TierEnum.pro;
      default:
        return TierEnum.free;
    }
  }

  @override
  void write(BinaryWriter writer, TierEnum obj) {
    switch (obj) {
      case TierEnum.free:
        writer.writeByte(0);
        break;
      case TierEnum.basic:
        writer.writeByte(1);
        break;
      case TierEnum.pro:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TierEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class FileTypeEnumAdapter extends TypeAdapter<FileTypeEnum> {
  @override
  final int typeId = 21;

  @override
  FileTypeEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return FileTypeEnum.pdf;
      case 1:
        return FileTypeEnum.docx;
      case 2:
        return FileTypeEnum.txt;
      case 3:
        return FileTypeEnum.image;
      default:
        return FileTypeEnum.pdf;
    }
  }

  @override
  void write(BinaryWriter writer, FileTypeEnum obj) {
    switch (obj) {
      case FileTypeEnum.pdf:
        writer.writeByte(0);
        break;
      case FileTypeEnum.docx:
        writer.writeByte(1);
        break;
      case FileTypeEnum.txt:
        writer.writeByte(2);
        break;
      case FileTypeEnum.image:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileTypeEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class DocumentRoleEnumAdapter extends TypeAdapter<DocumentRoleEnum> {
  @override
  final int typeId = 22;

  @override
  DocumentRoleEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return DocumentRoleEnum.sourceResume;
      case 1:
        return DocumentRoleEnum.jobPosting;
      case 2:
        return DocumentRoleEnum.certificate;
      case 3:
        return DocumentRoleEnum.other;
      default:
        return DocumentRoleEnum.sourceResume;
    }
  }

  @override
  void write(BinaryWriter writer, DocumentRoleEnum obj) {
    switch (obj) {
      case DocumentRoleEnum.sourceResume:
        writer.writeByte(0);
        break;
      case DocumentRoleEnum.jobPosting:
        writer.writeByte(1);
        break;
      case DocumentRoleEnum.certificate:
        writer.writeByte(2);
        break;
      case DocumentRoleEnum.other:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentRoleEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ExtractionStatusEnumAdapter extends TypeAdapter<ExtractionStatusEnum> {
  @override
  final int typeId = 23;

  @override
  ExtractionStatusEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ExtractionStatusEnum.pending;
      case 1:
        return ExtractionStatusEnum.complete;
      case 2:
        return ExtractionStatusEnum.failed;
      default:
        return ExtractionStatusEnum.pending;
    }
  }

  @override
  void write(BinaryWriter writer, ExtractionStatusEnum obj) {
    switch (obj) {
      case ExtractionStatusEnum.pending:
        writer.writeByte(0);
        break;
      case ExtractionStatusEnum.complete:
        writer.writeByte(1);
        break;
      case ExtractionStatusEnum.failed:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtractionStatusEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SectionTypeEnumAdapter extends TypeAdapter<SectionTypeEnum> {
  @override
  final int typeId = 24;

  @override
  SectionTypeEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return SectionTypeEnum.contact;
      case 1:
        return SectionTypeEnum.summary;
      case 2:
        return SectionTypeEnum.experience;
      case 3:
        return SectionTypeEnum.education;
      case 4:
        return SectionTypeEnum.skills;
      case 5:
        return SectionTypeEnum.certifications;
      case 6:
        return SectionTypeEnum.custom;
      default:
        return SectionTypeEnum.contact;
    }
  }

  @override
  void write(BinaryWriter writer, SectionTypeEnum obj) {
    switch (obj) {
      case SectionTypeEnum.contact:
        writer.writeByte(0);
        break;
      case SectionTypeEnum.summary:
        writer.writeByte(1);
        break;
      case SectionTypeEnum.experience:
        writer.writeByte(2);
        break;
      case SectionTypeEnum.education:
        writer.writeByte(3);
        break;
      case SectionTypeEnum.skills:
        writer.writeByte(4);
        break;
      case SectionTypeEnum.certifications:
        writer.writeByte(5);
        break;
      case SectionTypeEnum.custom:
        writer.writeByte(6);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SectionTypeEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SkillCategoryEnumAdapter extends TypeAdapter<SkillCategoryEnum> {
  @override
  final int typeId = 25;

  @override
  SkillCategoryEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return SkillCategoryEnum.technical;
      case 1:
        return SkillCategoryEnum.softSkill;
      case 2:
        return SkillCategoryEnum.toolsSoftware;
      case 3:
        return SkillCategoryEnum.uncategorized;
      default:
        return SkillCategoryEnum.technical;
    }
  }

  @override
  void write(BinaryWriter writer, SkillCategoryEnum obj) {
    switch (obj) {
      case SkillCategoryEnum.technical:
        writer.writeByte(0);
        break;
      case SkillCategoryEnum.softSkill:
        writer.writeByte(1);
        break;
      case SkillCategoryEnum.toolsSoftware:
        writer.writeByte(2);
        break;
      case SkillCategoryEnum.uncategorized:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillCategoryEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class QuestionCategoryEnumAdapter extends TypeAdapter<QuestionCategoryEnum> {
  @override
  final int typeId = 26;

  @override
  QuestionCategoryEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return QuestionCategoryEnum.behavioral;
      case 1:
        return QuestionCategoryEnum.roleSpecific;
      case 2:
        return QuestionCategoryEnum.companySpecific;
      default:
        return QuestionCategoryEnum.behavioral;
    }
  }

  @override
  void write(BinaryWriter writer, QuestionCategoryEnum obj) {
    switch (obj) {
      case QuestionCategoryEnum.behavioral:
        writer.writeByte(0);
        break;
      case QuestionCategoryEnum.roleSpecific:
        writer.writeByte(1);
        break;
      case QuestionCategoryEnum.companySpecific:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuestionCategoryEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AddOnTypeEnumAdapter extends TypeAdapter<AddOnTypeEnum> {
  @override
  final int typeId = 27;

  @override
  AddOnTypeEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AddOnTypeEnum.coverLetterTailoredCombo;
      default:
        return AddOnTypeEnum.coverLetterTailoredCombo;
    }
  }

  @override
  void write(BinaryWriter writer, AddOnTypeEnum obj) {
    switch (obj) {
      case AddOnTypeEnum.coverLetterTailoredCombo:
        writer.writeByte(0);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddOnTypeEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ExportFormatEnumAdapter extends TypeAdapter<ExportFormatEnum> {
  @override
  final int typeId = 28;

  @override
  ExportFormatEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ExportFormatEnum.pdf;
      case 1:
        return ExportFormatEnum.docx;
      case 2:
        return ExportFormatEnum.plainText;
      default:
        return ExportFormatEnum.pdf;
    }
  }

  @override
  void write(BinaryWriter writer, ExportFormatEnum obj) {
    switch (obj) {
      case ExportFormatEnum.pdf:
        writer.writeByte(0);
        break;
      case ExportFormatEnum.docx:
        writer.writeByte(1);
        break;
      case ExportFormatEnum.plainText:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportFormatEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AppThemeEnumAdapter extends TypeAdapter<AppThemeEnum> {
  @override
  final int typeId = 29;

  @override
  AppThemeEnum read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AppThemeEnum.system;
      case 1:
        return AppThemeEnum.light;
      case 2:
        return AppThemeEnum.dark;
      default:
        return AppThemeEnum.system;
    }
  }

  @override
  void write(BinaryWriter writer, AppThemeEnum obj) {
    switch (obj) {
      case AppThemeEnum.system:
        writer.writeByte(0);
        break;
      case AppThemeEnum.light:
        writer.writeByte(1);
        break;
      case AppThemeEnum.dark:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppThemeEnumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
