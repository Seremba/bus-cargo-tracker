// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_event_type.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SyncEventTypeAdapter extends TypeAdapter<SyncEventType> {
  @override
  final int typeId = 16;

  @override
  SyncEventType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return SyncEventType.propertyCreated;
      case 1:
        return SyncEventType.paymentRecorded;
      case 2:
        return SyncEventType.itemsLoadedPartial;
      case 3:
        return SyncEventType.tripStarted;
      case 4:
        return SyncEventType.checkpointReached;
      case 5:
        return SyncEventType.propertyDelivered;
      case 6:
        return SyncEventType.propertyPickedUp;
      case 7:
        return SyncEventType.exceptionLogged;
      case 8:
        return SyncEventType.receiverNotifyRequested;
      case 9:
        return SyncEventType.senderNotifyRequested;
      case 10:
        return SyncEventType.partialLoadNotifyRequested;
      case 11:
        return SyncEventType.passwordResetOtpRequested;
      case 12:
        return SyncEventType.pickupOtpGenerated;
      case 13:
        return SyncEventType.pickupOtpVerified;
      case 14:
        return SyncEventType.tripCheckpointReached;
      case 15:
        return SyncEventType.tripEnded;
      case 16:
        return SyncEventType.tripCancelled;
      case 17:
        return SyncEventType.propertyInTransit;
      case 18:
        return SyncEventType.paymentRefunded;
      case 19:
        return SyncEventType.paymentAdjusted;
      case 20:
        return SyncEventType.propertyItemLoaded;
      case 21:
        return SyncEventType.propertyItemInTransit;
      case 22:
        return SyncEventType.propertyItemDelivered;
      case 23:
        return SyncEventType.propertyItemPickedUp;
      case 24:
        return SyncEventType.adminOverrideApplied;
      default:
        return SyncEventType.propertyCreated;
    }
  }

  @override
  void write(BinaryWriter writer, SyncEventType obj) {
    switch (obj) {
      case SyncEventType.propertyCreated:
        writer.writeByte(0);
        break;
      case SyncEventType.paymentRecorded:
        writer.writeByte(1);
        break;
      case SyncEventType.itemsLoadedPartial:
        writer.writeByte(2);
        break;
      case SyncEventType.tripStarted:
        writer.writeByte(3);
        break;
      case SyncEventType.checkpointReached:
        writer.writeByte(4);
        break;
      case SyncEventType.propertyDelivered:
        writer.writeByte(5);
        break;
      case SyncEventType.propertyPickedUp:
        writer.writeByte(6);
        break;
      case SyncEventType.exceptionLogged:
        writer.writeByte(7);
        break;
      case SyncEventType.receiverNotifyRequested:
        writer.writeByte(8);
        break;
      case SyncEventType.senderNotifyRequested:
        writer.writeByte(9);
        break;
      case SyncEventType.partialLoadNotifyRequested:
        writer.writeByte(10);
        break;
      case SyncEventType.passwordResetOtpRequested:
        writer.writeByte(11);
        break;
      case SyncEventType.pickupOtpGenerated:
        writer.writeByte(12);
        break;
      case SyncEventType.pickupOtpVerified:
        writer.writeByte(13);
        break;
      case SyncEventType.tripCheckpointReached:
        writer.writeByte(14);
        break;
      case SyncEventType.tripEnded:
        writer.writeByte(15);
        break;
      case SyncEventType.tripCancelled:
        writer.writeByte(16);
        break;
      case SyncEventType.propertyInTransit:
        writer.writeByte(17);
        break;
      case SyncEventType.paymentRefunded:
        writer.writeByte(18);
        break;
      case SyncEventType.paymentAdjusted:
        writer.writeByte(19);
        break;
      case SyncEventType.propertyItemLoaded:
        writer.writeByte(20);
        break;
      case SyncEventType.propertyItemInTransit:
        writer.writeByte(21);
        break;
      case SyncEventType.propertyItemDelivered:
        writer.writeByte(22);
        break;
      case SyncEventType.propertyItemPickedUp:
        writer.writeByte(23);
        break;
      case SyncEventType.adminOverrideApplied:
        writer.writeByte(24);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncEventTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
