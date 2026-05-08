import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';

class AdminUserDetailScreen extends StatelessWidget {
  final User user;
  const AdminUserDetailScreen({super.key, required this.user});

  static String _fmt10(DateTime d) =>
      d.toLocal().toString().substring(0, 10);

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied ✅')));
  }

  static ({String label, Color bg, Color fg}) _roleStyle(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return (
          label: 'Admin',
          bg: const Color(0xFFEDE7F6),
          fg: const Color(0xFF4527A0),
        );
      case UserRole.staff:
        return (
          label: 'Staff',
          bg: const Color(0xFFE3F2FD),
          fg: const Color(0xFF1565C0),
        );
      case UserRole.driver:
        return (
          label: 'Driver',
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF2E7D32),
        );
      case UserRole.deskCargoOfficer:
        return (
          label: 'Desk Officer',
          bg: const Color(0xFFFFF3E0),
          fg: const Color(0xFFE65100),
        );
      case UserRole.sender:
        return (
          label: 'Sender',
          bg: const Color(0xFFF3E5F5),
          fg: const Color(0xFF6A1B9A),
        );
    }
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final userBox = HiveService.userBox();
    final propertyBox = HiveService.propertyBox();

    return AnimatedBuilder(
      animation: Listenable.merge([
        userBox.listenable(),
        propertyBox.listenable(),
      ]),
      builder: (context, _) {
        // Always read the freshest copy from the box.
        final u = userBox.get(user.id) ?? user;
        final style = _roleStyle(u.role);
        final initials = _initials(u.fullName);
        final isSender = u.role == UserRole.sender;
        final cs = Theme.of(context).colorScheme;
        final muted = cs.onSurface.withValues(alpha: 0.55);

        // Sender-specific: count properties created by this user
        final List<Property> senderProperties = isSender
            ? (propertyBox.values
                .whereType<Property>()
                .where((p) => p.createdByUserId == u.id)
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
            : [];

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            elevation: 2,
            title: Text(u.fullName.trim().isEmpty ? 'User Details' : u.fullName),
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // ── Avatar + role ─────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: isSender
                            ? cs.onSurface.withValues(alpha: 0.08)
                            : style.bg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: isSender ? muted : style.fg,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: style.bg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        style.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: style.fg,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (u.role != UserRole.admin)
                      _verifiedBadge(u.phoneVerified),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Profile card ──────────────────────────────────────────
              _sectionCard(children: [
                _sectionTitle('Profile'),
                const SizedBox(height: 10),
                _row('Full Name',
                    u.fullName.trim().isEmpty ? '—' : u.fullName),
                _row(
                  'Phone',
                  u.phone.trim().isEmpty ? '—' : u.phone,
                  onCopy: () => _copy(context, 'Phone', u.phone),
                ),
                _row(
                  'User ID',
                  u.id.trim().isEmpty ? '—' : u.id,
                  onCopy: () => _copy(context, 'User ID', u.id),
                ),
                _row('Joined', _fmt10(u.createdAt)),
                _row(
                  'Verification',
                  u.role == UserRole.admin
                      ? 'Admin (always verified)'
                      : u.phoneVerified
                          ? '✅ Phone verified'
                          : '⚠️ Phone not verified',
                ),
              ]),

              const SizedBox(height: 10),

              // ── Assignment card (staff / desk / driver) ───────────────
              if (u.role == UserRole.staff ||
                  u.role == UserRole.deskCargoOfficer ||
                  u.role == UserRole.driver) ...[
                _sectionCard(children: [
                  _sectionTitle('Assignment'),
                  const SizedBox(height: 10),
                  if (u.role == UserRole.staff ||
                      u.role == UserRole.deskCargoOfficer)
                    _row(
                      'Station',
                      (u.stationName ?? '').trim().isEmpty
                          ? '— not assigned'
                          : u.stationName!.trim(),
                    ),
                  if (u.role == UserRole.driver) ...[
                    _row(
                      'Route',
                      (u.assignedRouteName ?? '').trim().isEmpty
                          ? '— not assigned'
                          : u.assignedRouteName!.trim(),
                    ),
                    _row(
                      'Route ID',
                      (u.assignedRouteId ?? '').trim().isEmpty
                          ? '—'
                          : u.assignedRouteId!.trim(),
                    ),
                    if (u.awaitingReassignment) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz,
                                size: 16, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This driver has completed their last trip and is awaiting route reassignment.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ]),
                const SizedBox(height: 10),

              ],

                // ── Route History ─────────────────────────────────────────
                if (u.role == UserRole.driver &&
                    u.routeHistory.isNotEmpty) ...[
                  _sectionCard(children: [
                    _sectionTitle(
                        'Route History (${u.routeHistory.length})'),
                    const SizedBox(height: 8),
                    for (int i = u.routeHistory.length - 1; i >= 0; i--)
                      _routeHistoryRow(
                          u.routeHistory[i], i, u.routeHistory.length, muted),
                  ]),
                  const SizedBox(height: 10),
                ],

              // ── Sender properties ─────────────────────────────────────
              if (isSender) ...[
                _sectionCard(children: [
                  _sectionTitle('Properties (${senderProperties.length})'),
                  const SizedBox(height: 8),
                  if (senderProperties.isEmpty)
                    const Text(
                      'No properties registered by this sender.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    )
                  else
                    for (final p in senderProperties.take(30))
                      _propertyRow(p, muted),
                  if (senderProperties.length > 30) ...[
                    const SizedBox(height: 6),
                    Text(
                      '+ ${senderProperties.length - 30} more',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ]),
                const SizedBox(height: 10),
              ],

              // ── Account info ──────────────────────────────────────────
              _sectionCard(children: [
                _sectionTitle('Account'),
                const SizedBox(height: 10),
                _row(
                  'Password set',
                  u.passwordHash.trim().isEmpty ? 'No (shell account)' : 'Yes',
                ),
                _row(
                  'Role',
                  style.label,
                ),
              ]),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _routeHistoryRow(
      Map entry, int index, int total, Color muted) {
    final routeName = (entry['routeName'] ?? '—').toString();
    final assignedAt = entry['assignedAt'] != null
        ? DateTime.tryParse(entry['assignedAt'].toString())
        : null;
    final endedAt = entry['endedAt'] != null
        ? DateTime.tryParse(entry['endedAt'].toString())
        : null;
    final isLatest = index == total - 1;

    String fmt(DateTime? d) =>
        d == null ? '—' : d.toLocal().toString().substring(0, 10);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isLatest
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.route_outlined,
                  size: 14,
                  color: isLatest ? Colors.green : Colors.grey,
                ),
              ),
              if (index > 0)
                Container(
                  width: 2,
                  height: 20,
                  color: Colors.grey.withValues(alpha: 0.25),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  routeName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isLatest ? Colors.green : null,
                  ),
                ),
                Text(
                  endedAt != null
                      ? '${fmt(assignedAt)} → ${fmt(endedAt)}'
                      : 'From ${fmt(assignedAt)}',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    );
  }

  Widget _row(String label, String value, {VoidCallback? onCopy}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          if (onCopy != null)
            GestureDetector(
              onTap: onCopy,
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.copy_outlined,
                    size: 15, color: Colors.black38),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _verifiedBadge(bool verified) {
    if (verified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.verified_outlined, size: 11, color: Color(0xFF2E7D32)),
            SizedBox(width: 4),
            Text(
              'Verified',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E7D32)),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFFE65100).withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.warning_amber_outlined,
              size: 11, color: Color(0xFFE65100)),
          SizedBox(width: 4),
          Text(
            'Unverified',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE65100)),
          ),
        ],
      ),
    );
  }

  Widget _propertyRow(Property p, Color muted) {
    final statusColors = <PropertyStatus, Color>{
      PropertyStatus.pending: const Color(0xFFF57F17),
      PropertyStatus.loaded: const Color(0xFFE65100),
      PropertyStatus.inTransit: const Color(0xFF1565C0),
      PropertyStatus.delivered: const Color(0xFF2E7D32),
      PropertyStatus.pickedUp: const Color(0xFF1B5E20),
      PropertyStatus.rejected: const Color(0xFFC62828),
      PropertyStatus.expired: const Color(0xFF4E342E),
      PropertyStatus.underReview: const Color(0xFFFF8F00),
    };
    final statusLabels = <PropertyStatus, String>{
      PropertyStatus.pending: 'Pending',
      PropertyStatus.loaded: 'Loaded',
      PropertyStatus.inTransit: 'In Transit',
      PropertyStatus.delivered: 'Delivered',
      PropertyStatus.pickedUp: 'Picked Up',
      PropertyStatus.rejected: 'Rejected',
      PropertyStatus.expired: 'Expired',
      PropertyStatus.underReview: 'Under Review',
    };
    final color = statusColors[p.status] ?? Colors.grey;
    final label = statusLabels[p.status] ?? p.status.name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.receiverName.trim().isEmpty ? '—' : p.receiverName,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${p.propertyCode.trim().isEmpty ? '' : '${p.propertyCode}  •  '}'
                  '${p.destination.trim().isEmpty ? '—' : p.destination}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }
}