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

// ✅ standardized UI
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

    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.60);

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

          // Pending properties only (driver loads from pending)
          final pendingProps = pBox.values
              .where((p) => p.status == PropertyStatus.pending)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (pendingProps.isEmpty) {
            return const Center(child: Text('No pending properties.'));
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // ✅ Small context card (optional but helpful)
              if (activeTrip != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.route_outlined, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Active trip: ${activeTrip.routeName}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        StatusChip(
                          text: TripStatusLabels.text(activeTrip.status),
                          bgColor: TripStatusColors.background(activeTrip.status),
                          fgColor: TripStatusColors.foreground(activeTrip.status),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              for (final p in pendingProps) ...[
                _card(
                  context,
                  p,
                  itemSvc: itemSvc,
                  activeTripId: activeTrip?.tripId,
                  muted: muted,
                ),
              ],
              const SizedBox(height: 6),
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
    // Read-only view (no ensure here)
    final items = itemSvc.getItemsForProperty(p.key.toString());

    final loadedReady = items
        .where(
          (x) =>
              x.status == PropertyItemStatus.loaded &&
              x.tripId.trim().isEmpty,
        )
        .length;

    final remainingPending =
        items.where((x) => x.status == PropertyItemStatus.pending).length;

    final onActiveTrip = (activeTripId == null)
        ? 0
        : items.where((x) => x.tripId == activeTripId).length;

    final code = p.propertyCode.trim().isEmpty
        ? p.key.toString()
        : p.propertyCode.trim();

    final bg = PropertyStatusColors.background(p.status);
    final fg = PropertyStatusColors.foreground(p.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Code: $code',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                StatusChip(
                  text: PropertyStatusLabels.text(p.status),
                  bgColor: bg,
                  fgColor: fg,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Receiver: ${p.receiverName}'),
            Text('Destination: ${p.destination}'),
            Text('Total items: ${p.itemCount}'),
            const Divider(height: 18),

            Text(
              'Loaded (ready): $loadedReady/${p.itemCount}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              'Remaining at station: $remainingPending/${p.itemCount}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (activeTripId != null)
              Text(
                'On active trip: $onActiveTrip/${p.itemCount}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),

            const SizedBox(height: 10),
            Text(
              'Created: ${_fmt16(p.createdAt)}',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            Text(
              'LoadedAt: ${_fmt16(p.loadedAt)}',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}