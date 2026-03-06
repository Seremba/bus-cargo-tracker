// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_event.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SyncEventAdapter extends TypeAdapter<SyncEvent> {
  @override
  final int typeId = 17;

  @override
  SyncEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SyncEvent(
      eventId: fields[0] as String,
      type: fields[1] as SyncEventType,
      aggregateType: fields[2] as String,
      aggregateId: fields[3] as String,
      actorUserId: fields[4] as String,
      payload: (fields[5] as Map).cast<String, dynamic>(),
      createdAt: fields[6] as DateTime,
      pendingPush: fields[7] == null ? true : fields[7] as bool,
      pushed: fields[8] == null ? false : fields[8] as bool,
      appliedLocally: fields[9] == null ? false : fields[9] as bool,
      remoteCursor: fields[10] as String?,
      pushAttempts: fields[11] == null ? 0 : fields[11] as int,
      lastPushAttemptAt: fields[12] as DateTime?,
      lastError: fields[13] == null ? '' : fields[13] as String?,
      sourceDeviceId: fields[14] == null ? '' : fields[14] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SyncEvent obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.eventId)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.aggregateType)
      ..writeByte(3)
      ..write(obj.aggregateId)
      ..writeByte(4)
      ..write(obj.actorUserId)
      ..writeByte(5)
      ..write(obj.payload)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.pendingPush)
      ..writeByte(8)
      ..write(obj.pushed)
      ..writeByte(9)
      ..write(obj.appliedLocally)
      ..writeByte(10)
      ..write(obj.remoteCursor)
      ..writeByte(11)
      ..write(obj.pushAttempts)
      ..writeByte(12)
      ..write(obj.lastPushAttemptAt)
      ..writeByte(13)
      ..write(obj.lastError)
      ..writeByte(14)
      ..write(obj.sourceDeviceId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncEventAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
