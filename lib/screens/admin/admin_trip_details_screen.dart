import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/trip.dart';
import '../../models/checkpoint.dart';
import '../../models/trip_status.dart';
import '../../models/user_role.dart';

import '../../services/hive_service.dart';
import '../../services/trip_service.dart';
import '../../services/role_guard.dart';

import '../../theme/status_colors.dart';
import '../../widgets/status_chip.dart';

import '../../ui/status_labels.dart';

class AdminTripDetailsScreen extends StatelessWidget {
  final Trip trip;
  const AdminTripDetailsScreen({super.key, required this.trip});

  Widget _notAuthorized() =>
      const Scaffold(body: Center(child: Text('Not authorized')));

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

        final cargo = propertyBox.values
            .where((p) => p.tripId == refreshedTrip.tripId)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // ✅ Standardized trip chip colors (bg + fg)
        final tripBg = TripStatusColors.background(refreshedTrip.status);
        final tripFg = TripStatusColors.foreground(refreshedTrip.status);

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            elevation: 2,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    refreshedTrip.routeName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                StatusChip(
                  text: TripStatusLabels.text(refreshedTrip.status),
                  bgColor: tripBg,
                  fgColor: tripFg,
                ),
              ],
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              refreshedTrip.routeName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          StatusChip(
                            text: TripStatusLabels.text(refreshedTrip.status),
                            bgColor: tripBg,
                            fgColor: tripFg,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Driver: ${refreshedTrip.driverUserId}'),
                      const SizedBox(height: 6),
                      Text(
                        'Started: ${refreshedTrip.startedAt.toLocal().toString().substring(0, 16)}',
                      ),
                      if (refreshedTrip.endedAt != null)
                        Text(
                          'Ended: ${refreshedTrip.endedAt!.toLocal().toString().substring(0, 16)}',
                        ),
                      const SizedBox(height: 6),
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
                  final pBg = PropertyStatusColors.background(p.status);
                  final pFg = PropertyStatusColors.foreground(p.status);

                  return Card(
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(child: Text(p.receiverName)),
                          const SizedBox(width: 8),
                          StatusChip(
                            text: PropertyStatusLabels.text(p.status),
                            bgColor: pBg,
                            fgColor: pFg,
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Text('${p.destination} • ${p.receiverPhone}'),
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