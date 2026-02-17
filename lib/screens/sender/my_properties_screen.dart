import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
    // simple formatting; later we can add commas
    return '$currency $amount';
  }

  static String _statusText(PropertyStatus status) {
    switch (status) {
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

  static String _tripStatusText(TripStatus status) {
    switch (status) {
      case TripStatus.active:
        return '🟢 Active';
      case TripStatus.ended:
        return '✅ Ended';
      case TripStatus.cancelled:
        return '⛔ Cancelled';
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
          propertyBox.listenable(), // ✅ works because hive_flutter is imported
          tripBox.listenable(),
        ]),
        builder: (context, _) {
          final myItems = propertyBox.values
              .where((p) => p.createdByUserId == userId)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (myItems.isEmpty) {
            return const Center(child: Text('No properties yet.'));
          }

          return ListView.builder(
            itemCount: myItems.length,
            itemBuilder: (context, index) {
              final property = myItems[index];

              final String tripInfo = () {
                final tripId = property.tripId;
                if (tripId == null || tripId.trim().isEmpty) {
                  return 'Trip: Not started yet';
                }

                Trip? trip;
                try {
                  trip = tripBox.values.firstWhere((t) => t.tripId == tripId);
                } catch (_) {
                  trip = null;
                }

                if (trip == null) return 'Trip: Loading...';

                final i = trip.lastCheckpointIndex;

                String last;
                if (trip.checkpoints.isEmpty) {
                  last = 'No checkpoints configured';
                } else if (i < 0) {
                  last = 'Not started yet';
                } else if (i < trip.checkpoints.length) {
                  last = trip.checkpoints[i].name;
                } else {
                  last = 'Completed';
                }

                var info =
                    'Trip: ${_tripStatusText(trip.status)} • Last checkpoint: $last';
                if (trip.endedAt != null) {
                  info = '$info • Ended: ${_fmt16(trip.endedAt)}';
                }
                return info;
              }();

              // ✅ Payment summary line
              final paid = property.amountPaidTotal;
              final currency = property.currency.trim().isEmpty
                  ? 'UGX'
                  : property.currency.trim();
              final paymentLine = paid <= 0
                  ? 'Payment: —'
                  : 'Paid: ${_money(currency, paid)} • Last: ${_fmt16(property.lastPaidAt)}';

              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SenderPropertyDetailsScreen(property: property),
                      ),
                    );
                  },
                  title: Text(property.receiverName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${property.destination} • ${property.receiverPhone}'),
                      const SizedBox(height: 2),
                      Text(
                        'Items: ${property.itemCount} • Route: ${property.routeName.trim().isEmpty ? '—' : property.routeName}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _statusText(property.status),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(tripInfo, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(paymentLine, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  trailing: Text(
                    _fmt16(property.createdAt),
                    style: const TextStyle(fontSize: 12),
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
