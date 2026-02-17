import 'package:flutter/material.dart';
import 'register_property_screen.dart';
import 'my_properties_screen.dart';
import '../../services/session.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../common/notifications_screen.dart';
import '../../models/notification_item.dart';
import '../../services/hive_service.dart';
import '../../widgets/logout_button.dart';


class SenderDashboard extends StatelessWidget {
  const SenderDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          elevation: 2,
          title: const Text('Sender Dashboard'),
          actions: [
            ValueListenableBuilder(
              valueListenable: HiveService.notificationBox().listenable(),
              builder: (context, Box<NotificationItem> box, _) {
                final userId = Session.currentUserId!;
                final unreadCount = box.values
                    .where((n) => n.targetUserId == userId && !n.isRead)
                    .length;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Notifications',
                      icon: const Icon(Icons.notifications_none),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        );
                      },
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

            const LogoutButton(),

          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RegisterPropertyScreen(),
                      ),
                    );
                  },
                  child: const Text('Register Property'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MyPropertiesScreen(),
                      ),
                    );
                  },
                  child: const Text('My Properties'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
