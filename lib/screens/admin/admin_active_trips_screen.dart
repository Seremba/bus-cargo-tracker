import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/trip.dart';
import '../../models/trip_status.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/role_guard.dart';
import 'admin_trip_details_screen.dart';

class AdminActiveTripsScreen extends StatelessWidget {
  const AdminActiveTripsScreen({super.key});

  Widget _notAuthorized() =>
      const Scaffold(body: Center(child: Text('Not authorized')));

  String _tripStatusText(TripStatus s) {
    switch (s) {
      case TripStatus.active:
        return '🟢 Active';
      case TripStatus.ended:
        return '✅ Ended';
      case TripStatus.cancelled:
        return '⛔ Cancelled';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) return _notAuthorized();

    final box = HiveService.tripBox();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Active Trips'),
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<Trip> box, _) {
          final trips = box.values.toList()
            ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

          final activeTrips = trips
              .where((t) => t.status == TripStatus.active)
              .toList();

          if (activeTrips.isEmpty) {
            return const Center(child: Text('No active trips right now.'));
          }

          return ListView.builder(
            itemCount: activeTrips.length,
            itemBuilder: (context, index) {
              final t = activeTrips[index];

              final lastIndex = t.lastCheckpointIndex;
              final lastName =
                  (lastIndex >= 0 && lastIndex < t.checkpoints.length)
                  ? t.checkpoints[lastIndex].name
                  : 'Not started checkpoints';

              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(t.routeName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Driver: ${t.driverUserId}'),
                      Text('Status: ${_tripStatusText(t.status)}'),
                      Text('Last checkpoint: $lastName'),
                      Text(
                        'Started: ${t.startedAt.toLocal().toString().substring(0, 16)}',
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (!RoleGuard.hasRole(UserRole.admin)) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminTripDetailsScreen(trip: t),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
