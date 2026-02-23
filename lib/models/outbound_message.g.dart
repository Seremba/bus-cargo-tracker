// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outbound_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OutboundMessageAdapter extends TypeAdapter<OutboundMessage> {
  @override
  final int typeId = 13;

  @override
  OutboundMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OutboundMessage(
      id: fields[0] as String,
      toPhone: fields[1] as String,
      channel: fields[2] == null ? 'whatsapp' : fields[2] as String,
      body: fields[3] as String,
      createdAt: fields[8] as DateTime,
      propertyKey: fields[7] == null ? '' : fields[7] as String,
      status: fields[4] == null ? 'queued' : fields[4] as String,
      attempts: fields[5] == null ? 0 : fields[5] as int,
      lastAttemptAt: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, OutboundMessage obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.toPhone)
      ..writeByte(2)
      ..write(obj.channel)
      ..writeByte(3)
      ..write(obj.body)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.attempts)
      ..writeByte(6)
      ..write(obj.lastAttemptAt)
      ..writeByte(7)
      ..write(obj.propertyKey)
      ..writeByte(8)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutboundMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
