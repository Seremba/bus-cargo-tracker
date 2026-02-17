import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _notAuthorized() =>
      const Scaffold(body: Center(child: Text('Not authorized')));

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) return _notAuthorized();

    final box = HiveService.userBox();

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Users')),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<User> b, _) {
          final q = _search.text.trim().toLowerCase();

          final users = b.values.where((u) {
            if (q.isEmpty) return true;
            return u.fullName.toLowerCase().contains(q) ||
                u.phone.toLowerCase().contains(q);
          }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Search by name or phone',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              if (users.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No users found.'),
                ),
              for (final u in users) _userCard(u),
            ],
          );
        },
      ),
    );
  }

  Widget _userCard(User u) {
    final roleLabel = _roleLabel(u.role);
    final station = u.stationName?.trim();
    final stationText = (station == null || station.isEmpty) ? '—' : station;

    final canSetStation =
        u.role == UserRole.staff || u.role == UserRole.deskCargoOfficer;

    return Card(
      child: ListTile(
        title: Text(u.fullName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${u.phone} • $roleLabel'),
            const SizedBox(height: 4),
            Text('Station: $stationText', style: const TextStyle(fontSize: 12)),
            Text(
              'Created: ${u.createdAt.toLocal().toString().substring(0, 16)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Actions',
          onSelected: (v) {
            if (!mounted) return;
            if (!RoleGuard.hasRole(UserRole.admin)) return;

            if (v == 'reset_pw') _resetPasswordFlow(u);
            if (v == 'set_station') _setStationFlow(u);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'reset_pw',
              child: Text('Reset password'),
            ),
            PopupMenuItem(
              value: 'set_station',
              enabled: canSetStation,
              child: Text(
                canSetStation ? 'Set station' : 'Set station (staff/desk only)',
              ),
            ),
          ],
          child: const Icon(Icons.more_vert),
        ),
      ),
    );
  }

  String _roleLabel(UserRole r) {
    switch (r) {
      case UserRole.sender:
        return 'Sender';
      case UserRole.staff:
        return 'Staff';
      case UserRole.driver:
        return 'Driver';
      case UserRole.admin:
        return 'Admin';
      case UserRole.deskCargoOfficer:
        return 'Desk Cargo Officer';
    }
  }

  Future<void> _resetPasswordFlow(User u) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;

    final c = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reset password'),
          content: TextField(
            controller: c,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New temporary password',
              border: OutlineInputBorder(),
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
      );

      if (!mounted) return;
      if (ok != true) return;

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

    // allow staff + desk officer
    if (u.role != UserRole.staff && u.role != UserRole.deskCargoOfficer) return;

    final c = TextEditingController(text: u.stationName ?? '');
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Set station'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Station name',
              border: OutlineInputBorder(),
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

      if (!mounted) return;
      if (ok != true) return;

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
}
