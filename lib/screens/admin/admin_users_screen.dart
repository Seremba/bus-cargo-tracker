import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/routes.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../services/hive_service.dart';
import '../../services/role_guard.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _search = TextEditingController();
  UserRole? _roleFilter; // null = all roles

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // Initials from full name e.g. "Mbaziira Godfrey" → "MG"
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  // Role chip style
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
                  // Scrollable role filter chips
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
                  // User count badge
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

    // De-emphasise sender cards slightly
    final isSender = u.role == UserRole.sender;

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
                  // Row: name + role chip
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
                      // Role chip
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

                  const SizedBox(height: 3),

                  // Phone
                  Text(u.phone, style: TextStyle(fontSize: 12, color: muted)),

                  // Station — only shown when present
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

                  // Route — only shown for drivers when present
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

                  // Created date
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
              ],
            ),
          ],
        ),
      ),
    );
  }

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
            value: selectedRoute,
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
