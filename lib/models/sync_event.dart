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
  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'type': type.name,
      'aggregateType': aggregateType,
      'aggregateId': aggregateId,
      'actorUserId': actorUserId,
      'payload': Map<String, dynamic>.from(payload),
      'createdAt': createdAt.toIso8601String(),
      'remoteCursor': remoteCursor,
      'sourceDeviceId': sourceDeviceId,
    };
  }

  static SyncEvent fromJson(Map<String, dynamic> json) {
    return SyncEvent(
      eventId: (json['eventId'] ?? '').toString(),
      type: SyncEventType.values.byName((json['type'] ?? '').toString()),
      aggregateType: (json['aggregateType'] ?? '').toString(),
      aggregateId: (json['aggregateId'] ?? '').toString(),
      actorUserId: (json['actorUserId'] ?? '').toString(),
      payload: Map<String, dynamic>.from(
        (json['payload'] as Map?) ?? const <String, dynamic>{},
      ),
      createdAt: DateTime.parse((json['createdAt'] ?? '').toString()),
      pendingPush: false,
      pushed: true,
      appliedLocally: false,
      remoteCursor: json['remoteCursor']?.toString(),
      sourceDeviceId: (json['sourceDeviceId'] ?? '').toString(),
    );
  }
}
