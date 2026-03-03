import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/notification_item.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/notification_service.dart';
import '../../services/session.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static String _fmt16(DateTime d) => d.toLocal().toString().substring(0, 16);

  @override
  Widget build(BuildContext context) {
    final box = HiveService.notificationBox();
    final userId = Session.currentUserId!;
    final role = Session.currentRole;

    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.60);

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
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final n = items[index];

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: TextStyle(
                            fontWeight:
                                n.isRead ? FontWeight.w600 : FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!n.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      n.message,
                      style: TextStyle(color: muted),
                    ),
                  ),
                  trailing: Text(
                    _fmt16(n.createdAt),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  onTap: () async {
                    if (n.isRead) return; 
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