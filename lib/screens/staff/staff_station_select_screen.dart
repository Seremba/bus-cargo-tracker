import 'package:flutter/material.dart';

import '../../models/staff_station_mode.dart';
import '../../models/user_role.dart';
import '../../services/role_guard.dart';
import '../../services/session.dart';
import 'staff_station_screen.dart';

class StaffStationSelectScreen extends StatelessWidget {
  final StaffStationMode mode;
  const StaffStationSelectScreen({super.key, required this.mode});

  static const stations = <String>[
    'Kampala',
    'Masaka',
    'Mbarara',
    'Kabale',
    'Katuna Border',
    'Kigali',
  ];

  @override
  Widget build(BuildContext context) {
    // ✅ UI guard: staff/admin only
    if (!RoleGuard.hasAny({UserRole.staff, UserRole.admin})) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final role = Session.currentRole;
    final assigned = (Session.currentStationName ?? '').trim();

    // If staff (not admin) already has a station, skip selection screen
    if (role == UserRole.staff && assigned.isNotEmpty) {
      return StaffStationScreen(mode: mode);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Select Station')),
      body: ListView.builder(
        itemCount: stations.length,
        itemBuilder: (context, i) {
          final name = stations[i];
          return ListTile(
            title: Text(name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Session.currentStationName = name;

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => StaffStationScreen(mode: mode),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
