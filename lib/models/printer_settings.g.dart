// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'printer_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PrinterSettingsAdapter extends TypeAdapter<PrinterSettings> {
  @override
  final int typeId = 51;

  @override
  PrinterSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PrinterSettings(
      bluetoothAddress: fields[0] as String?,
      bluetoothName: fields[1] as String?,
      paperMm: fields[2] as int,
    );
  }

  @override
  void write(BinaryWriter writer, PrinterSettings obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.bluetoothAddress)
      ..writeByte(1)
      ..write(obj.bluetoothName)
      ..writeByte(2)
      ..write(obj.paperMm);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrinterSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
