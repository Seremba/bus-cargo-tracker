import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/payment_record.dart';
import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/trip.dart';
import '../../models/trip_status.dart';
import '../../services/hive_service.dart';
import '../../services/pickup_qr_service.dart';

class SenderPropertyDetailsScreen extends StatelessWidget {
  final Property property;
  const SenderPropertyDetailsScreen({super.key, required this.property});

  static String _fmt16(DateTime? d) {
    if (d == null) return '—';
    return d.toLocal().toString().substring(0, 16);
  }

  static String _money(String currency, int amount) {
    final cur = currency.trim().isEmpty ? 'UGX' : currency.trim();
    return '$cur $amount';
  }

  static Trip? _findTripById(Iterable<Trip> trips, String tripId) {
    for (final t in trips) {
      if (t.tripId == tripId) return t;
    }
    return null;
  }

  String _statusText(PropertyStatus s) {
    switch (s) {
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

  String _tripStatusText(TripStatus s) {
    switch (s) {
      case TripStatus.active:
        return '🟢 Active';
      case TripStatus.ended:
        return '✅ Ended';
      case TripStatus.cancelled:
        return '⛔ Cancelled';
    }
  }

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final propertyBox = HiveService.propertyBox();
    final tripBox = HiveService.tripBox();
    final payBox = HiveService.paymentBox();

    return AnimatedBuilder(
      animation: Listenable.merge([
        propertyBox.listenable(),
        tripBox.listenable(),
        payBox.listenable(),
      ]),
      builder: (context, _) {
        final p = propertyBox.values.firstWhere(
          (x) => x.key == property.key,
          orElse: () => property,
        );

        final now = DateTime.now();

        Trip? trip;
        final tripId = p.tripId;
        if (tripId != null && tripId.trim().isNotEmpty) {
          trip = _findTripById(tripBox.values, tripId.trim());
        }

        // Trip progress
        final totalCps = trip?.checkpoints.length ?? 0;
        final lastIndex = trip?.lastCheckpointIndex ?? -1;
        final reachedCount = (lastIndex + 1).clamp(0, totalCps);
        final progress = totalCps == 0
            ? 0.0
            : (reachedCount / totalCps).clamp(0.0, 1.0);

        String? nextName;
        if (trip != null) {
          final nextIndex = trip.lastCheckpointIndex + 1;
          if (nextIndex >= 0 && nextIndex < trip.checkpoints.length) {
            nextName = trip.checkpoints[nextIndex].name;
          } else {
            if (trip.status == TripStatus.cancelled) {
              nextName = 'Trip cancelled';
            } else if (trip.status == TripStatus.ended) {
              nextName = 'Trip ended';
            } else {
              nextName = 'Completed';
            }
          }
        }

        // OTP
        final otp = p.pickupOtp;

        // Payment summary
        final currency = p.currency.trim().isEmpty ? 'UGX' : p.currency.trim();
        final paidTotal = p.amountPaidTotal;

        // Payment history
        final propKeyStr = p.key.toString();
        final payments = payBox.values
            .where((PaymentRecord x) => x.propertyKey == propKeyStr)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // ✅ Pickup QR payload
        final int? propertyKeyInt = (p.key is int)
            ? (p.key as int)
            : int.tryParse(p.key.toString());

        final String? pickupQrPayload = (propertyKeyInt == null)
            ? null
            : PickupQrService.buildPayload(
                propertyKey: propertyKeyInt,
                nonce: p.qrNonce,
              );

        // QR expiry info
        final issuedAt = p.qrIssuedAt;
        final expiresAt =
            (issuedAt == null) ? null : issuedAt.add(PickupQrService.ttl);

        // ✅ Use the variable (no lint)
        final bool isQrExpired = (expiresAt != null) ? now.isAfter(expiresAt) : false;

        // QR "ready" means: delivered + has nonce + issued + not consumed + payload
        final bool qrReadyForDisplay = p.status == PropertyStatus.delivered &&
            p.qrIssuedAt != null &&
            p.qrNonce.trim().isNotEmpty &&
            p.qrConsumedAt == null &&
            pickupQrPayload != null;

        final loadedStation = (p.loadedAtStation).trim();
        final loadedBy = (p.loadedByUserId).trim();

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            elevation: 2,
            title: const Text('Property Details'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // =========================
              // Header
              // =========================
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
                              p.receiverName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.blue.shade50,
                            ),
                            child: Text(
                              _statusText(p.status),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Receiver phone: ${p.receiverPhone}'),
                          ),
                          IconButton(
                            tooltip: 'Copy phone',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () => _copy(
                              context,
                              'Phone',
                              p.receiverPhone,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Destination: ${p.destination}'),
                      const SizedBox(height: 6),
                      Text('Items: ${p.itemCount}'),
                      Text(
                        'Route: ${p.routeName.trim().isEmpty ? '—' : p.routeName}',
                      ),
                      const SizedBox(height: 6),
                      if (p.propertyCode.trim().isNotEmpty)
                        Row(
                          children: [
                            Expanded(
                              child: Text('Property Code: ${p.propertyCode}'),
                            ),
                            IconButton(
                              tooltip: 'Copy code',
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () => _copy(
                                context,
                                'Property code',
                                p.propertyCode,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Created: ${_fmt16(p.createdAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Loaded: ${_fmt16(p.loadedAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Loaded at station: ${loadedStation.isEmpty ? '—' : loadedStation}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Loaded by: ${loadedBy.isEmpty ? '—' : loadedBy}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // =========================
              // Trip Progress
              // =========================
              const Text(
                'Trip Progress',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              if (trip == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Trip not started yet. You’ll see progress once the driver loads your cargo.',
                    ),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trip: ${_tripStatusText(trip.status)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 8),
                        Text('Progress: $reachedCount / $totalCps'),
                        if (nextName != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Next checkpoint: $nextName',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // =========================
              // Pickup OTP
              // =========================
              if (p.status == PropertyStatus.delivered &&
                  otp != null &&
                  otp.trim().isNotEmpty) ...[
                const Text(
                  'Pickup OTP',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'OTP: $otp\n\nShare this OTP with the receiver to pick up the property.',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () => _copy(context, 'OTP', otp),
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // =========================
              // ✅ Pickup QR (IMAGE + state)
              // =========================
              if (p.status == PropertyStatus.pickedUp || p.pickedUpAt != null) ...[
                const Text(
                  'Pickup QR',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Picked up ✅\nTime: ${_fmt16(p.pickedUpAt)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (p.status == PropertyStatus.delivered) ...[
                const Text(
                  'Pickup QR',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                // CASE A: QR already consumed
                if (p.qrConsumedAt != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'QR already used ✅\nUsed at: ${_fmt16(p.qrConsumedAt)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  )
                // CASE B: QR not issued
                else if (!qrReadyForDisplay)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Pickup QR not issued yet.\nAsk station staff/admin to re-issue.',
                      ),
                    ),
                  )
                // CASE C: QR expired (uses isQrExpired ✅)
                else if (isQrExpired)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '⏱ Pickup QR expired.\nTap refresh to generate a new QR.',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.deepOrange,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Issued: ${_fmt16(issuedAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          Text(
                            'Expired: ${_fmt16(expiresAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh Pickup QR'),
                              // ✅ Fix async-gap lint: don't capture messenger from context before await
                              onPressed: () async {
                                final ok =
                                    await PickupQrService.refreshForDelivered(p);

                                if (!context.mounted) return;

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Pickup QR refreshed ✅'
                                          : 'Cannot refresh QR ❌',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                // CASE D: QR valid
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Show this QR to staff at pickup.'),
                          const SizedBox(height: 10),
                          Center(
                            child: QrImageView(
                              data: pickupQrPayload, // safe here (qrReadyForDisplay true)
                              version: QrVersions.auto,
                              size: 220,
                              gapless: false,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Issued: ${_fmt16(issuedAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          Text(
                            'Expires: ${_fmt16(expiresAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'QR Payload (backup):',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            pickupQrPayload,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton.icon(
                              onPressed: () => _copy(
                                context,
                                'Pickup QR',
                                pickupQrPayload,
                              ),
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copy payload'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),
              ],

              // =========================
              // Payment
              // =========================
              const Text(
                'Payment',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              if (paidTotal <= 0 && payments.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No payment recorded yet.'),
                  ),
                )
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Paid: ${_money(currency, paidTotal)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Method: ${p.lastPaymentMethod.trim().isEmpty ? '—' : p.lastPaymentMethod.trim()}',
                        ),
                        Text(
                          'Station: ${p.lastPaidAtStation.trim().isEmpty ? '—' : p.lastPaidAtStation.trim()}',
                        ),
                        Text(
                          'TxnRef: ${p.lastTxnRef.trim().isEmpty ? '—' : p.lastTxnRef.trim()}',
                        ),
                        Text(
                          'Last Paid At: ${_fmt16(p.lastPaidAt)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (payments.isNotEmpty) ...[
                  const Text(
                    'Payment History',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  for (final x in payments)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${x.currency} ${x.amount} • ${x.method.trim().isEmpty ? '—' : x.method}',
                        ),
                        subtitle: Text(
                          'Station: ${x.station.trim().isEmpty ? '—' : x.station}\n'
                          'TxnRef: ${x.txnRef.trim().isEmpty ? '—' : x.txnRef}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Text(
                          _fmt16(x.createdAt),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ],

              const SizedBox(height: 12),

              // =========================
              // Timeline
              // =========================
              const Text(
                'Timeline',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    _timelineRow('Pending', p.createdAt, true),
                    _timelineRow('Loaded', p.loadedAt, p.loadedAt != null),
                    _timelineRow('In Transit', p.inTransitAt, p.inTransitAt != null),
                    _timelineRow('Delivered', p.deliveredAt, p.deliveredAt != null),
                    _timelineRow('Picked Up', p.pickedUpAt, p.pickedUpAt != null),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _timelineRow(String label, DateTime? at, bool done) {
    return ListTile(
      dense: true,
      leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked),
      title: Text(label),
      subtitle: Text(_fmt16(at)),
    );
  }
}
