import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/notification_item.dart';
import '../../models/outbound_message.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/notification_service.dart';
import '../../services/outbound_message_service.dart';
import '../../services/role_guard.dart';
import '../../services/session.dart';
import '../../widgets/logout_button.dart';

import '../admin/admin_active_trips_screen.dart';
import '../admin/admin_audit_screen.dart';
import '../admin/admin_create_user_screen.dart';
import '../admin/admin_exceptions_screen.dart';
import '../admin/admin_payments_screen.dart';
import '../admin/admin_performance_screen.dart';
import '../admin/admin_properties_screen.dart';
import '../admin/admin_reports_screen.dart';
import '../admin/admin_trips_screen.dart';
import '../admin/admin_users_screen.dart';
import '../admin/admin_outbound_messages_screen.dart';

import '../common/outbound_messages_screen.dart';
import '../common/notifications_screen.dart';
import '../common/tracking_lookup_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // UI guard (admin only)
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.60);

    Widget sectionTitle(String text) {
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Divider(thickness: 1, height: 1, color: muted.withValues(alpha: 0.35)),
          ],
        ),
      );
    }

    Widget actionButton({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
      Widget? trailing,
    }) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: Icon(icon),
          label: Row(
            children: [
              Expanded(child: Text(label)),
              if (trailing != null) trailing,
            ],
          ),
          onPressed: onPressed,
        ),
      );
    }

    Widget badgePill({
      required String text,
      Color? bg,
      Color? fg,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (bg ?? cs.error).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: fg ?? cs.onError,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
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
            // Notifications with unread badge (theme-safe)
            ValueListenableBuilder(
              valueListenable: HiveService.notificationBox().listenable(),
              builder: (context, Box box, _) {
                final userId = Session.currentUserId!;
                final unreadCount = box.values.where((n) {
                  final ni = n as NotificationItem;
                  final isForAdminInbox =
                      ni.targetUserId == NotificationService.adminInbox;
                  final isForThisAdmin = ni.targetUserId == userId;
                  return (isForAdminInbox || isForThisAdmin) && !ni.isRead;
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
                            color: cs.error,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            style: TextStyle(
                              color: cs.onError,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
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
            sectionTitle('Operations'),
            actionButton(
              icon: Icons.inventory_2_outlined,
              label: 'All Properties',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminPropertiesScreen(),
                  ),
                );
              },
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

            sectionTitle('Finance'),
            actionButton(
              icon: Icons.payments_outlined,
              label: 'Payments',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminPaymentsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            actionButton(
              icon: Icons.insights_outlined,
              label: 'Reports',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminReportsScreen()),
                );
              },
            ),

            sectionTitle('Users'),
            actionButton(
              icon: Icons.person_add,
              label: 'Create User',
              onPressed: () async {
                final createdUser = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminCreateUserScreen(),
                  ),
                );

                if (createdUser != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User created ✅')),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            actionButton(
              icon: Icons.people_outline,
              label: 'Manage Users',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
                );
              },
            ),

            sectionTitle('Monitoring'),
            actionButton(
              icon: Icons.history,
              label: 'Audit Log',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminAuditScreen()),
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
            const SizedBox(height: 10),

            sectionTitle('Outbound'),
            // SMS Processing (queued + failed badge)
            ValueListenableBuilder(
              valueListenable: HiveService.outboundMessageBox().listenable(),
              builder: (context, Box box, _) {
                final pendingSms = box.values
                    .whereType<OutboundMessage>()
                    .where((m) {
                      final ch = m.channel.trim().toLowerCase();
                      if (ch != 'sms') return false;
                      final st = m.status.trim().toLowerCase();
                      return st == OutboundMessageService.statusQueued ||
                          st == OutboundMessageService.statusFailed;
                    })
                    .length;

                return actionButton(
                  icon: Icons.sms_outlined,
                  label: 'SMS Processing',
                  trailing: pendingSms > 0
                      ? badgePill(text: pendingSms > 99 ? '99+' : '$pendingSms')
                      : null,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OutboundMessagesScreen(
                          channelFilter: 'sms',
                          title: 'SMS Processing',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 10),

            // Outbound Messages button with SMS queued/failed badge
            ValueListenableBuilder(
              valueListenable: HiveService.outboundMessageBox().listenable(),
              builder: (context, Box<OutboundMessage> b, _) {
                int queuedSms = 0;
                int failedSms = 0;

                for (final m in b.values) {
                  final ch = m.channel.trim().toLowerCase();
                  if (ch != 'sms') continue;

                  final st = m.status.trim().toLowerCase();
                  if (st == OutboundMessageService.statusQueued) queuedSms++;
                  if (st == OutboundMessageService.statusFailed) failedSms++;
                }

                final show = queuedSms > 0 || failedSms > 0;

                return actionButton(
                  icon: Icons.outbox_outlined,
                  label: 'Outbound Messages',
                  trailing: show
                      ? badgePill(
                          text:
                              'SMS ${queuedSms.clamp(0, 99)}/${failedSms.clamp(0, 99)}',
                        )
                      : null,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminOutboundMessagesScreen(),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 10),

            sectionTitle('Lookup'),
            actionButton(
              icon: Icons.search,
              label: 'Tracking Lookup',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TrackingLookupScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // subtle footer
            Text(
              'Tip: Keep SMS queue near zero to avoid delayed receiver updates.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}