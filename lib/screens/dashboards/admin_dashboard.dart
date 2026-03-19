import 'package:bus_cargo_tracker/screens/admin/at_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/notification_item.dart';
import '../../models/outbound_message.dart';
import '../../models/trip.dart';
import '../../models/trip_status.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';

import '../../services/hive_service.dart';
import '../../services/notification_service.dart';
import '../../services/outbound_message_service.dart';
import '../../services/role_guard.dart';
import '../../services/session.dart';
import '../../services/sync_service.dart';

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

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _syncing = false;
  DateTime? _lastSynced;

  Future<void> _runSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      final result = await SyncService.syncNow();
      if (!mounted) return;
      setState(() => _lastSynced = DateTime.now());
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync complete. '
            'Pushed: ${result.pushed}, '
            'Pulled: ${result.pulled}, '
            'Applied: ${result.applied}, '
            'Failed: ${result.failed}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _fmtSynced(DateTime? d) {
    if (d == null) return 'Not synced yet';
    final s = d.toLocal().toString();
    return 'Last synced: ${s.length >= 16 ? s.substring(0, 16) : s}';
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final adminName = (Session.currentUserFullName ?? 'Admin').trim();

    Widget badgePill({required String text, Color? bg, Color? fg}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (bg ?? cs.error).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: fg ?? cs.onError,
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        ),
      );
    }

    Widget countBadge(String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.w700,
            fontSize: 11,
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: cs.primary),
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
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 4),
              // Interleave tiles with subtle dividers
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    indent: 52,
                    color: cs.outlineVariant.withValues(alpha: 0.40),
                  ),
              ],
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
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
                if (trailing != null) ...[trailing, const SizedBox(width: 8)],
                Icon(Icons.chevron_right, color: muted, size: 20),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          elevation: 1,
          centerTitle: false,
          titleSpacing: 16,
          // Fixed: use left-aligned column title so it never truncates
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Admin',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  height: 1.1,
                ),
              ),
              Text(adminName, style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
          actions: [
            // Sync button with tooltip showing last synced time
            Tooltip(
              message: _fmtSynced(_lastSynced),
              child: IconButton(
                onPressed: _syncing ? null : _runSync,
                icon: _syncing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : const Icon(Icons.sync),
              ),
            ),
            // Notification bell with unread badge
            ValueListenableBuilder(
              valueListenable: HiveService.notificationBox().listenable(),
              builder: (context, Box box, _) {
                final userId = Session.currentUserId;
                final unreadCount = box.values.where((n) {
                  final ni = n as NotificationItem;
                  final isForAdminInbox =
                      ni.targetUserId == NotificationService.adminInbox;
                  final isForThisAdmin =
                      userId != null && ni.targetUserId == userId;
                  return (isForAdminInbox || isForThisAdmin) && !ni.isRead;
                }).length;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Notifications',
                      icon: const Icon(Icons.notifications_none),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      ),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cs.error,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
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
            const SizedBox(width: 4),
          ],
        ),
        body: AnimatedBuilder(
          animation: Listenable.merge([
            HiveService.propertyBox().listenable(),
            HiveService.tripBox().listenable(),
            HiveService.userBox().listenable(),
            HiveService.outboundMessageBox().listenable(),
          ]),
          builder: (context, _) {
            // Live counts for badges
            final allProperties = HiveService.propertyBox().values;
            final totalProperties = allProperties.length;
            final activeTrips = HiveService.tripBox().values
                .where((t) => (t as Trip).status == TripStatus.active)
                .length;
            final totalUsers = HiveService.userBox().values
                .where((u) => (u as User).role != UserRole.sender)
                .length;

            final outboundBox = HiveService.outboundMessageBox();
            final pendingSms = outboundBox.values
                .whereType<OutboundMessage>()
                .where((m) {
                  final ch = m.channel.trim().toLowerCase();
                  if (ch != 'sms') return false;
                  final st = m.status.trim().toLowerCase();
                  return st == OutboundMessageService.statusQueued ||
                      st == OutboundMessageService.statusFailed;
                })
                .length;

            int queuedSms = 0;
            int failedSms = 0;
            for (final m in outboundBox.values.whereType<OutboundMessage>()) {
              if (m.channel.trim().toLowerCase() != 'sms') continue;
              final st = m.status.trim().toLowerCase();
              if (st == OutboundMessageService.statusQueued) queuedSms++;
              if (st == OutboundMessageService.statusFailed) failedSms++;
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Last synced timestamp strip
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(Icons.sync, size: 13, color: muted),
                      const SizedBox(width: 6),
                      Text(
                        _fmtSynced(_lastSynced),
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),

                sectionCard(
                  title: 'Operations',
                  icon: Icons.settings_outlined,
                  children: [
                    actionTile(
                      icon: Icons.inventory_2_outlined,
                      title: 'All Properties',
                      subtitle: 'View, search, and manage cargo',
                      trailing: totalProperties > 0
                          ? countBadge('$totalProperties')
                          : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminPropertiesScreen(),
                        ),
                      ),
                    ),
                    actionTile(
                      icon: Icons.route_outlined,
                      title: 'Trips',
                      subtitle: 'Create + manage trips and routes',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminTripsScreen(),
                        ),
                      ),
                    ),
                    actionTile(
                      icon: Icons.local_shipping_outlined,
                      title: 'Active Trips',
                      subtitle: 'Trips currently in progress',
                      trailing: activeTrips > 0
                          ? countBadge('$activeTrips active')
                          : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminActiveTripsScreen(),
                        ),
                      ),
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
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminPaymentsScreen(),
                        ),
                      ),
                    ),
                    actionTile(
                      icon: Icons.insights_outlined,
                      title: 'Reports',
                      subtitle: 'Totals and performance reports',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminReportsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),

                sectionCard(
                  title: 'Users',
                  icon: Icons.people_outline,
                  children: [
                    actionTile(
                      icon: Icons.person_add_outlined,
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
                      icon: Icons.manage_accounts_outlined,
                      title: 'Manage Users',
                      subtitle: 'Edit roles and stations',
                      trailing: totalUsers > 0
                          ? countBadge('$totalUsers staff')
                          : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminUsersScreen(),
                        ),
                      ),
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
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminAuditScreen(),
                        ),
                      ),
                    ),
                    actionTile(
                      icon: Icons.speed_outlined,
                      title: 'Performance',
                      subtitle: 'App health and usage signals',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminPerformanceScreen(),
                        ),
                      ),
                    ),
                    actionTile(
                      icon: Icons.report_problem_outlined,
                      title: 'Exceptions',
                      subtitle: 'Errors captured for review',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminExceptionsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),

                sectionCard(
                  title: 'Outbound',
                  icon: Icons.outbox_outlined,
                  children: [
                    actionTile(
                      icon: Icons.sms_outlined,
                      title: 'SMS Processing',
                      subtitle: 'Open, mark sent/failed, requeue stale',
                      trailing: pendingSms > 0
                          ? badgePill(
                              text: pendingSms > 99 ? '99+' : '$pendingSms',
                            )
                          : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OutboundMessagesScreen(
                            channelFilter: 'sms',
                            title: 'SMS Processing',
                          ),
                        ),
                      ),
                    ),
                    actionTile(
                      icon: Icons.outbox_outlined,
                      title: 'Outbound Messages',
                      subtitle: 'Full queue visibility and management',
                      trailing: (queuedSms > 0 || failedSms > 0)
                          ? badgePill(
                              text:
                                  '${queuedSms.clamp(0, 99)}Q / ${failedSms.clamp(0, 99)}F',
                              bg: cs.primary,
                              fg: cs.onPrimary,
                            )
                          : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminOutboundMessagesScreen(),
                        ),
                      ),
                    ),
                    actionTile(
                      icon: Icons.settings_outlined,
                      title: 'SMS Settings',
                      subtitle: 'Africa\'s Talking API key and sender ID',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AtSettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Lookup ───────────────────────────────────────────────
                sectionCard(
                  title: 'Lookup',
                  icon: Icons.search,
                  children: [
                    actionTile(
                      icon: Icons.manage_search_outlined,
                      title: 'Tracking Lookup',
                      subtitle: 'Search status by tracking code',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TrackingLookupScreen(),
                        ),
                      ),
                    ),
                  ],
                ),

                // Footer tip
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 14, color: muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Keep SMS queue near zero to avoid delayed receiver updates.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
