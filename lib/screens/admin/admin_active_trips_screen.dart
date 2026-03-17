import 'package:bus_cargo_tracker/ui/app_colors.dart';
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

class AdminActiveTripsScreen extends StatelessWidget {
  const AdminActiveTripsScreen({super.key});

  Widget _notAuthorized() =>
      const Scaffold(body: Center(child: Text('Not authorized')));

  /// Initials avatar — Driver role color: green
  Widget _driverAvatar(String userId) {
    final parts = userId.trim().split(RegExp(r'[\s_-]+'));
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : userId.isNotEmpty
        ? userId.substring(0, userId.length.clamp(0, 2)).toUpperCase()
        : 'DR';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.green,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) return _notAuthorized();

    final box = HiveService.tripBox();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: ValueListenableBuilder(
          valueListenable: box.listenable(),
          builder: (context, Box<Trip> b, _) {
            final count = b.values
                .where((t) => t.status == TripStatus.active)
                .length;
            return Text('Active Trips ($count)');
          },
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<Trip> b, _) {
          final activeTrips =
              b.values.where((t) => t.status == TripStatus.active).toList()
                ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

          if (activeTrips.isEmpty) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.directions_bus_outlined,
                    size: 16,
                    color: Colors.black38,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'No active trips right now.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            itemCount: activeTrips.length,
            itemBuilder: (context, index) =>
                _tripTile(context, activeTrips[index]),
          );
        },
      ),
    );
  }

  Widget _tripTile(BuildContext context, Trip t) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    final lastIndex = t.lastCheckpointIndex;
    final lastName = (lastIndex >= 0 && lastIndex < t.checkpoints.length)
        ? t.checkpoints[lastIndex].name
        : 'No checkpoint reached yet';

    final total = t.checkpoints.length;
    final reached = (t.lastCheckpointIndex + 1).clamp(0, total);
    final progress = total > 0 ? reached / total : 0.0;

    final started = t.startedAt.toLocal().toString().substring(0, 16);

    final bg = TripStatusColors.background(t.status);
    final fg = TripStatusColors.foreground(t.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (!RoleGuard.hasRole(UserRole.admin)) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AdminTripDetailsScreen(trip: t)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: avatar + route + status ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _driverAvatar(t.driverUserId),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.routeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.person_outline, size: 12, color: muted),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                t.driverUserId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusChip(
                        text: TripStatusLabels.text(t.status),
                        bgColor: bg,
                        fgColor: fg,
                      ),
                      const SizedBox(height: 4),
                      Icon(Icons.chevron_right, size: 16, color: muted),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),

              // ── Started + last checkpoint ──
              Row(
                children: [
                  Icon(Icons.play_circle_outline, size: 13, color: muted),
                  const SizedBox(width: 4),
                  Text(
                    'Started: $started',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 13, color: muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Last: $lastName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Checkpoint progress bar ──
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.12,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$reached / $total',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
