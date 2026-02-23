// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'property.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PropertyAdapter extends TypeAdapter<Property> {
  @override
  final int typeId = 5;

  @override
  Property read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Property(
      receiverName: fields[0] as String,
      receiverPhone: fields[1] as String,
      description: fields[2] as String,
      destination: fields[3] as String,
      itemCount: fields[17] == null ? 1 : fields[17] as int,
      createdAt: fields[4] as DateTime,
      status: fields[5] as PropertyStatus,
      createdByUserId: fields[12] as String,
      pickupOtp: fields[11] as String?,
      inTransitAt: fields[6] as DateTime?,
      deliveredAt: fields[7] as DateTime?,
      staffPickupConfirmed: fields[8] as bool,
      receiverPickupConfirmed: fields[9] as bool,
      pickedUpAt: fields[10] as DateTime?,
      tripId: fields[13] as String?,
      otpGeneratedAt: fields[14] as DateTime?,
      otpAttempts: fields[15] as int,
      otpLockedUntil: fields[16] as DateTime?,
      routeId: fields[18] == null ? '' : fields[18] as String?,
      routeName: fields[19] == null ? '' : fields[19] as String?,
      qrIssuedAt: fields[20] as DateTime?,
      qrNonce: fields[21] == null ? '' : fields[21] as String,
      qrConsumedAt: fields[22] as DateTime?,
      propertyCode: fields[23] == null ? '' : fields[23] as String?,
      amountPaidTotal: fields[24] == null ? 0 : fields[24] as int,
      currency: fields[25] == null ? 'UGX' : fields[25] as String?,
      lastPaidAt: fields[26] as DateTime?,
      lastPaymentMethod: fields[27] == null ? '' : fields[27] as String?,
      lastPaidByUserId: fields[28] == null ? '' : fields[28] as String?,
      lastPaidAtStation: fields[29] == null ? '' : fields[29] as String?,
      lastTxnRef: fields[30] == null ? '' : fields[30] as String?,
      loadedAt: fields[31] as DateTime?,
      loadedAtStation: fields[32] == null ? '' : fields[32] as String?,
      loadedByUserId: fields[33] == null ? '' : fields[33] as String?,
      trackingCode: fields[34] == null ? '' : fields[34] as String?,
      notifyReceiver: fields[35] == null ? false : fields[35] as bool,
      receiverNotifyEnabledAt: fields[36] as DateTime?,
      receiverNotifyEnabledByUserId:
          fields[37] == null ? '' : fields[37] as String?,
      lastReceiverNotifiedAt: fields[38] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Property obj) {
    writer
      ..writeByte(39)
      ..writeByte(0)
      ..write(obj.receiverName)
      ..writeByte(1)
      ..write(obj.receiverPhone)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.destination)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.inTransitAt)
      ..writeByte(7)
      ..write(obj.deliveredAt)
      ..writeByte(8)
      ..write(obj.staffPickupConfirmed)
      ..writeByte(9)
      ..write(obj.receiverPickupConfirmed)
      ..writeByte(10)
      ..write(obj.pickedUpAt)
      ..writeByte(11)
      ..write(obj.pickupOtp)
      ..writeByte(12)
      ..write(obj.createdByUserId)
      ..writeByte(13)
      ..write(obj.tripId)
      ..writeByte(14)
      ..write(obj.otpGeneratedAt)
      ..writeByte(15)
      ..write(obj.otpAttempts)
      ..writeByte(16)
      ..write(obj.otpLockedUntil)
      ..writeByte(17)
      ..write(obj.itemCount)
      ..writeByte(18)
      ..write(obj.routeId)
      ..writeByte(19)
      ..write(obj.routeName)
      ..writeByte(20)
      ..write(obj.qrIssuedAt)
      ..writeByte(21)
      ..write(obj.qrNonce)
      ..writeByte(22)
      ..write(obj.qrConsumedAt)
      ..writeByte(23)
      ..write(obj.propertyCode)
      ..writeByte(24)
      ..write(obj.amountPaidTotal)
      ..writeByte(25)
      ..write(obj.currency)
      ..writeByte(26)
      ..write(obj.lastPaidAt)
      ..writeByte(27)
      ..write(obj.lastPaymentMethod)
      ..writeByte(28)
      ..write(obj.lastPaidByUserId)
      ..writeByte(29)
      ..write(obj.lastPaidAtStation)
      ..writeByte(30)
      ..write(obj.lastTxnRef)
      ..writeByte(31)
      ..write(obj.loadedAt)
      ..writeByte(32)
      ..write(obj.loadedAtStation)
      ..writeByte(33)
      ..write(obj.loadedByUserId)
      ..writeByte(34)
      ..write(obj.trackingCode)
      ..writeByte(35)
      ..write(obj.notifyReceiver)
      ..writeByte(36)
      ..write(obj.receiverNotifyEnabledAt)
      ..writeByte(37)
      ..write(obj.receiverNotifyEnabledByUserId)
      ..writeByte(38)
      ..write(obj.lastReceiverNotifiedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PropertyAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
