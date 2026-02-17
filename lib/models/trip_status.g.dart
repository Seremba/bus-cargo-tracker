// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip_status.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TripStatusAdapter extends TypeAdapter<TripStatus> {
  @override
  final int typeId = 6;

  @override
  TripStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TripStatus.active;
      case 1:
        return TripStatus.ended;
      case 2:
        return TripStatus.cancelled;
      default:
        return TripStatus.active;
    }
  }

  @override
  void write(BinaryWriter writer, TripStatus obj) {
    switch (obj) {
      case TripStatus.active:
        writer.writeByte(0);
        break;
      case TripStatus.ended:
        writer.writeByte(1);
        break;
      case TripStatus.cancelled:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
