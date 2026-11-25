// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserSettingsAdapter extends TypeAdapter<UserSettings> {
  @override
  final int typeId = 6;

  @override
  UserSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserSettings(
      privacyAccepted: fields[0] as bool,
      privacyAcceptedAt: fields[1] as DateTime?,
      onboardingComplete: fields[2] as bool,
      ratingPromptShown: fields[3] as bool,
      tier: fields[4] as TierEnum,
      billingCycleStart: fields[5] as DateTime?,
      tailoredResumesCreatedThisCycle: (fields[6] as num).toInt(),
      masterResumeResetDate: fields[7] as DateTime?,
      defaultExportFormat: fields[8] as ExportFormatEnum,
      theme: fields[9] as AppThemeEnum,
      atsNotificationsEnabled: fields[10] as bool,
      totalUploadCount: (fields[11] as num).toInt(),
      fontScaleOverride: (fields[12] as num?)?.toDouble(),
      highContrastOverride: fields[13] as bool?,
      reduceMotionOverride: fields[14] as bool?,
      screenReaderHintsEnabled: fields[15] as bool,
      experienceSanitizedVersion:
          fields[16] == null ? 0 : (fields[16] as num).toInt(),
      aiDataSharingAccepted: fields[17] == null ? false : fields[17] as bool,
      ageBracket: fields[18] == null
          ? AgeBracketEnum.unknown
          : fields[18] as AgeBracketEnum,
      ageSignalCheckedAt: fields[19] as DateTime?,
      ageRestrictionNoticeShown:
          fields[20] == null ? false : fields[20] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, UserSettings obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.privacyAccepted)
      ..writeByte(1)
      ..write(obj.privacyAcceptedAt)
      ..writeByte(2)
      ..write(obj.onboardingComplete)
      ..writeByte(3)
      ..write(obj.ratingPromptShown)
      ..writeByte(4)
      ..write(obj.tier)
      ..writeByte(5)
      ..write(obj.billingCycleStart)
      ..writeByte(6)
      ..write(obj.tailoredResumesCreatedThisCycle)
      ..writeByte(7)
      ..write(obj.masterResumeResetDate)
      ..writeByte(8)
      ..write(obj.defaultExportFormat)
      ..writeByte(9)
      ..write(obj.theme)
      ..writeByte(10)
      ..write(obj.atsNotificationsEnabled)
      ..writeByte(11)
      ..write(obj.totalUploadCount)
      ..writeByte(12)
      ..write(obj.fontScaleOverride)
      ..writeByte(13)
      ..write(obj.highContrastOverride)
      ..writeByte(14)
      ..write(obj.reduceMotionOverride)
      ..writeByte(15)
      ..write(obj.screenReaderHintsEnabled)
      ..writeByte(16)
      ..write(obj.experienceSanitizedVersion)
      ..writeByte(17)
      ..write(obj.aiDataSharingAccepted)
      ..writeByte(18)
      ..write(obj.ageBracket)
      ..writeByte(19)
      ..write(obj.ageSignalCheckedAt)
      ..writeByte(20)
      ..write(obj.ageRestrictionNoticeShown);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
