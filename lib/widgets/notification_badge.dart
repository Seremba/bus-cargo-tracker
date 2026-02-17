import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/notification_item.dart';
import '../services/hive_service.dart';
import '../services/session.dart';

class NotificationBadgeIcon extends StatelessWidget {
  final VoidCallback onTap;
  const NotificationBadgeIcon({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final box = HiveService.notificationBox();
    final userId = Session.currentUserId ?? '';

    return ValueListenableBuilder(
      valueListenable: box.listenable(),
      builder: (context, Box<NotificationItem> b, _) {
        final unread = b.values.where((n) {
          return n.targetUserId == userId && n.isRead == false;
        }).length;

        return InkWell(
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.notifications_none),
              ),
              if (unread > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : unread.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
