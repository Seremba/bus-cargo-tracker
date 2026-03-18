import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/notification_item.dart';

import '../../services/hive_service.dart';
import '../../services/session.dart';

import '../../widgets/logout_button.dart';
import '../common/notifications_screen.dart';
import 'register_property_screen.dart';
import 'my_properties_screen.dart';

class SenderDashboard extends StatelessWidget {
  const SenderDashboard({super.key});

  static const int _recentLimit = 3;

  String _name() {
    final t = (Session.currentUserFullName ?? '').trim();
    return t.isEmpty ? 'Sender' : t;
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  static ({String label, Color bg, Color fg}) _statusStyle(
    PropertyStatus status,
  ) {
    switch (status) {
      case PropertyStatus.pending:
        return (
          label: 'Pending',
          bg: const Color(0xFFFFF8E1),
          fg: const Color(0xFFF57F17),
        );
      case PropertyStatus.loaded:
        return (
          label: 'Loaded',
          bg: const Color(0xFFFFF3E0),
          fg: const Color(0xFFE65100),
        );
      case PropertyStatus.inTransit:
        return (
          label: 'In Transit',
          bg: const Color(0xFFE3F2FD),
          fg: const Color(0xFF1565C0),
        );
      case PropertyStatus.delivered:
        return (
          label: 'Delivered',
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF2E7D32),
        );
      case PropertyStatus.pickedUp:
        return (
          label: 'Picked Up',
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF1B5E20),
        );
      case PropertyStatus.rejected:
        return (
          label: 'Rejected',
          bg: const Color(0xFFFFEBEE),
          fg: const Color(0xFFC62828),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userName = _name();
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          centerTitle: false,
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                userName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Sender Dashboard',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
          actions: [
            ValueListenableBuilder(
              valueListenable: HiveService.notificationBox().listenable(),
              builder: (context, Box<NotificationItem> box, _) {
                final userId = (Session.currentUserId ?? '').trim();
                final unreadCount = userId.isEmpty
                    ? 0
                    : box.values
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
            const SizedBox(width: 6),
          ],
        ),

        body: ValueListenableBuilder(
          valueListenable: HiveService.propertyBox().listenable(),
          builder: (context, Box<Property> box, _) {
            final muted = cs.onSurface.withValues(alpha: 0.65);
            final userId = (Session.currentUserId ?? '').trim();

            final myProps =
                userId.isEmpty
                    ? <Property>[]
                    : box.values
                          .where((p) => p.createdByUserId.trim() == userId)
                          .toList()
                      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

            final recent = myProps.take(_recentLimit).toList();

            // Active = pending/loaded/inTransit — rejected is not active
            final activeCount = myProps.where((p) {
              return p.status == PropertyStatus.pending ||
                  p.status == PropertyStatus.loaded ||
                  p.status == PropertyStatus.inTransit;
            }).length;

            // F1: count rejected so we can surface an alert
            final rejectedCount = myProps.where((p) {
              return p.status == PropertyStatus.rejected;
            }).length;

            final totalCount = myProps.length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              children: [
                _welcomeCard(context, userName, activeCount, rejectedCount),

                const SizedBox(height: 14),

                _actionCard(
                  context,
                  title: 'Register Property',
                  subtitle: 'Create a property code + QR',
                  icon: Icons.add_box_outlined,
                  filled: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RegisterPropertyScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                _actionCard(
                  context,
                  title: 'My Properties',
                  subtitle: totalCount == 0
                      ? 'Track status, payments, and QR'
                      : '$totalCount propert${totalCount == 1 ? 'y' : 'ies'} • tap to view all',
                  icon: Icons.inventory_2_outlined,
                  filled: false,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MyPropertiesScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 22),

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recent',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MyPropertiesScreen(),
                          ),
                        );
                      },
                      child: const Text('View all'),
                    ),
                  ],
                ),

                if (recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No properties yet. Tap "Register Property" to start.',
                      style: TextStyle(color: muted),
                    ),
                  ),

                const SizedBox(height: 6),

                for (final p in recent) _recentTile(context, p),
              ],
            );
          },
        ),
      ),
    );
  }

  static Widget _welcomeCard(
    BuildContext context,
    String userName,
    int activeCount,
    int rejectedCount,
  ) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.65);
    final initials = _initials(userName);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.50),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                color: cs.onPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome,', style: TextStyle(color: muted)),
                const SizedBox(height: 2),
                Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                if (rejectedCount > 0)
                  Text(
                    '$rejectedCount propert${rejectedCount == 1 ? 'y' : 'ies'} rejected — tap to view',
                    style: const TextStyle(
                      color: Color(0xFFC62828),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (activeCount > 0)
                  Text(
                    '$activeCount active shipment${activeCount == 1 ? '' : 's'} in progress',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    'Register cargo and keep track of your properties.',
                    style: TextStyle(color: muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _actionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    final bg = filled ? cs.primary : cs.surface;
    final fg = filled ? cs.onPrimary : cs.onSurface;
    final sub = filled
        ? cs.onPrimary.withValues(alpha: 0.85)
        : cs.onSurface.withValues(alpha: 0.65);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: filled
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.60),
                  ),
                ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: sub, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _recentTile(BuildContext context, Property p) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.65);

    final receiver = p.receiverName.trim().isEmpty
        ? 'Receiver'
        : p.receiverName.trim();
    final route = p.routeName.trim().isEmpty ? '—' : p.routeName.trim();
    final destination =
        p.destination.trim().isEmpty ? '—' : p.destination.trim();
    final code = p.propertyCode.trim().isEmpty ? '—' : p.propertyCode.trim();
    final itemCount = p.itemCount < 0 ? 0 : p.itemCount;
    final style = _statusStyle(p.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                receiver,
                style: const TextStyle(fontWeight: FontWeight.w900),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: style.bg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                style.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: style.fg,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📍 $destination',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                '$code  •  $itemCount item${itemCount == 1 ? '' : 's'}',
                style: TextStyle(color: muted, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Route: $route',
                style: TextStyle(color: muted, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}