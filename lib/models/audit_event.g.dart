// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_event.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AuditEventAdapter extends TypeAdapter<AuditEvent> {
  @override
  final int typeId = 1;

  @override
  AuditEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AuditEvent(
      id: fields[0] as String,
      at: fields[1] as DateTime,
      action: fields[4] as String,
      actorUserId: fields[2] as String?,
      actorRole: fields[3] as String?,
      propertyKey: fields[5] as String?,
      tripId: fields[6] as String?,
      details: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AuditEvent obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.at)
      ..writeByte(2)
      ..write(obj.actorUserId)
      ..writeByte(3)
      ..write(obj.actorRole)
      ..writeByte(4)
      ..write(obj.action)
      ..writeByte(5)
      ..write(obj.propertyKey)
      ..writeByte(6)
      ..write(obj.tripId)
      ..writeByte(7)
      ..write(obj.details);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditEventAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
