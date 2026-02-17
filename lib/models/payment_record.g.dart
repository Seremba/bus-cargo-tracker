// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PaymentRecordAdapter extends TypeAdapter<PaymentRecord> {
  @override
  final int typeId = 12;

  @override
  PaymentRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PaymentRecord(
      paymentId: fields[0] as String,
      propertyKey: fields[1] as String,
      amount: fields[2] as int,
      currency: fields[3] == null ? 'UGX' : fields[3] as String,
      method: fields[4] == null ? '' : fields[4] as String,
      txnRef: fields[5] == null ? '' : fields[5] as String,
      station: fields[6] == null ? '' : fields[6] as String,
      createdAt: fields[7] as DateTime,
      recordedByUserId: fields[8] == null ? '' : fields[8] as String,
      kind: fields[9] == null ? 'payment' : fields[9] as String,
      note: fields[10] == null ? '' : fields[10] as String,
    );
  }

  @override
  void write(BinaryWriter writer, PaymentRecord obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.paymentId)
      ..writeByte(1)
      ..write(obj.propertyKey)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.currency)
      ..writeByte(4)
      ..write(obj.method)
      ..writeByte(5)
      ..write(obj.txnRef)
      ..writeByte(6)
      ..write(obj.station)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.recordedByUserId)
      ..writeByte(9)
      ..write(obj.kind)
      ..writeByte(10)
      ..write(obj.note);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
