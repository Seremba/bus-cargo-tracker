// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TripAdapter extends TypeAdapter<Trip> {
  @override
  final int typeId = 7;

  @override
  Trip read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Trip(
      tripId: fields[0] as String,
      routeName: fields[1] as String,
      driverUserId: fields[2] as String,
      startedAt: fields[3] as DateTime,
      status: fields[5] as TripStatus,
      checkpoints: (fields[6] as List).cast<Checkpoint>(),
      routeId: fields[8] as String,
      endedAt: fields[4] as DateTime?,
      lastCheckpointIndex: fields[7] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Trip obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.tripId)
      ..writeByte(1)
      ..write(obj.routeName)
      ..writeByte(2)
      ..write(obj.driverUserId)
      ..writeByte(3)
      ..write(obj.startedAt)
      ..writeByte(4)
      ..write(obj.endedAt)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.checkpoints)
      ..writeByte(7)
      ..write(obj.lastCheckpointIndex)
      ..writeByte(8)
      ..write(obj.routeId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
