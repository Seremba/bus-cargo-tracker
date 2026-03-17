import 'package:bus_cargo_tracker/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/property_item_status.dart';
import '../../models/user_role.dart';

import '../../services/hive_service.dart';
import '../../services/property_item_service.dart';
import '../../services/role_guard.dart';
import '../../services/trip_service.dart';

import '../../theme/status_colors.dart';
import '../../ui/status_labels.dart';
import '../../widgets/status_chip.dart';

class DriverLoadOverviewScreen extends StatelessWidget {
  const DriverLoadOverviewScreen({super.key});

  static String _fmt16(DateTime? d) {
    if (d == null) return '—';
    return d.toLocal().toString().substring(0, 16);
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasAny({UserRole.driver, UserRole.admin})) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final pBox = HiveService.propertyBox();
    final iBox = HiveService.propertyItemBox();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.60);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Driver Load Overview'),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([pBox.listenable(), iBox.listenable()]),
        builder: (context, _) {
          final itemSvc = PropertyItemService(iBox);
          final activeTrip = TripService.getActiveTripForCurrentDriver();

          final pendingProps =
              pBox.values
                  .where((p) => p.status == PropertyStatus.pending)
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (pendingProps.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: Colors.black38,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'No pending properties.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              // ── Active trip context card ──
              if (activeTrip != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.route_outlined,
                        size: 17,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Active trip: ${activeTrip.routeName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(
                        text: TripStatusLabels.text(activeTrip.status),
                        bgColor: TripStatusColors.background(activeTrip.status),
                        fgColor: TripStatusColors.foreground(activeTrip.status),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              for (final p in pendingProps)
                _card(
                  context,
                  p,
                  itemSvc: itemSvc,
                  activeTripId: activeTrip?.tripId,
                  muted: muted,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(
    BuildContext context,
    Property p, {
    required PropertyItemService itemSvc,
    required String? activeTripId,
    required Color muted,
  }) {
    final items = itemSvc.getItemsForProperty(p.key.toString());

    final loadedReady = items
        .where(
          (x) =>
              x.status == PropertyItemStatus.loaded && x.tripId.trim().isEmpty,
        )
        .length;

    final remainingPending = items
        .where((x) => x.status == PropertyItemStatus.pending)
        .length;

    final onActiveTrip = (activeTripId == null)
        ? 0
        : items.where((x) => x.tripId == activeTripId).length;

    final code = p.propertyCode.trim().isEmpty
        ? p.key.toString()
        : p.propertyCode.trim();

    final bg = PropertyStatusColors.background(p.status);
    final fg = PropertyStatusColors.foreground(p.status);

    final cs = Theme.of(context).colorScheme;

    // Progress fraction for loaded items
    final total = p.itemCount > 0 ? p.itemCount : 1;
    final loadFraction = (loadedReady / total).clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: code + status pill ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Property code avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Receiver + destination
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 12, color: muted),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              p.receiverName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.place_outlined, size: 12, color: muted),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              p.destination,
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
                StatusChip(
                  text: PropertyStatusLabels.text(p.status),
                  bgColor: bg,
                  fgColor: fg,
                ),
              ],
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),

            // ── Load progress bar ──
            Row(
              children: [
                Icon(Icons.local_shipping_outlined, size: 13, color: muted),
                const SizedBox(width: 4),
                Text(
                  'Total items: ${p.itemCount}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: loadFraction,
                minHeight: 6,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 8),

            // ── Load stats ──
            Row(
              children: [
                Expanded(
                  child: _statPill(
                    icon: Icons.check_circle_outline,
                    label: 'Loaded (ready)',
                    value: '$loadedReady/${p.itemCount}',
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statPill(
                    icon: Icons.hourglass_top_outlined,
                    label: 'Remaining',
                    value: '$remainingPending/${p.itemCount}',
                    color: Colors.amber.shade700,
                  ),
                ),
              ],
            ),

            if (activeTripId != null) ...[
              const SizedBox(height: 6),
              _statPill(
                icon: Icons.directions_bus_outlined,
                label: 'On active trip',
                value: '$onActiveTrip/${p.itemCount}',
                color: Colors.blue,
              ),
            ],

            const SizedBox(height: 10),

            // ── Timestamps ──
            Row(
              children: [
                Icon(Icons.access_time_outlined, size: 12, color: muted),
                const SizedBox(width: 4),
                Text(
                  'Created: ${_fmt16(p.createdAt)}',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.upload_outlined, size: 12, color: muted),
                const SizedBox(width: 4),
                Text(
                  'Loaded at: ${_fmt16(p.loadedAt)}',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Stat pill: icon + label + value ──
  Widget _statPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: color),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
