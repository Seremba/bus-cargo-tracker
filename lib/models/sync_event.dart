import 'package:hive/hive.dart';

import 'sync_event_type.dart';

part 'sync_event.g.dart';

@HiveType(typeId: 17)
class SyncEvent extends HiveObject {
  @HiveField(0)
  final String eventId;

  @HiveField(1)
  final SyncEventType type;

  /// Entity family: property, trip, payment, otp, notification, exception
  @HiveField(2)
  final String aggregateType;

  @HiveField(3)
  final String aggregateId;

  @HiveField(4)
  final String actorUserId;

  @HiveField(5)
  final Map<String, dynamic> payload;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7, defaultValue: true)
  bool pendingPush;

  @HiveField(8, defaultValue: false)
  bool pushed;

  @HiveField(9, defaultValue: false)
  bool appliedLocally;

  @HiveField(10)
  String? remoteCursor;

  @HiveField(11, defaultValue: 0)
  int pushAttempts;

  @HiveField(12)
  DateTime? lastPushAttemptAt;

  @HiveField(13, defaultValue: '')
  String lastError;

  @HiveField(14, defaultValue: '')
  String sourceDeviceId;

  SyncEvent({
    required this.eventId,
    required this.type,
    required this.aggregateType,
    required this.aggregateId,
    required this.actorUserId,
    required Map<String, dynamic> payload,
    required this.createdAt,
    this.pendingPush = true,
    this.pushed = false,
    this.appliedLocally = false,
    this.remoteCursor,
    this.pushAttempts = 0,
    this.lastPushAttemptAt,
    String? lastError,
    String? sourceDeviceId,
  }) : payload = Map<String, dynamic>.from(payload),
       lastError = (lastError ?? '').trim(),
       sourceDeviceId = (sourceDeviceId ?? '').trim();
}
