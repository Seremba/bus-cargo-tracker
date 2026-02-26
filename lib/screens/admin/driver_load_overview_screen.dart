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

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Driver Load Overview'),
      ),
      body: ValueListenableBuilder(
        valueListenable: pBox.listenable(),
        builder: (context, Box<Property> pb, _) {
          return ValueListenableBuilder(
            valueListenable: iBox.listenable(),
            builder: (context, Box ib, _) {
              final itemSvc = PropertyItemService(iBox);
              final activeTrip = TripService.getActiveTripForCurrentDriver();

              // Pending properties only
              final pendingProps = pb.values
                  .where((p) => p.status == PropertyStatus.pending)
                  .toList()
                ..sort(
                  (a, b) => b.createdAt.compareTo(a.createdAt),
                );

              if (pendingProps.isEmpty) {
                return const Center(child: Text('No pending properties.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: pendingProps.length,
                itemBuilder: (context, idx) {
                  final p = pendingProps[idx];

                  final items =
                      itemSvc.getItemsForProperty(p.key.toString());

                  final loadedReady = items
                      .where((x) =>
                          x.status == PropertyItemStatus.loaded &&
                          x.tripId.trim().isEmpty)
                      .length;

                  final remainingPending = items
                      .where((x) => x.status == PropertyItemStatus.pending)
                      .length;

                  final onActiveTrip = activeTrip == null
                      ? 0
                      : items
                          .where(
                              (x) => x.tripId == activeTrip.tripId)
                          .length;

                  final code = p.propertyCode.trim().isEmpty
                      ? p.key.toString()
                      : p.propertyCode.trim();

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Code: $code',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('Receiver: ${p.receiverName}'),
                          Text('Destination: ${p.destination}'),
                          Text('Total items: ${p.itemCount}'),
                          const Divider(height: 18),

                          // Metrics
                          Text(
                            'Loaded (ready): $loadedReady/${p.itemCount}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Remaining at station: $remainingPending/${p.itemCount}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (activeTrip != null)
                            Text(
                              'On active trip: $onActiveTrip/${p.itemCount}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),

                          const SizedBox(height: 8),
                          Text(
                            'Created: ${_fmt16(p.createdAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'LoadedAt: ${_fmt16(p.loadedAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}