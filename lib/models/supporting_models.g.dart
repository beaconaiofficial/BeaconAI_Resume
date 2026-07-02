// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'supporting_models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SourceDocumentAdapter extends TypeAdapter<SourceDocument> {
  @override
  final int typeId = 1;

  @override
  SourceDocument read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SourceDocument(
      id: fields[0] as String,
      resumeId: fields[1] as String,
      fileName: fields[2] as String,
      fileType: fields[3] as FileTypeEnum,
      documentRole: fields[4] as DocumentRoleEnum,
      uploadedAt: fields[5] as DateTime,
      extractionStatus: fields[6] as ExtractionStatusEnum,
      rawExtractedText: fields[7] as String,
      appliedFields: (fields[8] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, SourceDocument obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.resumeId)
      ..writeByte(2)
      ..write(obj.fileName)
      ..writeByte(3)
      ..write(obj.fileType)
      ..writeByte(4)
      ..write(obj.documentRole)
      ..writeByte(5)
      ..write(obj.uploadedAt)
      ..writeByte(6)
      ..write(obj.extractionStatus)
      ..writeByte(7)
      ..write(obj.rawExtractedText)
      ..writeByte(8)
      ..write(obj.appliedFields);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceDocumentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class CoverLetterAdapter extends TypeAdapter<CoverLetter> {
  @override
  final int typeId = 3;

  @override
  CoverLetter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CoverLetter(
      id: fields[0] as String,
      resumeId: fields[1] as String,
      jobDescription: fields[2] as String,
      content: fields[3] as String,
      createdAt: fields[4] as DateTime,
      updatedAt: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, CoverLetter obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.resumeId)
      ..writeByte(2)
      ..write(obj.jobDescription)
      ..writeByte(3)
      ..write(obj.content)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoverLetterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class InterviewStudyGuideAdapter extends TypeAdapter<InterviewStudyGuide> {
  @override
  final int typeId = 4;

  @override
  InterviewStudyGuide read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InterviewStudyGuide(
      id: fields[0] as String,
      resumeId: fields[1] as String,
      companyName: fields[2] as String,
      roleTitle: fields[3] as String,
      generatedAt: fields[4] as DateTime,
      questions: (fields[5] as List?)?.cast<InterviewQuestion>(),
      exportedAt: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, InterviewStudyGuide obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.resumeId)
      ..writeByte(2)
      ..write(obj.companyName)
      ..writeByte(3)
      ..write(obj.roleTitle)
      ..writeByte(4)
      ..write(obj.generatedAt)
      ..writeByte(5)
      ..write(obj.questions)
      ..writeByte(6)
      ..write(obj.exportedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterviewStudyGuideAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class InterviewQuestionAdapter extends TypeAdapter<InterviewQuestion> {
  @override
  final int typeId = 5;

  @override
  InterviewQuestion read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InterviewQuestion(
      id: fields[0] as String,
      category: fields[1] as QuestionCategoryEnum,
      questionText: fields[2] as String,
      answerGuide: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, InterviewQuestion obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.category)
      ..writeByte(2)
      ..write(obj.questionText)
      ..writeByte(3)
      ..write(obj.answerGuide);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterviewQuestionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AddOnPurchaseAdapter extends TypeAdapter<AddOnPurchase> {
  @override
  final int typeId = 7;

  @override
  AddOnPurchase read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AddOnPurchase(
      id: fields[0] as String,
      purchasedAt: fields[1] as DateTime,
      type: fields[2] as AddOnTypeEnum,
      resumeId: fields[3] as String?,
      used: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, AddOnPurchase obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.purchasedAt)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.resumeId)
      ..writeByte(4)
      ..write(obj.used);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddOnPurchaseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
