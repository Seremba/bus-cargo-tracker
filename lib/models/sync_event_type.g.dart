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
        return SyncEventType.tripCompleted;
      case 16:
        return SyncEventType.tripCancelled;
      case 17:
        return SyncEventType.propertyInTransit;
      case 18:
        return SyncEventType.paymentVoided;
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
      case 25:
        return SyncEventType.propertyCommitted;
      case 26:
        return SyncEventType.propertyLoaded;
      case 27:
        return SyncEventType.propertyStatusManuallyChanged;
      case 28:
        return SyncEventType.receiptPrinted;
      case 29:
        return SyncEventType.pickupOtpReset;
      case 30:
        return SyncEventType.pickupConfirmed;
      case 31:
        return SyncEventType.pickupAttemptFailed;
      case 32:
        return SyncEventType.pickupLockedOut;
      case 33:
        return SyncEventType.qrNonceRotated;
      case 34:
        return SyncEventType.propertyItemCreated;
      case 35:
        return SyncEventType.propertyItemDeferred;
      case 36:
        return SyncEventType.tripCreated;
      case 37:
        return SyncEventType.tripUpdated;
      case 38:
        return SyncEventType.trackingCodeGenerated;
      case 39:
        return SyncEventType.receiverNotificationsEnabled;
      case 40:
        return SyncEventType.receiverNotificationQueued;
      case 41:
        return SyncEventType.receiverNotificationSent;
      case 42:
        return SyncEventType.receiverNotificationFailed;
      case 43:
        return SyncEventType.userCreated;
      case 44:
        return SyncEventType.userUpdated;
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
      case SyncEventType.tripCompleted:
        writer.writeByte(15);
        break;
      case SyncEventType.tripCancelled:
        writer.writeByte(16);
        break;
      case SyncEventType.propertyInTransit:
        writer.writeByte(17);
        break;
      case SyncEventType.paymentVoided:
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
      case SyncEventType.propertyCommitted:
        writer.writeByte(25);
        break;
      case SyncEventType.propertyLoaded:
        writer.writeByte(26);
        break;
      case SyncEventType.propertyStatusManuallyChanged:
        writer.writeByte(27);
        break;
      case SyncEventType.receiptPrinted:
        writer.writeByte(28);
        break;
      case SyncEventType.pickupOtpReset:
        writer.writeByte(29);
        break;
      case SyncEventType.pickupConfirmed:
        writer.writeByte(30);
        break;
      case SyncEventType.pickupAttemptFailed:
        writer.writeByte(31);
        break;
      case SyncEventType.pickupLockedOut:
        writer.writeByte(32);
        break;
      case SyncEventType.qrNonceRotated:
        writer.writeByte(33);
        break;
      case SyncEventType.propertyItemCreated:
        writer.writeByte(34);
        break;
      case SyncEventType.propertyItemDeferred:
        writer.writeByte(35);
        break;
      case SyncEventType.tripCreated:
        writer.writeByte(36);
        break;
      case SyncEventType.tripUpdated:
        writer.writeByte(37);
        break;
      case SyncEventType.trackingCodeGenerated:
        writer.writeByte(38);
        break;
      case SyncEventType.receiverNotificationsEnabled:
        writer.writeByte(39);
        break;
      case SyncEventType.receiverNotificationQueued:
        writer.writeByte(40);
        break;
      case SyncEventType.receiverNotificationSent:
        writer.writeByte(41);
        break;
      case SyncEventType.receiverNotificationFailed:
        writer.writeByte(42);
        break;
      case SyncEventType.userCreated:
        writer.writeByte(43);
        break;
      case SyncEventType.userUpdated:
        writer.writeByte(44);
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
