import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/trip.dart';
import '../../models/trip_status.dart';
import '../../services/hive_service.dart';
import '../../services/session.dart';
import 'sender_property_details_screen.dart';

class MyPropertiesScreen extends StatelessWidget {
  const MyPropertiesScreen({super.key});

  static String _fmt16(DateTime? d) {
    if (d == null) return '—';
    return d.toLocal().toString().substring(0, 16);
  }

  static String _money(String currency, int amount) {
    return '$currency $amount';
  }

  static ({String emoji, String label, Color bg, Color fg}) _statusStyle(
    PropertyStatus status,
  ) {
    switch (status) {
      case PropertyStatus.pending:
        return (
          emoji: '🟡',
          label: 'Pending',
          bg: const Color(0xFFFFF8E1),
          fg: const Color(0xFFF57F17),
        );
      case PropertyStatus.loaded:
        return (
          emoji: '🟠',
          label: 'Loaded',
          bg: const Color(0xFFFFF3E0),
          fg: const Color(0xFFE65100),
        );
      case PropertyStatus.inTransit:
        return (
          emoji: '🔵',
          label: 'In Transit',
          bg: const Color(0xFFE3F2FD),
          fg: const Color(0xFF1565C0),
        );
      case PropertyStatus.delivered:
        return (
          emoji: '🟢',
          label: 'Delivered',
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF2E7D32),
        );
      case PropertyStatus.pickedUp:
        return (
          emoji: '✅',
          label: 'Picked Up',
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF1B5E20),
        );
      case PropertyStatus.rejected:
        return (
          emoji: '🔴',
          label: 'Rejected',
          bg: const Color(0xFFFFEBEE),
          fg: const Color(0xFFC62828),
        );
      case PropertyStatus.expired:
        return (
          emoji: '⏳',
          label: 'Expired',
          bg: const Color(0xFFEFEBE9),
          fg: const Color(0xFF4E342E),
        );
    }
  }

  static String _tripLine(Property property, Trip? trip) {
    final tripId = property.tripId;
    if (tripId == null || tripId.trim().isEmpty) {
      return 'Awaiting departure';
    }
    if (trip == null) return 'Trip: Loading...';

    final i = trip.lastCheckpointIndex;
    String last;
    if (trip.checkpoints.isEmpty) {
      last = 'No checkpoints configured';
    } else if (i < 0) {
      last = 'Departed — no checkpoint yet';
    } else if (i < trip.checkpoints.length) {
      last = trip.checkpoints[i].name;
    } else {
      last = 'Completed';
    }

    switch (trip.status) {
      case TripStatus.active:
        return 'En route • Last: $last';
      case TripStatus.ended:
        return 'Trip ended • Last: $last';
      case TripStatus.cancelled:
        return 'Trip cancelled';
    }
  }

  @override
  Widget build(BuildContext context) {
    final propertyBox = HiveService.propertyBox();
    final tripBox = HiveService.tripBox();
    final userId = Session.currentUserId!;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('My Properties'),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          propertyBox.listenable(),
          tripBox.listenable(),
        ]),
        builder: (context, _) {
          final myItems =
              propertyBox.values
                  .where((p) => p.createdByUserId == userId)
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (myItems.isEmpty) {
            return const Center(child: Text('No properties yet.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: myItems.length,
            itemBuilder: (context, index) {
              final property = myItems[index];
              final style = _statusStyle(property.status);

              Trip? trip;
              final tripId = property.tripId;
              if (tripId != null && tripId.trim().isNotEmpty) {
                try {
                  trip = tripBox.values.firstWhere((t) => t.tripId == tripId);
                } catch (_) {
                  trip = null;
                }
              }

              final tripInfo = _tripLine(property, trip);

              final paid = property.amountPaidTotal;
              final currency = property.currency.trim().isEmpty
                  ? 'UGX'
                  : property.currency.trim();

              final muted = Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.55);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SenderPropertyDetailsScreen(property: property),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                property.receiverName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: style.bg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${style.emoji}  ${style.label}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: style.fg,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        Text(
                          '📍 ${property.destination}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          '📞 ${property.receiverPhone}',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          '${property.itemCount} item${property.itemCount == 1 ? '' : 's'}  •  ${property.routeName.trim().isEmpty ? 'No route' : property.routeName}',
                          style: TextStyle(fontSize: 12, color: muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        // F1: rejection reason snippet
                        if (property.status == PropertyStatus.rejected &&
                            (property.rejectionCategory ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '⚠ Rejected — tap to view reason',
                            style: TextStyle(
                              fontSize: 12,
                              color: const Color(0xFFC62828),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],

                        // F5: expiry notice
                        if (property.status == PropertyStatus.expired) ...[
                          const SizedBox(height: 4),
                          const Text(
                            '⏳ Expired — no payment within 10 days. Contact desk to restore.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4E342E),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        Divider(height: 1, color: Colors.grey.shade200),
                        const SizedBox(height: 8),

                        Row(
                          children: [
                            Icon(
                              Icons.directions_bus_outlined,
                              size: 14,
                              color: muted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                tripInfo,
                                style: TextStyle(fontSize: 12, color: muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        Row(
                          children: [
                            Icon(
                              Icons.payments_outlined,
                              size: 14,
                              color: muted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: paid <= 0
                                  ? Text(
                                      'No payment recorded',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Paid: ${_money(currency, paid)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'Last paid: ${_fmt16(property.lastPaidAt)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: muted,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text(
                            'Created: ${_fmt16(property.createdAt)}',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
