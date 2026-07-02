// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resume_sections.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ResumeSectionAdapter extends TypeAdapter<ResumeSection> {
  @override
  final int typeId = 2;

  @override
  ResumeSection read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ResumeSection(
      id: fields[0] as String,
      resumeId: fields[1] as String,
      type: fields[2] as SectionTypeEnum,
      data: fields[3] as String,
      hasUnreviewedAIContent: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ResumeSection obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.resumeId)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.data)
      ..writeByte(4)
      ..write(obj.hasUnreviewedAIContent);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResumeSectionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ContactInfoAdapter extends TypeAdapter<ContactInfo> {
  @override
  final int typeId = 12;

  @override
  ContactInfo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ContactInfo(
      firstName: fields[0] as String,
      lastName: fields[1] as String,
      professionalTitle: fields[2] as String,
      city: fields[3] as String,
      state: fields[4] as String,
      phone: fields[5] as String,
      email: fields[6] as String,
      linkedInUrl: fields[7] as String?,
      websiteUrl: fields[8] as String?,
      gitHubUrl: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ContactInfo obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.firstName)
      ..writeByte(1)
      ..write(obj.lastName)
      ..writeByte(2)
      ..write(obj.professionalTitle)
      ..writeByte(3)
      ..write(obj.city)
      ..writeByte(4)
      ..write(obj.state)
      ..writeByte(5)
      ..write(obj.phone)
      ..writeByte(6)
      ..write(obj.email)
      ..writeByte(7)
      ..write(obj.linkedInUrl)
      ..writeByte(8)
      ..write(obj.websiteUrl)
      ..writeByte(9)
      ..write(obj.gitHubUrl);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactInfoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SkillEntryAdapter extends TypeAdapter<SkillEntry> {
  @override
  final int typeId = 8;

  @override
  SkillEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SkillEntry(
      id: fields[0] as String,
      name: fields[1] as String,
      category: fields[2] as SkillCategoryEnum,
      isAIPrefilled: fields[3] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, SkillEntry obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.isAIPrefilled);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ExperienceEntryAdapter extends TypeAdapter<ExperienceEntry> {
  @override
  final int typeId = 9;

  @override
  ExperienceEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExperienceEntry(
      id: fields[0] as String,
      title: fields[1] as String,
      company: fields[2] as String,
      location: fields[3] as String,
      startDate: fields[4] as String,
      endDate: fields[5] as String?,
      isCurrent: fields[6] as bool,
      bullets: (fields[7] as List?)?.cast<String>(),
      isAIPrefilled: fields[8] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ExperienceEntry obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.company)
      ..writeByte(3)
      ..write(obj.location)
      ..writeByte(4)
      ..write(obj.startDate)
      ..writeByte(5)
      ..write(obj.endDate)
      ..writeByte(6)
      ..write(obj.isCurrent)
      ..writeByte(7)
      ..write(obj.bullets)
      ..writeByte(8)
      ..write(obj.isAIPrefilled);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExperienceEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class EducationEntryAdapter extends TypeAdapter<EducationEntry> {
  @override
  final int typeId = 10;

  @override
  EducationEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EducationEntry(
      id: fields[0] as String,
      degree: fields[1] as String,
      institution: fields[2] as String,
      fieldOfStudy: fields[3] as String,
      graduationYear: fields[4] as String,
      gpa: fields[5] as String?,
      isAIPrefilled: fields[6] as bool,
      honors: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, EducationEntry obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.degree)
      ..writeByte(2)
      ..write(obj.institution)
      ..writeByte(3)
      ..write(obj.fieldOfStudy)
      ..writeByte(4)
      ..write(obj.graduationYear)
      ..writeByte(5)
      ..write(obj.gpa)
      ..writeByte(6)
      ..write(obj.isAIPrefilled)
      ..writeByte(7)
      ..write(obj.honors);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EducationEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class CertificationEntryAdapter extends TypeAdapter<CertificationEntry> {
  @override
  final int typeId = 11;

  @override
  CertificationEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CertificationEntry(
      id: fields[0] as String,
      name: fields[1] as String,
      issuer: fields[2] as String,
      dateEarned: fields[3] as String,
      expiresDate: fields[4] as String?,
      credentialId: fields[5] as String?,
      isAIPrefilled: fields[6] as bool,
      needsComplianceReview: fields[7] == null ? false : fields[7] as bool,
      complianceReviewReason: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, CertificationEntry obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.issuer)
      ..writeByte(3)
      ..write(obj.dateEarned)
      ..writeByte(4)
      ..write(obj.expiresDate)
      ..writeByte(5)
      ..write(obj.credentialId)
      ..writeByte(6)
      ..write(obj.isAIPrefilled)
      ..writeByte(7)
      ..write(obj.needsComplianceReview)
      ..writeByte(8)
      ..write(obj.complianceReviewReason);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CertificationEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
