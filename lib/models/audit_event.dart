import 'package:hive/hive.dart';

part 'audit_event.g.dart';

@HiveType(typeId: 1)
class AuditEvent extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime at;

  @HiveField(2)
  final String? actorUserId;

  @HiveField(3)
  final String? actorRole;

  @HiveField(4)
  final String action;

  @HiveField(5)
  final String? propertyKey;

  @HiveField(6)
  final String? tripId;

  @HiveField(7)
  final String? details;

  AuditEvent({
    required this.id,
    required this.at,
    required this.action,
    this.actorUserId,
    this.actorRole,
    this.propertyKey,
    this.tripId,
    this.details,
  });
}
