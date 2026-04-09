import 'package:hive/hive.dart';
part 'sync_event_type.g.dart';
// IMPORTANT — Hive field index rules:
// • Never reorder or renumber existing @HiveField indices.
// • New values must always be appended at the end with the next available index.
// • Renaming the Dart identifier is safe as long as the @HiveField index is unchanged.
// typeId: 16
@HiveType(typeId: 16)
enum SyncEventType {
  // ── Original values (indices 0–24, never change) ──────────────────────────
  @HiveField(0)
  propertyCreated,
  @HiveField(1)
  paymentRecorded,
  @HiveField(2)
  itemsLoadedPartial,
  @HiveField(3)
  tripStarted,
  @HiveField(4)
  checkpointReached, // legacy — superseded by tripCheckpointReached (14)
  @HiveField(5)
  propertyDelivered,
  @HiveField(6)
  propertyPickedUp,
  @HiveField(7)
  exceptionLogged,
  @HiveField(8)
  receiverNotifyRequested, // legacy — superseded by receiverNotificationQueued (40)
  @HiveField(9)
  senderNotifyRequested,
  @HiveField(10)
  partialLoadNotifyRequested,
  @HiveField(11)
  passwordResetOtpRequested,
  @HiveField(12)
  pickupOtpGenerated,
  @HiveField(13)
  pickupOtpVerified, // legacy — superseded by pickupConfirmed (30)
  @HiveField(14)
  tripCheckpointReached,
  // Phase 3 rename: tripEnded → tripCompleted (index 15 unchanged)
  @HiveField(15)
  tripCompleted, // was: tripEnded
  @HiveField(16)
  tripCancelled,
  @HiveField(17)
  propertyInTransit,
  // Phase 3 rename: paymentRefunded → paymentVoided (index 18 unchanged)
  @HiveField(18)
  paymentVoided, // was: paymentRefunded
  @HiveField(19)
  paymentAdjusted,
  @HiveField(20)
  propertyItemLoaded,
  @HiveField(21)
  propertyItemInTransit,
  @HiveField(22)
  propertyItemDelivered,
  @HiveField(23)
  propertyItemPickedUp,
  @HiveField(24)
  adminOverrideApplied,
  // ── Phase 3: new event types (appended from index 25) ─────────────────────
  // Property lifecycle
  @HiveField(25)
  propertyCommitted, // QR issued / commit hash locked
  @HiveField(26)
  propertyLoaded, // full load (all items loaded)
  @HiveField(27)
  propertyStatusManuallyChanged, // admin manual status override
  // Payment
  @HiveField(28)
  receiptPrinted,
  // Pickup / security
  @HiveField(29)
  pickupOtpReset, // admin reset OTP
  @HiveField(30)
  pickupConfirmed, // successful OTP pickup
  @HiveField(31)
  pickupAttemptFailed, // wrong OTP entered
  @HiveField(32)
  pickupLockedOut, // max attempts exceeded
  @HiveField(33)
  qrNonceRotated, // nonce rotated after failed attempt
  // Item-level
  @HiveField(34)
  propertyItemCreated,
  @HiveField(35)
  propertyItemDeferred, // item deferred to next trip
  // Trip
  @HiveField(36)
  tripCreated, // explicit trip creation record
  @HiveField(37)
  tripUpdated, // route/checkpoint edits
  // Receiver / tracking
  @HiveField(38)
  trackingCodeGenerated,
  @HiveField(39)
  receiverNotificationsEnabled,
  @HiveField(40)
  receiverNotificationQueued,
  @HiveField(41)
  receiverNotificationSent,
  @HiveField(42)
  receiverNotificationFailed,
  // User sync (Phase 6)
  @HiveField(43)
  userCreated,
  @HiveField(44)
  userUpdated,
  // User deletion (appended — never reorder above)
  @HiveField(45)
  userDeleted,
}