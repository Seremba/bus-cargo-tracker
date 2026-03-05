import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/notification_item.dart';

import '../../services/hive_service.dart';
import '../../services/session.dart';

import '../../widgets/logout_button.dart';
import '../common/notifications_screen.dart';
import 'register_property_screen.dart';
import 'my_properties_screen.dart';

class SenderDashboard extends StatelessWidget {
  const SenderDashboard({super.key});

  static const int _recentLimit = 3; // ✅ set to 4 if you prefer

  String _name() {
    final t = (Session.currentUserFullName ?? '').trim();
    return t.isEmpty ? 'Sender' : t;
  }

  String _statusText(Property p) {
    final raw = p.status.toString();
    final s = raw.contains('.') ? raw.split('.').last : raw;
    return s.trim().isEmpty ? '—' : s.trim();
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
                userName, // ✅ Name first, bigger
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
            final muted = Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.65);

            final userId = (Session.currentUserId ?? '').trim();

            final myProps =
                userId.isEmpty
                      ? <Property>[]
                      : box.values.where((p) {
                          final createdBy = (p.createdByUserId ?? '').trim();
                          return createdBy == userId;
                        }).toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

            final recent = myProps.take(_recentLimit).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              children: [
                // ✅ Keep welcome card but make it lighter + smaller
                _welcomeCard(context, userName),

                const SizedBox(height: 14),

                // ✅ Primary action (kept “nice”)
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

                // ✅ Secondary action (calmer)
                _actionCard(
                  context,
                  title: 'My Properties',
                  subtitle: 'Track status, payments, and QR',
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

                const SizedBox(height: 18),

                // Recent header
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
                      'No properties yet. Tap “Register Property” to start.',
                      style: TextStyle(color: muted),
                    ),
                  ),

                const SizedBox(height: 6),

                // ✅ Recent tiles (still nice, but less heavy)
                for (final p in recent) _recentTile(context, p, _statusText),
              ],
            );
          },
        ),
      ),
    );
  }

  static Widget _welcomeCard(BuildContext context, String userName) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.65);

    return Container(
      padding: const EdgeInsets.all(14), // ✅ slightly smaller
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35), // ✅ lighter
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.50), // ✅ soft border
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // smaller icon block
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.person, color: cs.primary),
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
          // ✅ add soft outline for secondary card (makes it “nice” but calm)
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
                    Text(subtitle, style: TextStyle(color: sub)),
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

  static Widget _recentTile(
    BuildContext context,
    Property p,
    String Function(Property) statusTextFn,
  ) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.65);

    final receiver = (p.receiverName ?? '').trim().isEmpty
        ? 'Receiver'
        : p.receiverName!.trim();

    final route = (p.routeName ?? '').trim().isEmpty
        ? '—'
        : p.routeName!.trim();

    final code = (p.propertyCode ?? '').trim();
    final codeText = code.isEmpty ? '—' : code;
    final itemCount = p.itemCount < 0 ? 0 : p.itemCount;

    final status = statusTextFn(p);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.28), // ✅ lighter
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        title: Text(
          receiver,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$codeText • Items: $itemCount',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                'Route: $route',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: cs.primary,
            ),
          ),
        ),
      ),
    );
  }
}
