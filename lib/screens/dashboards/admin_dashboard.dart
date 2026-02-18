import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../common/notifications_screen.dart';
import '../admin/admin_properties_screen.dart';
import '../admin/admin_active_trips_screen.dart';
import '../admin/admin_trips_screen.dart';
import '../admin/admin_create_user_screen.dart';
import '../admin/admin_users_screen.dart';
import '../admin/admin_reports_screen.dart';

import '../../models/notification_item.dart';
import '../../services/hive_service.dart';
import '../../services/notification_service.dart';
import '../../services/session.dart';
import '../../widgets/logout_button.dart';

import '../../services/role_guard.dart';
import '../../models/user_role.dart';
import '../admin/admin_audit_screen.dart';
import '../admin/admin_performance_screen.dart';
import '../admin/admin_exceptions_screen.dart';
import '../admin/admin_payments_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ UI guard (admin only)
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    Widget actionButton({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
    }) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          icon: Icon(icon),
          label: Text(label),
          onPressed: onPressed,
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          elevation: 2,
          title: const Text('Admin Dashboard'),
          actions: [
            ValueListenableBuilder(
              valueListenable: HiveService.notificationBox().listenable(),
              builder: (context, Box<NotificationItem> box, _) {
                final userId = Session.currentUserId!;
                final unreadCount = box.values.where((n) {
                  final isForAdminInbox =
                      n.targetUserId == NotificationService.adminInbox;
                  final isForThisAdmin = n.targetUserId == userId;
                  return (isForAdminInbox || isForThisAdmin) && !n.isRead;
                }).length;

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
        body: ListView(
          padding: const EdgeInsets.all(16),
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
                      builder: (_) => const AdminPropertiesScreen(),
                    ),
                  );
                },
                child: const Text('All Properties'),
              ),
            ),
            const SizedBox(height: 10),

            // ✅ NEW: Reports
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.insights),
                label: const Text('Reports'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminReportsScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Payments'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminPaymentsScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.history),
                label: const Text('Audit Log'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminAuditScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.person_add),
                label: const Text('Create User'),
                onPressed: () async {
                  final createdUser = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminCreateUserScreen(),
                    ),
                  );

                  // If AdminCreateUserScreen pops(user), we can optionally show a small confirmation here.
                  if (createdUser != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User created ✅')),
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminUsersScreen(),
                      ),
                    );
                  }
                },
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.people),
                label: const Text('Manage Users'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            actionButton(
              icon: Icons.route_outlined,
              label: 'Trips',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminTripsScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            actionButton(
              icon: Icons.local_shipping_outlined,
              label: 'Active Trips',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminActiveTripsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            actionButton(
              icon: Icons.speed_outlined,
              label: 'Performance',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminPerformanceScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            actionButton(
              icon: Icons.report_problem_outlined,
              label: 'Exceptions',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminExceptionsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
