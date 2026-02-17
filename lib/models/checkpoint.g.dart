// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checkpoint.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CheckpointAdapter extends TypeAdapter<Checkpoint> {
  @override
  final int typeId = 2;

  @override
  Checkpoint read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Checkpoint(
      name: fields[0] as String,
      lat: fields[1] as double,
      lng: fields[2] as double,
      radiusMeters: fields[3] as double,
      reachedAt: fields[4] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Checkpoint obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.lat)
      ..writeByte(2)
      ..write(obj.lng)
      ..writeByte(3)
      ..write(obj.radiusMeters)
      ..writeByte(4)
      ..write(obj.reachedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CheckpointAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
