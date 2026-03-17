import 'package:bus_cargo_tracker/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/notification_item.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/notification_service.dart';
import '../../services/session.dart';


class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static String _fmt16(DateTime d) =>
      d.toLocal().toString().substring(0, 16);

  @override
  Widget build(BuildContext context) {
    final box = HiveService.notificationBox();
    final userId = Session.currentUserId!;
    final role = Session.currentRole;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: ValueListenableBuilder(
          valueListenable: box.listenable(),
          builder: (context, Box<NotificationItem> b, _) {
            final unread = b.values.where((n) {
              if (n.targetUserId == userId) return !n.isRead;
              if (role == UserRole.admin &&
                  n.targetUserId == NotificationService.adminInbox) {
                return !n.isRead;
              }
              return false;
            }).length;
            return Text(
              unread > 0 ? 'Notifications ($unread)' : 'Notifications',
            );
          },
        ),
        actions: [
          ValueListenableBuilder(
            valueListenable: box.listenable(),
            builder: (context, Box<NotificationItem> b, _) {
              final hasUnread = b.values.any((n) {
                if (!n.isRead && n.targetUserId == userId) return true;
                if (!n.isRead &&
                    role == UserRole.admin &&
                    n.targetUserId == NotificationService.adminInbox) {
                  return true;
                }
                return false;
              });
              if (!hasUnread) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Mark all as read',
                icon: const Icon(Icons.done_all_outlined),
                onPressed: () async {
                  for (final n in b.values) {
                    if (n.isRead) continue;
                    if (n.targetUserId == userId ||
                        (role == UserRole.admin &&
                            n.targetUserId ==
                                NotificationService.adminInbox)) {
                      n.isRead = true;
                      await n.save();
                    }
                  }
                },
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<NotificationItem> b, _) {
          final items = b.values.where((n) {
            if (n.targetUserId == userId) return true;
            if (role == UserRole.admin &&
                n.targetUserId == NotificationService.adminInbox) {
              return true;
            }
            return false;
          }).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.notifications_none_outlined,
                      size: 16, color: Colors.black38),
                  SizedBox(width: 8),
                  Text(
                    'No notifications yet.',
                    style:
                        TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            itemCount: items.length,
            itemBuilder: (context, index) =>
                _notifTile(context, items[index]),
          );
        },
      ),
    );
  }

  Widget _notifTile(BuildContext context, NotificationItem n) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final isUnread = !n.isRead;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      // Unread notifications get a subtle primary tint
      color: isUnread
          ? AppColors.primary.withValues(alpha: 0.06)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          if (n.isRead) return;
          n.isRead = true;
          await n.save();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Notification icon avatar ──
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isUnread
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : cs.surfaceContainerHighest
                          .withValues(alpha: 0.40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isUnread
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none_outlined,
                  size: 20,
                  color: isUnread ? AppColors.primary : muted,
                ),
              ),
              const SizedBox(width: 12),

              // ── Content ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + unread dot
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isUnread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (isUnread) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Message
                    Text(
                      n.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isUnread
                            ? cs.onSurface.withValues(alpha: 0.75)
                            : muted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Timestamp
                    Row(
                      children: [
                        Icon(Icons.access_time_outlined,
                            size: 11, color: muted),
                        const SizedBox(width: 3),
                        Text(
                          _fmt16(n.createdAt),
                          style:
                              TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}