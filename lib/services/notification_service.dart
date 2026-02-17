import '../models/notification_item.dart';
import 'hive_service.dart';

class NotificationService {
  static const String adminInbox = 'ADMIN_INBOX';

  static Future<void> notify({
    required String targetUserId,
    required String title,
    required String message,
  }) async {
    final box = HiveService.notificationBox();
    final item = NotificationItem(
      targetUserId: targetUserId,
      title: title,
      message: message,
      createdAt: DateTime.now(),
      isRead: false,
    );
    await box.add(item);
  }
}
