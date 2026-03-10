import 'package:hive/hive.dart';

part 'sync_event_type.g.dart';

@HiveType(typeId: 16)
enum SyncEventType {
  @HiveField(0)
  propertyCreated,

  @HiveField(1)
  paymentRecorded,

  @HiveField(2)
  itemsLoadedPartial,

  @HiveField(3)
  tripStarted,

  @HiveField(4)
  checkpointReached,

  @HiveField(5)
  propertyDelivered,

  @HiveField(6)
  propertyPickedUp,

  @HiveField(7)
  exceptionLogged,

  @HiveField(8)
  receiverNotifyRequested,

  @HiveField(9)
  senderNotifyRequested,

  @HiveField(10)
  partialLoadNotifyRequested,

  @HiveField(11)
  passwordResetOtpRequested,

  @HiveField(12)
  pickupOtpGenerated,

  @HiveField(13)
  pickupOtpVerified,

  @HiveField(14)
  tripCheckpointReached,

  @HiveField(15)
  tripEnded,

  @HiveField(16)
  tripCancelled,
  
  @HiveField(17)
  propertyInTransit,
}
