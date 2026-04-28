import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/routes.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../services/hive_service.dart';
import '../../services/role_guard.dart';
import '../../services/sync_service.dart';
import '../../models/sync_event_type.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _search = TextEditingController();
  UserRole? _roleFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
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

  /// Verification badge — shown for senders and staff/drivers who use OTP login.
  /// Admins are always verified and don't need a badge.
  Widget _verifiedBadge(bool phoneVerified) {
    if (phoneVerified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.verified_outlined, size: 10, color: Color(0xFF2E7D32)),
            SizedBox(width: 3),
            Text(
              'Verified',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2E7D32),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.warning_amber_outlined, size: 10, color: Color(0xFFE65100)),
          SizedBox(width: 3),
          Text(
            'Unverified',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE65100),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final box = HiveService.userBox();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Users')),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<User> b, _) {
          final q = _search.text.trim().toLowerCase();

          final allUsers = b.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final filtered = allUsers.where((u) {
            final matchesSearch =
                q.isEmpty ||
                u.fullName.toLowerCase().contains(q) ||
                u.phone.toLowerCase().contains(q);
            final matchesRole = _roleFilter == null || u.role == _roleFilter;
            return matchesSearch && matchesRole;
          }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search by name or phone',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.30),
                  suffixIcon: q.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _filterChip('All', null, cs),
                          const SizedBox(width: 6),
                          _filterChip('Staff', UserRole.staff, cs),
                          const SizedBox(width: 6),
                          _filterChip('Driver', UserRole.driver, cs),
                          const SizedBox(width: 6),
                          _filterChip(
                            'Desk Officer',
                            UserRole.deskCargoOfficer,
                            cs,
                          ),
                          const SizedBox(width: 6),
                          _filterChip('Sender', UserRole.sender, cs),
                          const SizedBox(width: 6),
                          _filterChip('Admin', UserRole.admin, cs),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${filtered.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No users found.',
                    style: TextStyle(color: muted),
                  ),
                ),

              for (final u in filtered) _userCard(u, cs, muted),
            ],
          );
        },
      ),
    );
  }

  Widget _filterChip(String label, UserRole? role, ColorScheme cs) {
    final selected = _roleFilter == role;
    return GestureDetector(
      onTap: () => setState(() => _roleFilter = role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary
              : cs.surfaceContainerHighest.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.50),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _userCard(User u, ColorScheme cs, Color muted) {
    final style = _roleStyle(u.role);
    final initials = _initials(u.fullName);
    final station = u.stationName?.trim() ?? '';
    final route = u.assignedRouteName?.trim() ?? '';
    final canSetStation =
        u.role == UserRole.staff || u.role == UserRole.deskCargoOfficer;
    final canEditDriverRoute = u.role == UserRole.driver;
    final canDelete = u.role != UserRole.admin;
    final isSender = u.role == UserRole.sender;
    // Admins are implicitly always verified — no badge needed
    final showVerifiedBadge = u.role != UserRole.admin;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSender
                    ? cs.onSurface.withValues(alpha: 0.08)
                    : style.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: isSender ? muted : style.fg,
                ),
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Name + role chip ──────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          u.fullName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: isSender
                                ? cs.onSurface.withValues(alpha: 0.70)
                                : cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: style.bg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          style.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: style.fg,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // ── Verified / Unverified badge ───────────────────────
                  if (showVerifiedBadge) ...[
                    _verifiedBadge(u.phoneVerified),
                    const SizedBox(height: 3),
                  ],

                  Text(u.phone, style: TextStyle(fontSize: 12, color: muted)),

                  if (station.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          station,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ],

                  if (u.role == UserRole.driver && route.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.route_outlined, size: 12, color: muted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            route,
                            style: TextStyle(fontSize: 12, color: muted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 2),

                  Text(
                    'Joined ${u.createdAt.toLocal().toString().substring(0, 10)}',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),

            PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: Icon(Icons.more_vert, color: muted),
              onSelected: (v) {
                if (!mounted) return;
                if (!RoleGuard.hasRole(UserRole.admin)) return;
                if (v == 'reset_pw') _resetPasswordFlow(u);
                if (v == 'set_station') _setStationFlow(u);
                if (v == 'edit_route') _editDriverRoute(u);
                if (v == 'delete') _deleteUserFlow(u);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'reset_pw',
                  child: Row(
                    children: [
                      Icon(Icons.lock_reset_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Reset password'),
                    ],
                  ),
                ),
                if (canSetStation)
                  const PopupMenuItem(
                    value: 'set_station',
                    child: Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Set station'),
                      ],
                    ),
                  ),
                if (canEditDriverRoute)
                  const PopupMenuItem(
                    value: 'edit_route',
                    child: Row(
                      children: [
                        Icon(Icons.route_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Edit route'),
                      ],
                    ),
                  ),
                if (canDelete) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Delete user',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Delete user flow ───────────────────────────────────────────────────────

  Future<void> _deleteUserFlow(User u) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;
    if (u.role == UserRole.admin) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete user?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Theme.of(context).colorScheme.onSurface,
                  decoration: TextDecoration.none,
                  fontFamily: null,
                ),
                children: [
                  const TextSpan(text: 'Are you sure you want to delete '),
                  TextSpan(
                    text: u.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '? This action cannot be undone.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.20)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 16,
                    color: Colors.red.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The user will be removed from all devices on next sync.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    try {
      await HiveService.userBox().delete(u.id);

      await SyncService.enqueue(
        type: SyncEventType.userDeleted,
        aggregateType: 'user',
        aggregateId: u.id,
        actorUserId: u.id,
        payload: {'userId': u.id},
        aggregateVersion: 1,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${u.fullName} deleted ✅'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete user: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // ── Reset password flow ────────────────────────────────────────────────────

  Future<void> _resetPasswordFlow(User u) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;

    final c = TextEditingController();
    bool hidePass = true;

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text(
              'Reset password\n${u.fullName}',
              style: const TextStyle(fontSize: 15),
            ),
            content: TextField(
              controller: c,
              obscureText: hidePass,
              decoration: InputDecoration(
                labelText: 'New temporary password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    hidePass
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setLocal(() => hidePass = !hidePass),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
      );

      if (!mounted || ok != true) return;

      final pw = c.text.trim();
      if (pw.length < 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password too short (min 4)')),
        );
        return;
      }

      final success = await AuthService.adminResetPassword(
        userId: u.id,
        newPassword: pw,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Password reset ✅' : 'Failed ❌')),
      );
    } finally {
      c.dispose();
    }
  }

  // ── Set station flow ───────────────────────────────────────────────────────

  Future<void> _setStationFlow(User u) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;
    if (u.role != UserRole.staff && u.role != UserRole.deskCargoOfficer) return;

    final c = TextEditingController(text: u.stationName ?? '');
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(
            'Set station\n${u.fullName}',
            style: const TextStyle(fontSize: 15),
          ),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Station name',
              hintText: 'e.g. Kampala, Juba',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (!mounted || ok != true) return;

      final station = c.text.trim();
      if (station.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Station cannot be empty')),
        );
        return;
      }

      final success = await AuthService.adminUpdateUserStation(
        userId: u.id,
        stationName: station,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Station updated ✅' : 'Failed ❌')),
      );
    } finally {
      c.dispose();
    }
  }

  // ── Edit driver route flow ─────────────────────────────────────────────────

  Future<void> _editDriverRoute(User user) async {
    if (user.role != UserRole.driver) return;

    AppRoute? selectedRoute = routes.firstWhere(
      (r) => r.id == user.assignedRouteId,
      orElse: () => routes.first,
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            'Edit route\n${user.fullName}',
            style: const TextStyle(fontSize: 15),
          ),
          content: DropdownButtonFormField<AppRoute>(
            initialValue: selectedRoute,
            decoration: const InputDecoration(
              labelText: 'Assigned Route',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.route_outlined),
            ),
            items: routes
                .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                .toList(),
            onChanged: (v) => setLocal(() => selectedRoute = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedRoute == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || selectedRoute == null) return;

    final ok = await AuthService.adminUpdateDriverAssignedRoute(
      userId: user.id,
      assignedRouteId: selectedRoute!.id,
      assignedRouteName: selectedRoute!.name,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Driver route updated ✅' : 'Failed to update driver route ❌',
        ),
      ),
    );
  }
}