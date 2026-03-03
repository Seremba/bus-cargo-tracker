import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/trip.dart';
import '../../models/trip_status.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/role_guard.dart';

import '../../theme/status_colors.dart';
import '../../widgets/status_chip.dart';
import '../../ui/status_labels.dart';

import 'admin_trip_details_screen.dart';

class AdminTripsScreen extends StatelessWidget {
  const AdminTripsScreen({super.key});

  Widget _notAuthorized() =>
      const Scaffold(body: Center(child: Text('Not authorized')));

  static String _fmt16(DateTime? d) {
    if (d == null) return '—';
    return d.toLocal().toString().substring(0, 16);
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) return _notAuthorized();

    final tripBox = HiveService.tripBox();
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.60);

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

                  final started = _fmt16(t.startedAt);
                  final ended = _fmt16(t.endedAt);

                  final bg = TripStatusColors.background(t.status);
                  final fg = TripStatusColors.foreground(t.status);

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
                            Text(
                              t.endedAt == null
                                  ? 'Started: $started'
                                  : 'Started: $started  •  Ended: $ended',
                              style: TextStyle(color: muted),
                            ),
                            Text(
                              'Last checkpoint: $lastCheckpoint',
                              style: TextStyle(color: muted),
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