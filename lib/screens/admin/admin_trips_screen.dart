import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/trip.dart';
import '../../models/trip_status.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/role_guard.dart';
import 'admin_trip_details_screen.dart';

class AdminTripsScreen extends StatelessWidget {
  const AdminTripsScreen({super.key});

  Widget _notAuthorized() =>
      const Scaffold(body: Center(child: Text('Not authorized')));

  String _statusText(TripStatus s) {
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

    final tripBox = HiveService.tripBox();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          elevation: 2,
          title: const Text('Trips'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Ended'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: ValueListenableBuilder(
          valueListenable: tripBox.listenable(),
          builder: (context, Box<Trip> box, _) {
            final allTrips = box.values.toList()
              ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

            List<Trip> byStatus(TripStatus s) =>
                allTrips.where((t) => t.status == s).toList();

            Widget buildList(List<Trip> trips) {
              if (trips.isEmpty) {
                return const Center(child: Text('No trips here yet.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: trips.length,
                itemBuilder: (context, index) {
                  final t = trips[index];

                  final i = t.lastCheckpointIndex;
                  final lastCheckpoint = (i >= 0 && i < t.checkpoints.length)
                      ? t.checkpoints[i].name
                      : 'No checkpoint reached yet';

                  final started = t.startedAt.toLocal().toString().substring(
                    0,
                    16,
                  );

                  final endedText = (t.endedAt != null)
                      ? ' • Ended: ${t.endedAt!.toLocal().toString().substring(0, 16)}'
                      : '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(t.routeName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('Driver: ${t.driverUserId}'),
                          Text('Status: ${_statusText(t.status)}'),
                          Text('Started: $started$endedText'),
                          Text('Last checkpoint: $lastCheckpoint'),
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
            }

            return TabBarView(
              children: [
                buildList(byStatus(TripStatus.active)),
                buildList(byStatus(TripStatus.ended)),
                buildList(byStatus(TripStatus.cancelled)),
              ],
            );
          },
        ),
      ),
    );
  }
}
