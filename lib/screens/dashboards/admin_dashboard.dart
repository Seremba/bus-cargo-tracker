import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/notification_item.dart';
import '../../models/outbound_message.dart';
import '../../models/property_status.dart';
import '../../models/sync_event.dart';
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
import '../admin/sms_settings_screen.dart';

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

  String _fmtAmount(int n) {
    if (n >= 1000000) {
      final m = n / 1000000;
      return '${m.toStringAsFixed(m.truncateToDouble() == m ? 0 : 1)}M';
    }
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}K';
    }
    return n.toString();
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
            HiveService.paymentBox().listenable(),
            HiveService.outboundMessageBox().listenable(),
          ]),
          builder: (context, _) {
            final now = DateTime.now();
            final todayStart = DateTime(now.year, now.month, now.day);

            // ── KPI calculations ──────────────────────────────────────
            final allProperties = HiveService.propertyBox().values.toList();
            final allPayments = HiveService.paymentBox().values.toList();
            final allTrips = HiveService.tripBox().values.toList();
            final outboundBox = HiveService.outboundMessageBox();

            // Revenue today
            final todayRevenue = allPayments
                .where((p) => p.createdAt.isAfter(todayStart))
                .fold(0, (sum, p) => sum + p.amount);

            // Active trips
            final activeTrips = allTrips
                .where((t) => t.status == TripStatus.active)
                .length;

            // Pending pickup (delivered but not picked up)
            final pendingPickup = allProperties
                .where((p) => p.status == PropertyStatus.delivered)
                .length;

            // Unpaid properties (pending status, no payment)
            final unpaidProps = allProperties
                .where(
                  (p) =>
                      p.status == PropertyStatus.pending &&
                      p.amountPaidTotal == 0,
                )
                .length;

            // In transit
            final inTransit = allProperties
                .where((p) => p.status == PropertyStatus.inTransit)
                .length;

            // SMS failed
            final smsFailed = outboundBox.values
                .whereType<OutboundMessage>()
                .where(
                  (m) =>
                      m.channel.trim().toLowerCase() == 'sms' &&
                      m.status.trim().toLowerCase() ==
                          OutboundMessageService.statusFailed,
                )
                .length;

            // Total properties
            final totalProperties = allProperties.length;

            // Staff count
            final totalUsers = HiveService.userBox().values
                .where((u) => u.role != UserRole.sender)
                .length;

            final outboundMsgs = outboundBox.values
                .whereType<OutboundMessage>()
                .toList();

            int queuedSms = 0;
            int failedSms = 0;
            int pendingSms = 0;
            for (final m in outboundMsgs) {
              if (m.channel.trim().toLowerCase() != 'sms') continue;
              final st = m.status.trim().toLowerCase();
              if (st == OutboundMessageService.statusQueued) queuedSms++;
              if (st == OutboundMessageService.statusFailed) failedSms++;
              if (st == OutboundMessageService.statusQueued ||
                  st == OutboundMessageService.statusFailed) {
                pendingSms++;
              }
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // ── KPI cards ──────────────────────────────────────────
                _kpiSectionLabel(cs),
                const SizedBox(height: 12),

                // Revenue — full width hero card
                _kpiHeroCard(
                  context: context,
                  icon: Icons.payments_outlined,
                  label: 'Revenue today',
                  value: 'UGX ${_fmtAmount(todayRevenue)}',
                  sublabel: 'Tap to view all payments',
                  color: Colors.green,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminPaymentsScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Row 1: Active trips + In transit
                Row(
                  children: [
                    Expanded(
                      child: _kpiCard(
                        context: context,
                        icon: Icons.local_shipping_outlined,
                        label: 'Active trips',
                        value: '$activeTrips',
                        color: Colors.blue,
                        alert: activeTrips == 0,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminActiveTripsScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _kpiCard(
                        context: context,
                        icon: Icons.directions_bus_outlined,
                        label: 'In transit',
                        value: '$inTransit',
                        color: Colors.blue.shade700,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminPropertiesScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Row 2: Pending pickup + Total properties
                Row(
                  children: [
                    Expanded(
                      child: _kpiCard(
                        context: context,
                        icon: Icons.lock_outline,
                        label: 'Pending pickup',
                        value: '$pendingPickup',
                        color: Colors.teal,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminPropertiesScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _kpiCard(
                        context: context,
                        icon: Icons.inventory_2_outlined,
                        label: 'Total properties',
                        value: '$totalProperties',
                        color: cs.primary,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminPropertiesScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Row 3: Unpaid cargo + SMS failed
                Row(
                  children: [
                    Expanded(
                      child: _kpiCard(
                        context: context,
                        icon: Icons.warning_amber_outlined,
                        label: 'Unpaid cargo',
                        value: '$unpaidProps',
                        color: Colors.amber.shade700,
                        alert: unpaidProps > 0,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminPropertiesScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _kpiCard(
                        context: context,
                        icon: Icons.sms_failed_outlined,
                        label: 'SMS failed',
                        value: '$smsFailed',
                        color: Colors.red,
                        alert: smsFailed > 0,
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
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ── Phase 6: Sync status strip (replaces plain last-synced text) ──
                _SyncStatusStrip(
                  lastSynced: _lastSynced,
                  syncing: _syncing,
                  onSyncTap: _runSync,
                ),

                const SizedBox(height: 14),

                // ── Action sections ────────────────────────────────────
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
                      subtitle: 'Twilio credentials and configuration',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SmsSettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),

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

  // ── KPI section label ───────────────────────────────────────────────────
  Widget _kpiSectionLabel(ColorScheme cs) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.dashboard_outlined, size: 17, color: cs.primary),
        const SizedBox(width: 6),
        const Text(
          'Overview',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ── Full-width hero KPI card (revenue) ──────────────────────────────────
  Widget _kpiHeroCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.40),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withValues(alpha: 0.50)),
          ],
        ),
      ),
    );
  }

  // ── Standard KPI card ────────────────────────────────────────────────────
  Widget _kpiCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool alert = false,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: alert
                ? color.withValues(alpha: 0.50)
                : cs.outlineVariant.withValues(alpha: 0.40),
            width: alert ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                if (alert)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Phase 6: Sync status strip ─────────────────────────────────────────────
//
// Replaces the plain "Last synced: ..." text with a reactive strip that
// shows pending + failed counts from the live Hive sync event box.
// Stays compact — single row, no card chrome — so it doesn't compete
// with the KPI section above it.

class _SyncStatusStrip extends StatelessWidget {
  final DateTime? lastSynced;
  final bool syncing;
  final VoidCallback onSyncTap;

  const _SyncStatusStrip({
    required this.lastSynced,
    required this.syncing,
    required this.onSyncTap,
  });

  String _fmtRelative(DateTime? d) {
    if (d == null) return 'Not synced yet';
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return ValueListenableBuilder<Box<SyncEvent>>(
      valueListenable: HiveService.syncEventBox().listenable(),
      builder: (context, box, _) {
        final events = box.values.toList();
        final pendingCount = events
            .where((e) => e.pendingPush && !e.pushed)
            .length;
        final failedCount = events
            .where((e) => e.pushAttempts > 0 && !e.pushed)
            .length;

        final hasFailures = failedCount > 0;
        final hasPending = pendingCount > 0;

        final statusColor = hasFailures
            ? Colors.red.shade600
            : hasPending
            ? Colors.amber.shade700
            : Colors.green.shade600;

        final statusIcon = hasFailures
            ? Icons.sync_problem_outlined
            : hasPending
            ? Icons.sync_outlined
            : Icons.check_circle_outline;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: statusColor.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: 7),
              Expanded(
                child: Wrap(
                  spacing: 10,
                  children: [
                    Text(
                      _fmtRelative(lastSynced),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    if (hasPending)
                      Text(
                        '$pendingCount pending',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (hasFailures)
                      Text(
                        '$failedCount failed — will retry',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: syncing ? null : onSyncTap,
                child: AnimatedOpacity(
                  opacity: syncing ? 0.4 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      syncing
                          ? SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: cs.primary,
                              ),
                            )
                          : Icon(Icons.sync, size: 13, color: cs.primary),
                      const SizedBox(width: 3),
                      Text(
                        syncing ? 'Syncing…' : 'Sync now',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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