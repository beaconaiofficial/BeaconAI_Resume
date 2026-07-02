// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resume.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ResumeAdapter extends TypeAdapter<Resume> {
  @override
  final int typeId = 0;

  @override
  Resume read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Resume(
      id: fields[0] as String,
      title: fields[1] as String,
      createdAt: fields[2] as DateTime,
      updatedAt: fields[3] as DateTime,
      isMaster: fields[4] as bool,
      templateId: fields[5] as String,
      templateAccentColor: fields[6] as String?,
      linkedJobDescription: fields[7] as String?,
      uploadCount: (fields[8] as num).toInt(),
      isArchived: fields[9] as bool,
      companyName: fields[10] as String?,
      roleTitle: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Resume obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.updatedAt)
      ..writeByte(4)
      ..write(obj.isMaster)
      ..writeByte(5)
      ..write(obj.templateId)
      ..writeByte(6)
      ..write(obj.templateAccentColor)
      ..writeByte(7)
      ..write(obj.linkedJobDescription)
      ..writeByte(8)
      ..write(obj.uploadCount)
      ..writeByte(9)
      ..write(obj.isArchived)
      ..writeByte(10)
      ..write(obj.companyName)
      ..writeByte(11)
      ..write(obj.roleTitle);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResumeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
