import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_item_status.dart';
import '../../models/property_status.dart';
import '../../models/trip.dart';
import '../../services/hive_service.dart';
import '../../services/property_item_service.dart';
import '../../services/session.dart';
import '../../services/trip_service.dart';

/// A clean cargo manifest for the driver — optimised for showing at
/// checkpoints, border crossings, and police checks.
///
/// Shows: vehicle/route info, total items, and a numbered list of every
/// property on board with destination, description, and item count.
class DriverManifestScreen extends StatelessWidget {
  const DriverManifestScreen({super.key});

  static String _fmt10(DateTime d) =>
      d.toLocal().toString().substring(0, 10);

  @override
  Widget build(BuildContext context) {
    final pBox = HiveService.propertyBox();
    final iBox = HiveService.propertyItemBox();
    final assignedRouteId =
        (Session.currentAssignedRouteId ?? '').trim();
    final assignedRouteName =
        (Session.currentAssignedRouteName ?? '').trim();
    final driverName =
        (Session.currentUserFullName ?? 'Driver').trim();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Cargo Manifest'),
        actions: [
          IconButton(
            tooltip: 'Copy manifest text',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => _copyManifest(
              context,
              pBox: pBox,
              iBox: iBox,
              assignedRouteId: assignedRouteId,
              assignedRouteName: assignedRouteName,
              driverName: driverName,
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          pBox.listenable(),
          iBox.listenable(),
        ]),
        builder: (context, _) {
          final cs = Theme.of(context).colorScheme;
          final muted = cs.onSurface.withValues(alpha: 0.55);
          final itemSvc = PropertyItemService(iBox);

          final activeTrip = TripService.getActiveTripForCurrentDriver(
            routeId: assignedRouteId.isEmpty ? null : assignedRouteId,
          );
          final activeTripId = activeTrip?.tripId;

          final currentDriverId =
              (Session.currentUserId ?? '').trim();

          // Properties currently on board
          final onBoard = pBox.values.where((p) {
            if (assignedRouteId.isNotEmpty &&
                p.routeId != assignedRouteId) { return false; }
            // On active trip — isolated by tripId
            if (activeTripId != null && activeTripId.isNotEmpty) {
              if ((p.tripId ?? '').trim() == activeTripId.trim()) {
                return p.status == PropertyStatus.inTransit ||
                    p.status == PropertyStatus.loaded;
              }
            }
            // Before trip starts — filter by driverUserId
            final items = itemSvc.getItemsForProperty(p.key.toString());
            return items.any(
              (x) =>
                  x.status == PropertyItemStatus.loaded &&
                  x.tripId.trim().isEmpty &&
                  x.driverUserId.trim() == currentDriverId,
            );
          }).toList()
            ..sort((a, b) => a.destination.compareTo(b.destination));

          final totalProperties = onBoard.length;
          final totalItems =
              onBoard.fold<int>(0, (sum, p) => sum + p.itemCount);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              // ── Header card ────────────────────────────────────────
              _headerCard(
                cs: cs,
                muted: muted,
                driverName: driverName,
                routeName: assignedRouteName.isEmpty
                    ? 'Route not assigned'
                    : assignedRouteName,
                activeTrip: activeTrip,
                totalProperties: totalProperties,
                totalItems: totalItems,
              ),

              const SizedBox(height: 12),

              if (onBoard.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 48,
                          color: muted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No cargo on board',
                          style: TextStyle(color: muted, fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Properties will appear here once\nthey are loaded onto your vehicle.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: muted.withValues(alpha: 0.60),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // ── Property list ───────────────────────────────────
                for (int i = 0; i < onBoard.length; i++)
                  _propertyRow(
                    context: context,
                    index: i + 1,
                    p: onBoard[i],
                    itemSvc: itemSvc,
                    muted: muted,
                    cs: cs,
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget _headerCard({
    required ColorScheme cs,
    required Color muted,
    required String driverName,
    required String routeName,
    required Trip? activeTrip,
    required int totalProperties,
    required int totalItems,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.local_shipping_outlined,
                    size: 20,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cargo Manifest',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _fmt10(DateTime.now()),
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _infoRow(Icons.person_outline, 'Driver', driverName, muted),
            _infoRow(Icons.route_outlined, 'Route', routeName, muted),
            if (activeTrip != null)
              _infoRow(
                Icons.trip_origin,
                'Trip started',
                _fmt10(activeTrip.startedAt),
                muted,
              ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: _statPill(
                    label: 'Shipments',
                    value: '$totalProperties',
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statPill(
                    label: 'Total items',
                    value: '$totalItems',
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
      IconData icon, String label, String value, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: muted),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _propertyRow({
    required BuildContext context,
    required int index,
    required Property p,
    required PropertyItemService itemSvc,
    required Color muted,
    required ColorScheme cs,
  }) {
    final items = itemSvc.getItemsForProperty(p.key.toString());
    final inTransitCount =
        items.where((x) => x.status == PropertyItemStatus.inTransit).length;
    final loadedCount = items
        .where((x) =>
            x.status == PropertyItemStatus.loaded &&
            x.tripId.trim().isEmpty)
        .length;
    final onBoardCount =
        inTransitCount > 0 ? inTransitCount : loadedCount;
    final showCount =
        onBoardCount > 0 ? onBoardCount : p.itemCount;

    final code = p.propertyCode.trim().isEmpty ? '—' : p.propertyCode;
    final description =
        p.description.trim().isEmpty ? '—' : p.description.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Index number
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$index',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Receiver + destination
                  Text(
                    p.receiverName.trim().isEmpty ? '—' : p.receiverName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 12, color: muted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          p.destination.trim().isEmpty
                              ? '—'
                              : p.destination.trim(),
                          style: TextStyle(fontSize: 12, color: muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Description + item count
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 12, color: muted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          '$description — $showCount item${showCount == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12, color: muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Property code
                  Row(
                    children: [
                      Icon(Icons.qr_code_outlined,
                          size: 12, color: muted),
                      const SizedBox(width: 3),
                      Text(
                        code,
                        style: TextStyle(
                          fontSize: 11,
                          color: muted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Item count badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.green.withValues(alpha: 0.25)),
              ),
              child: Text(
                '$showCount\nitems',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.green,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyManifest(
    BuildContext context, {
    required dynamic pBox,
    required dynamic iBox,
    required String assignedRouteId,
    required String assignedRouteName,
    required String driverName,
  }) async {
    final itemSvc = PropertyItemService(iBox);
    final activeTrip = TripService.getActiveTripForCurrentDriver(
      routeId: assignedRouteId.isEmpty ? null : assignedRouteId,
    );
    final activeTripId = activeTrip?.tripId;

    final currentDriverId = (Session.currentUserId ?? '').trim();
    final onBoard = (pBox.values as Iterable<Property>).where((p) {
      if (assignedRouteId.isNotEmpty && p.routeId != assignedRouteId) {
        return false;
      }
      if (activeTripId != null && activeTripId.isNotEmpty) {
        if ((p.tripId ?? '').trim() == activeTripId.trim()) {
          return p.status == PropertyStatus.inTransit ||
              p.status == PropertyStatus.loaded;
        }
      }
      final items = itemSvc.getItemsForProperty(p.key.toString());
      return items.any(
        (x) =>
            x.status == PropertyItemStatus.loaded &&
            x.tripId.trim().isEmpty &&
            x.driverUserId.trim() == currentDriverId,
      );
    }).toList()
      ..sort((a, b) => a.destination.compareTo(b.destination));

    final buf = StringBuffer();
    buf.writeln('CARGO MANIFEST — ${_fmt10(DateTime.now())}');
    buf.writeln('Driver: $driverName');
    buf.writeln('Route: ${assignedRouteName.isEmpty ? '—' : assignedRouteName}');
    buf.writeln(
        'Total: ${onBoard.length} shipment${onBoard.length == 1 ? '' : 's'}, '
        '${onBoard.fold<int>(0, (s, p) => s + p.itemCount)} items');
    buf.writeln('─' * 40);
    for (int i = 0; i < onBoard.length; i++) {
      final p = onBoard[i];
      final desc = p.description.trim().isEmpty ? '—' : p.description.trim();
      buf.writeln(
          '${i + 1}. ${p.receiverName} → ${p.destination} | $desc | ${p.itemCount} item${p.itemCount == 1 ? '' : 's'} | ${p.propertyCode}');
    }

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Manifest copied to clipboard ✅')),
    );
  }
}