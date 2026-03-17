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

class AdminTripsScreen extends StatelessWidget {
  const AdminTripsScreen({super.key});

  Widget _notAuthorized() =>
      const Scaffold(body: Center(child: Text('Not authorized')));

  static String _fmt16(DateTime? d) {
    if (d == null) return '—';
    return d.toLocal().toString().substring(0, 16);
  }

  /// Initials avatar from a userId / full name string
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

    final tripBox = HiveService.tripBox();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          elevation: 2,
          title: const Text('Trips'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: ValueListenableBuilder(
              valueListenable: tripBox.listenable(),
              builder: (context, Box<Trip> box, _) {
                final allTrips = box.values.toList();
                int count(TripStatus s) =>
                    allTrips.where((t) => t.status == s).length;
                return TabBar(
                  tabs: [
                    Tab(text: 'Active (${count(TripStatus.active)})'),
                    Tab(text: 'Ended (${count(TripStatus.ended)})'),
                    Tab(
                        text:
                            'Cancelled (${count(TripStatus.cancelled)})'),
                  ],
                );
              },
            ),
          ),
        ),
        body: ValueListenableBuilder(
          valueListenable: tripBox.listenable(),
          builder: (context, Box<Trip> box, _) {
            final allTrips = box.values.toList()
              ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

            List<Trip> byStatus(TripStatus s) =>
                allTrips.where((t) => t.status == s).toList();

            return TabBarView(
              children: [
                _buildList(context, byStatus(TripStatus.active)),
                _buildList(context, byStatus(TripStatus.ended)),
                _buildList(context, byStatus(TripStatus.cancelled)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Trip> trips) {
    if (trips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(
          children: [
            const Icon(Icons.directions_bus_outlined,
                size: 16, color: Colors.black38),
            const SizedBox(width: 8),
            const Text(
              'No trips here yet.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      itemCount: trips.length,
      itemBuilder: (context, index) => _tripTile(context, trips[index]),
    );
  }

  Widget _tripTile(BuildContext context, Trip t) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    final i = t.lastCheckpointIndex;
    final lastCheckpoint =
        (i >= 0 && i < t.checkpoints.length)
            ? t.checkpoints[i].name
            : 'No checkpoint reached yet';

    final total = t.checkpoints.length;
    final reached = (t.lastCheckpointIndex + 1).clamp(0, total);
    final progress = total > 0 ? reached / total : 0.0;

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
            MaterialPageRoute(
              builder: (_) => AdminTripDetailsScreen(trip: t),
            ),
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
                            Icon(Icons.person_outline,
                                size: 12, color: muted),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                t.driverUserId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, color: muted),
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
                      Icon(Icons.chevron_right,
                          size: 16,
                          color: muted),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),
              Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 8),

              // ── Timestamps ──
              Row(
                children: [
                  Icon(Icons.play_circle_outline,
                      size: 13, color: muted),
                  const SizedBox(width: 4),
                  Text(
                    'Started: ${_fmt16(t.startedAt)}',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  if (t.endedAt != null) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.stop_circle_outlined,
                        size: 13, color: muted),
                    const SizedBox(width: 4),
                    Text(
                      'Ended: ${_fmt16(t.endedAt)}',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 6),

              // ── Last checkpoint ──
              Row(
                children: [
                  Icon(Icons.place_outlined,
                      size: 13, color: muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Last: $lastCheckpoint',
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
                        backgroundColor: AppColors.primary
                            .withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary),
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