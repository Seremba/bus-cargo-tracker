// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'property_status.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PropertyStatusAdapter extends TypeAdapter<PropertyStatus> {
  @override
  final int typeId = 4;

  @override
  PropertyStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return PropertyStatus.pending;
      case 1:
        return PropertyStatus.inTransit;
      case 2:
        return PropertyStatus.delivered;
      case 3:
        return PropertyStatus.pickedUp;
      default:
        return PropertyStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, PropertyStatus obj) {
    switch (obj) {
      case PropertyStatus.pending:
        writer.writeByte(0);
        break;
      case PropertyStatus.inTransit:
        writer.writeByte(1);
        break;
      case PropertyStatus.delivered:
        writer.writeByte(2);
        break;
      case PropertyStatus.pickedUp:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PropertyStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
