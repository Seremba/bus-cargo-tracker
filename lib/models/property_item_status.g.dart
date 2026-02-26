// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'property_item_status.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PropertyItemStatusAdapter extends TypeAdapter<PropertyItemStatus> {
  @override
  final int typeId = 64;

  @override
  PropertyItemStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return PropertyItemStatus.pending;
      case 1:
        return PropertyItemStatus.loaded;
      case 2:
        return PropertyItemStatus.inTransit;
      case 3:
        return PropertyItemStatus.delivered;
      case 4:
        return PropertyItemStatus.pickedUp;
      default:
        return PropertyItemStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, PropertyItemStatus obj) {
    switch (obj) {
      case PropertyItemStatus.pending:
        writer.writeByte(0);
        break;
      case PropertyItemStatus.loaded:
        writer.writeByte(1);
        break;
      case PropertyItemStatus.inTransit:
        writer.writeByte(2);
        break;
      case PropertyItemStatus.delivered:
        writer.writeByte(3);
        break;
      case PropertyItemStatus.pickedUp:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PropertyItemStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
