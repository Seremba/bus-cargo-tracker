import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/trip.dart';
import '../../models/checkpoint.dart';
import '../../models/trip_status.dart';
import '../../models/user.dart';
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

  // ── Resolve a userId to a display name, falling back to a shortened id ──
  static String _resolveName(String userId) {
    final raw = userId.trim();
    if (raw.isEmpty) return '—';
    try {
      final user = HiveService.userBox().values
          .whereType<User>()
          .firstWhere((u) => u.id == raw);
      final name = user.fullName.trim();
      return name.isNotEmpty ? name : _shortId(raw);
    } catch (_) {
      return _shortId(raw);
    }
  }

  // Show only last 8 chars of a UUID so it is still identifiable but compact
  static String _shortId(String id) {
    if (id.length <= 8) return id;
    return '…${id.substring(id.length - 8)}';
  }

  // ── Human-readable checkpoint progress ──
  static String _checkpointSummary(Trip t) {
    final total = t.checkpoints.length;
    if (total == 0) return 'No checkpoints configured';

    final reached = t.lastCheckpointIndex + 1; // index is -1 when none reached
    if (reached <= 0) return 'Departed — no checkpoint reached yet';
    if (reached >= total) return 'All checkpoints reached';

    final lastName = t.checkpoints[t.lastCheckpointIndex].name;
    return 'Last: $lastName ($reached / $total)';
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
        HiveService.userBox().listenable(), // needed so names refresh if user data changes
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

        final tripBg = TripStatusColors.background(refreshedTrip.status);
        final tripFg = TripStatusColors.foreground(refreshedTrip.status);

        // Resolve driver UUID → name
        final driverDisplay = _resolveName(refreshedTrip.driverUserId);

        final cs = Theme.of(context).colorScheme;
        final muted = cs.onSurface.withValues(alpha: 0.55);

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
              // ── Trip summary card ──────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Route + status chip
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

                      const SizedBox(height: 12),

                      // Driver — resolved to full name
                      _infoRow(
                        icon: Icons.person_outline,
                        label: 'Driver',
                        value: driverDisplay,
                        muted: muted,
                      ),

                      const SizedBox(height: 6),

                      // Started
                      _infoRow(
                        icon: Icons.play_circle_outline,
                        label: 'Started',
                        value: refreshedTrip.startedAt
                            .toLocal()
                            .toString()
                            .substring(0, 16),
                        muted: muted,
                      ),

                      // Ended (only when applicable)
                      if (refreshedTrip.endedAt != null) ...[
                        const SizedBox(height: 6),
                        _infoRow(
                          icon: Icons.stop_circle_outlined,
                          label: 'Ended',
                          value: refreshedTrip.endedAt!
                              .toLocal()
                              .toString()
                              .substring(0, 16),
                          muted: muted,
                        ),
                      ],

                      const SizedBox(height: 6),

                      // Checkpoint progress — human-readable
                      _infoRow(
                        icon: Icons.place_outlined,
                        label: 'Progress',
                        value: _checkpointSummary(refreshedTrip),
                        muted: muted,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Checkpoints ────────────────────────────────────────────
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
                        reached
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: reached ? Colors.green : muted,
                      ),
                      title: Text(cp.name),
                      subtitle: Text('Reached: $reachedText'),
                      trailing: Text(
                        'Radius: ${cp.radiusMeters.toStringAsFixed(0)}m',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // ── Cargo ──────────────────────────────────────────────────
              Text(
                'Cargo on this trip (${cargo.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              if (cargo.isEmpty)
                Text(
                  'No cargo assigned to this trip yet.',
                  style: TextStyle(color: muted),
                )
              else
                ...cargo.map((p) {
                  final pBg = PropertyStatusColors.background(p.status);
                  final pFg = PropertyStatusColors.foreground(p.status);

                  // Resolve sender UUID → name
                  final senderDisplay = _resolveName(p.createdByUserId);

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Receiver name + status chip on same row,
                          // name now uses Flexible so it never wraps awkwardly
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Text(
                                  p.receiverName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  // allow wrapping but keep it tidy
                                  softWrap: true,
                                ),
                              ),
                              const SizedBox(width: 8),
                              StatusChip(
                                text: PropertyStatusLabels.text(p.status),
                                bgColor: pBg,
                                fgColor: pFg,
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          _infoRow(
                            icon: Icons.place_outlined,
                            label: 'Destination',
                            value: p.destination,
                            muted: muted,
                          ),
                          const SizedBox(height: 4),
                          _infoRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone',
                            value: p.receiverPhone,
                            muted: muted,
                          ),
                          const SizedBox(height: 4),
                          _infoRow(
                            icon: Icons.person_outline,
                            label: 'Sender',
                            value: senderDisplay,
                            muted: muted,
                          ),
                          const SizedBox(height: 4),
                          _infoRow(
                            icon: Icons.access_time_outlined,
                            label: 'Registered',
                            value: p.createdAt
                                .toLocal()
                                .toString()
                                .substring(0, 16),
                            muted: muted,
                          ),
                        ],
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

  // ── Shared detail row helper ─────────────────────────────────────────────
  static Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color muted,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: muted),
        const SizedBox(width: 6),
        SizedBox(
          width: 76,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 12,
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}