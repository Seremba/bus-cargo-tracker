import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/trip.dart';
import '../../models/checkpoint.dart';
import '../../models/property_status.dart';
import '../../models/trip_status.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/trip_service.dart';
import '../../services/role_guard.dart';

class AdminTripDetailsScreen extends StatelessWidget {
  final Trip trip;
  const AdminTripDetailsScreen({super.key, required this.trip});

  Widget _notAuthorized() =>
      const Scaffold(body: Center(child: Text('Not authorized')));

  String _statusText(PropertyStatus s) {
    switch (s) {
      case PropertyStatus.pending:
        return '🟡 Pending';
      case PropertyStatus.inTransit:
        return '🔵 In Transit';
      case PropertyStatus.delivered:
        return '🟢 Delivered';
      case PropertyStatus.pickedUp:
        return '✅ Picked Up';
    }
  }

  String _tripStatusText(TripStatus status) {
    switch (status) {
      case TripStatus.active:
        return '🟢 Active';
      case TripStatus.ended:
        return '✅ Ended';
      case TripStatus.cancelled:
        return '⛔ Cancelled';
    }
  }

  Future<String?> _askCancelReason(BuildContext context) async {
    final controller = TextEditingController();

    return showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel trip?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This will mark the trip as cancelled. Continue?'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Cancel Trip'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) return _notAuthorized();

    final tripBox = HiveService.tripBox();
    final propertyBox = HiveService.propertyBox();

    return AnimatedBuilder(
      animation: Listenable.merge([
        tripBox.listenable(),
        propertyBox.listenable(),
      ]),
      builder: (context, _) {
        final refreshedTrip = tripBox.values.firstWhere(
          (t) => t.tripId == trip.tripId,
          orElse: () => trip,
        );

        final cargo =
            propertyBox.values
                .where((p) => p.tripId == refreshedTrip.tripId)
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            elevation: 2,
            title: Text(
              '${refreshedTrip.routeName} • ${_tripStatusText(refreshedTrip.status)}',
            ),
            actions: [
              if (refreshedTrip.status == TripStatus.active) ...[
                IconButton(
                  tooltip: 'End Trip',
                  icon: const Icon(Icons.stop_circle_outlined),
                  onPressed: () async {
                    if (!RoleGuard.hasRole(UserRole.admin)) return;

                    final ok =
                        await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('End trip?'),
                            content: const Text(
                              'This will mark the trip as ended. Continue?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('End Trip'),
                              ),
                            ],
                          ),
                        ) ??
                        false;

                    if (!ok) return;

                    await TripService.endTrip(refreshedTrip);

                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Trip ended ✅')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Cancel Trip',
                  icon: const Icon(Icons.cancel_outlined),
                  onPressed: () async {
                    if (!RoleGuard.hasRole(UserRole.admin)) return;

                    final reason = await _askCancelReason(context);
                    if (reason == null) return;

                    await TripService.cancelTrip(refreshedTrip, reason: reason);

                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Trip cancelled ⛔')),
                    );
                  },
                ),
              ],
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        refreshedTrip.routeName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('Driver: ${refreshedTrip.driverUserId}'),
                      const SizedBox(height: 4),
                      Text('Status: ${_tripStatusText(refreshedTrip.status)}'),
                      if (refreshedTrip.endedAt != null)
                        Text(
                          'Ended: ${refreshedTrip.endedAt!.toLocal().toString().substring(0, 16)}',
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Started: ${refreshedTrip.startedAt.toLocal().toString().substring(0, 16)}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Last checkpoint index: ${refreshedTrip.lastCheckpointIndex}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Checkpoints',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: refreshedTrip.checkpoints.length,
                  itemBuilder: (context, i) {
                    final Checkpoint cp = refreshedTrip.checkpoints[i];
                    final reached = cp.reachedAt != null;
                    final reachedText = reached
                        ? cp.reachedAt!.toLocal().toString().substring(0, 16)
                        : '—';

                    return ListTile(
                      dense: true,
                      leading: Icon(
                        reached ? Icons.check_circle : Icons.circle_outlined,
                      ),
                      title: Text(cp.name),
                      subtitle: Text('Reached: $reachedText'),
                      trailing: Text(
                        'Radius: ${cp.radiusMeters.toStringAsFixed(0)}m',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Cargo on this trip (${cargo.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (cargo.isEmpty)
                const Text('No cargo assigned to this trip yet.')
              else
                ...cargo.map((p) {
                  return Card(
                    child: ListTile(
                      title: Text(p.receiverName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${p.destination} • ${p.receiverPhone}'),
                          const SizedBox(height: 4),
                          Text(
                            _statusText(p.status),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sender: ${p.createdByUserId}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      trailing: Text(
                        p.createdAt.toLocal().toString().substring(0, 16),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
