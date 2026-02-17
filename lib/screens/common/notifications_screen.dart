import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/notification_item.dart';
import '../../services/hive_service.dart';
import '../../services/notification_service.dart';
import '../../services/session.dart';
import '../../models/user_role.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final box = HiveService.notificationBox();
    final userId = Session.currentUserId!;
    final role = Session.currentRole;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Notifications'),
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<NotificationItem> box, _) {
          final items = box.values.where((n) {
            // Always show notifications targeted to this user
            if (n.targetUserId == userId) return true;

            // Admin also sees "admin inbox"
            if (role == UserRole.admin &&
                n.targetUserId == NotificationService.adminInbox) {
              return true;
            }

            return false;
          }).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (items.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final n = items[index];

              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(
                    n.title,
                    style: TextStyle(
                      fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(n.message),
                  trailing: Text(
                    n.createdAt.toLocal().toString().substring(0, 16),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    if (n.isRead) return; // ✅ do nothing if already read
                    n.isRead = true;
                    await n.save();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
