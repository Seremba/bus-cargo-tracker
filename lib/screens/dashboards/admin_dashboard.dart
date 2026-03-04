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
    final muted = cs.onSurface.withValues(alpha: 0.65);

    final adminName = (Session.currentUserFullName ?? 'Admin').trim();

    Widget badgePill({required String text, Color? bg, Color? fg}) {
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
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      );
    }

    Widget sectionCard({
      required String title,
      required List<Widget> children,
      IconData? icon,
    }) {
      return Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: muted),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );
    }

    Widget actionTile({
      required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        if ((subtitle ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    trailing,
                    const SizedBox(width: 10),
                  ],
                  Icon(Icons.chevron_right, color: muted),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          elevation: 1,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Admin Dashboard',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(adminName, style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
          actions: [
            // Notifications with unread badge (theme-safe)
            ValueListenableBuilder(
              valueListenable: HiveService.notificationBox().listenable(),
              builder: (context, Box box, _) {
                final userId = Session.currentUserId;
                final unreadCount = box.values.where((n) {
                  final ni = n as NotificationItem;
                  final isForAdminInbox =
                      ni.targetUserId == NotificationService.adminInbox;
                  final isForThisAdmin =
                      (userId != null && ni.targetUserId == userId);
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
                              fontWeight: FontWeight.w900,
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
            sectionCard(
              title: 'Operations',
              icon: Icons.settings_outlined,
              children: [
                actionTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'All Properties',
                  subtitle: 'View, search, and manage cargo',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminPropertiesScreen(),
                      ),
                    );
                  },
                ),
                actionTile(
                  icon: Icons.route_outlined,
                  title: 'Trips',
                  subtitle: 'Create + manage trips and routes',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminTripsScreen(),
                      ),
                    );
                  },
                ),
                actionTile(
                  icon: Icons.local_shipping_outlined,
                  title: 'Active Trips',
                  subtitle: 'Trips currently in progress',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminActiveTripsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            sectionCard(
              title: 'Finance',
              icon: Icons.payments_outlined,
              children: [
                actionTile(
                  icon: Icons.payments_outlined,
                  title: 'Payments',
                  subtitle: 'Review and export payments',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminPaymentsScreen(),
                      ),
                    );
                  },
                ),
                actionTile(
                  icon: Icons.insights_outlined,
                  title: 'Reports',
                  subtitle: 'Totals and performance reports',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminReportsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            sectionCard(
              title: 'Users',
              icon: Icons.people_outline,
              children: [
                actionTile(
                  icon: Icons.person_add,
                  title: 'Create User',
                  subtitle: 'Add staff, driver, desk officer',
                  onTap: () async {
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
                actionTile(
                  icon: Icons.people_outline,
                  title: 'Manage Users',
                  subtitle: 'Edit roles and stations',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminUsersScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            sectionCard(
              title: 'Monitoring',
              icon: Icons.monitor_heart_outlined,
              children: [
                actionTile(
                  icon: Icons.history,
                  title: 'Audit Log',
                  subtitle: 'All critical actions (traceability)',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminAuditScreen(),
                      ),
                    );
                  },
                ),
                actionTile(
                  icon: Icons.speed_outlined,
                  title: 'Performance',
                  subtitle: 'App health and usage signals',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminPerformanceScreen(),
                      ),
                    );
                  },
                ),
                actionTile(
                  icon: Icons.report_problem_outlined,
                  title: 'Exceptions',
                  subtitle: 'Errors captured for review',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminExceptionsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            sectionCard(
              title: 'Outbound',
              icon: Icons.outbox_outlined,
              children: [
                ValueListenableBuilder(
                  valueListenable: HiveService.outboundMessageBox()
                      .listenable(),
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

                    return actionTile(
                      icon: Icons.sms_outlined,
                      title: 'SMS Processing',
                      subtitle: 'Open, mark sent/failed, requeue stale',
                      trailing: pendingSms > 0
                          ? badgePill(
                              text: pendingSms > 99 ? '99+' : '$pendingSms',
                            )
                          : null,
                      onTap: () {
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
                ValueListenableBuilder(
                  valueListenable: HiveService.outboundMessageBox()
                      .listenable(),
                  builder: (context, Box b, _) {
                    int queuedSms = 0;
                    int failedSms = 0;

                    for (final m in b.values.whereType<OutboundMessage>()) {
                      final ch = m.channel.trim().toLowerCase();
                      if (ch != 'sms') continue;
                      final st = m.status.trim().toLowerCase();
                      if (st == OutboundMessageService.statusQueued) {
                        queuedSms++;
                      }
                      if (st == OutboundMessageService.statusFailed) {
                        failedSms++;
                      }
                    }

                    final show = queuedSms > 0 || failedSms > 0;

                    return actionTile(
                      icon: Icons.outbox_outlined,
                      title: 'Outbound Messages (Admin)',
                      subtitle: 'Full queue visibility and management',
                      trailing: show
                          ? badgePill(
                              text:
                                  'SMS ${queuedSms.clamp(0, 99)}/${failedSms.clamp(0, 99)}',
                              bg: cs.primary,
                              fg: cs.onPrimary,
                            )
                          : null,
                      onTap: () {
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
              ],
            ),
            sectionCard(
              title: 'Lookup',
              icon: Icons.search,
              children: [
                actionTile(
                  icon: Icons.search,
                  title: 'Tracking Lookup',
                  subtitle: 'Search status by tracking code',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TrackingLookupScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Tip: Keep SMS queue near zero to avoid delayed receiver updates.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
