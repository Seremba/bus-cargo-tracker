import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/trip.dart';
import '../../models/trip_status.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/role_guard.dart';
import 'admin_trip_details_screen.dart';

import '../../theme/status_colors.dart';
import '../../widgets/status_chip.dart';

import '../../ui/status_labels.dart';

class AdminActiveTripsScreen extends StatelessWidget {
  const AdminActiveTripsScreen({super.key});

  Widget _notAuthorized() =>
      const Scaffold(body: Center(child: Text('Not authorized')));

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

          final muted = Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.60);

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: activeTrips.length,
            itemBuilder: (context, index) {
              final t = activeTrips[index];

              final lastIndex = t.lastCheckpointIndex;
              final lastName =
                  (lastIndex >= 0 && lastIndex < t.checkpoints.length)
                  ? t.checkpoints[lastIndex].name
                  : 'No checkpoint reached yet';

              final bg = TripStatusColors.background(t.status);
              final fg = TripStatusColors.foreground(t.status);

              final started = t.startedAt.toLocal().toString().substring(0, 16);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.routeName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(
                        text: TripStatusLabels.text(t.status),
                        bgColor: bg,
                        fgColor: fg,
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Driver: ${t.driverUserId}'),
                        Text('Last checkpoint: $lastName'),
                        Text(
                          'Started: $started',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
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
