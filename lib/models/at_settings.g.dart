// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'at_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AtSettingsAdapter extends TypeAdapter<AtSettings> {
  @override
  final int typeId = 11;

  @override
  AtSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AtSettings(
      apiKey: fields[0] as String,
      username: fields[1] as String,
      isSandbox: fields[2] as bool,
      senderId: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, AtSettings obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.apiKey)
      ..writeByte(1)
      ..write(obj.username)
      ..writeByte(2)
      ..write(obj.isSandbox)
      ..writeByte(3)
      ..write(obj.senderId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AtSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
