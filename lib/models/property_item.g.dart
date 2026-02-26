// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'property_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PropertyItemAdapter extends TypeAdapter<PropertyItem> {
  @override
  final int typeId = 65;

  @override
  PropertyItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PropertyItem(
      itemKey: fields[0] as String,
      propertyKey: fields[1] as String,
      itemNo: fields[2] as int,
      status: fields[3] as PropertyItemStatus,
      labelCode: fields[9] as String,
      loadedAt: fields[4] as DateTime?,
      inTransitAt: fields[5] as DateTime?,
      deliveredAt: fields[6] as DateTime?,
      pickedUpAt: fields[7] as DateTime?,
      tripId: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PropertyItem obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.propertyKey)
      ..writeByte(2)
      ..write(obj.itemNo)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.loadedAt)
      ..writeByte(5)
      ..write(obj.inTransitAt)
      ..writeByte(6)
      ..write(obj.deliveredAt)
      ..writeByte(7)
      ..write(obj.pickedUpAt)
      ..writeByte(8)
      ..write(obj.tripId)
      ..writeByte(9)
      ..write(obj.labelCode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PropertyItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
