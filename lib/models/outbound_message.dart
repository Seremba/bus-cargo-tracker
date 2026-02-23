import 'package:hive/hive.dart';

part 'outbound_message.g.dart';

@HiveType(typeId: 13) // If 12 is already used, change to a free typeId.
class OutboundMessage extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String toPhone;

  @HiveField(2, defaultValue: 'whatsapp')
  final String channel; // whatsapp / sms

  @HiveField(3)
  final String body;

  @HiveField(4, defaultValue: 'queued')
  String status; // queued / sent / failed

  @HiveField(5, defaultValue: 0)
  int attempts;

  @HiveField(6)
  DateTime? lastAttemptAt;

  @HiveField(7, defaultValue: '')
  final String propertyKey;

  @HiveField(8)
  final DateTime createdAt;

  OutboundMessage({
    required this.id,
    required this.toPhone,
    required this.channel,
    required this.body,
    required this.createdAt,
    required this.propertyKey,
    this.status = 'queued',
    this.attempts = 0,
    this.lastAttemptAt,
  });
}