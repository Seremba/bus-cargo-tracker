import 'package:hive/hive.dart';

part 'notification_item.g.dart';

@HiveType(typeId: 3) // ✅ unique typeId (0=Property, 1=PropertyStatus)
class NotificationItem extends HiveObject {
  @HiveField(0)
  final String targetUserId; // who should see it (senderId or ADMIN_INBOX)

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String message;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  bool isRead;

  NotificationItem({
    required this.targetUserId,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isRead = false,
  });
}
