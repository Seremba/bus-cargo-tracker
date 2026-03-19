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
import '../../services/property_service.dart';

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
      case PropertyStatus.loaded:
        return '🟠 Loaded';
      case PropertyStatus.inTransit:
        return '🔵 In Transit';
      case PropertyStatus.delivered:
        return '🟢 Delivered';
      case PropertyStatus.pickedUp:
        return '✅ Picked Up';
      case PropertyStatus.rejected:
        return '🔴 Rejected';
      case PropertyStatus.expired:
        return '⏳ Expired';
      case PropertyStatus.underReview:
        return '🔎 Under Review';
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied ✅')));
  }

  @override
  Widget build(BuildContext context) {
    final propertyBox = HiveService.propertyBox();
    final tripBox = HiveService.tripBox();
    final payBox = HiveService.paymentBox();
    final userBox = HiveService.userBox();

    return AnimatedBuilder(
      animation: Listenable.merge([
        propertyBox.listenable(),
        tripBox.listenable(),
        payBox.listenable(),
        userBox.listenable(),
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
            nextName = trip.status == TripStatus.cancelled
                ? 'Trip cancelled'
                : trip.status == TripStatus.ended
                ? 'Trip ended'
                : 'Completed';
          }
        }

        final currency = p.currency.trim().isEmpty ? 'UGX' : p.currency.trim();
        final paidTotal = p.amountPaidTotal;

        final propKeyStr = p.key.toString();
        final payments =
            payBox.values
                .whereType<PaymentRecord>()
                .where((x) => x.propertyKey == propKeyStr)
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final int? propertyKeyInt = (p.key is int)
            ? (p.key as int)
            : int.tryParse(p.key.toString());

        final String? pickupQrPayload = (propertyKeyInt == null)
            ? null
            : PickupQrService.buildPayload(
                propertyKey: propertyKeyInt,
                nonce: p.qrNonce,
              );

        final issuedAt = p.qrIssuedAt;
        final expiresAt = (issuedAt == null)
            ? null
            : issuedAt.add(PickupQrService.ttl);
        final bool isQrExpired = (expiresAt != null)
            ? now.isAfter(expiresAt)
            : false;

        final bool qrReadyForDisplay =
            p.status == PropertyStatus.delivered &&
            p.qrIssuedAt != null &&
            p.qrNonce.trim().isNotEmpty &&
            p.qrConsumedAt == null &&
            pickupQrPayload != null;

        final loadedStation = p.loadedAtStation.trim();
        final loadedByRaw = p.loadedByUserId.trim();
        final loadedByUser = userBox.values
            .where((u) => u.id == loadedByRaw)
            .firstOrNull;
        final loadedBy = (loadedByUser?.fullName.trim().isNotEmpty == true)
            ? loadedByUser!.fullName.trim()
            : loadedByRaw.isEmpty
            ? ''
            : loadedByRaw;

        final bool loadedDone =
            p.loadedAt != null ||
            p.status == PropertyStatus.inTransit ||
            p.status == PropertyStatus.delivered ||
            p.status == PropertyStatus.pickedUp;

        final bool isExpired = p.status == PropertyStatus.expired;
        final bool isUnderReview = p.status == PropertyStatus.underReview;
        final bool isRejected = p.status == PropertyStatus.rejected;

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            elevation: 2,
            title: const Text('Property Details'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // ── Under Review banner ───────────────────────────────────
              if (isUnderReview) ...[
                _banner(
                  icon: Icons.manage_search_outlined,
                  iconColor: const Color(0xFFFF8F00),
                  bg: const Color(0xFFFFF8E1),
                  border: const Color(0xFFFF8F00),
                  title: 'Under Review',
                  body:
                      'Your re-review request has been submitted. '
                      'Admin will review and either approve (restore to Pending) '
                      'or deny the request.\n'
                      'You will be notified of the outcome.',
                  margin: const EdgeInsets.only(bottom: 12),
                ),
              ],

              // ── Rejected banner + re-review button ────────────────────
              if (isRejected) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.cancel_outlined,
                            color: Colors.red,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Property Rejected',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.red,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if ((p.rejectionCategory ?? '').isNotEmpty)
                        Text(
                          'Reason: ${PropertyService.rejectionCategoryLabel(p.rejectionCategory!)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      if ((p.rejectionReason ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Details: ${p.rejectionReason!.trim()}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                      if (p.rejectedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Rejected at: ${_fmt16(p.rejectedAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Text(
                        'If you believe this rejection is an error, you may '
                        'request a re-review. Admin will assess and decide whether '
                        'to restore your property to Pending.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.manage_search_outlined),
                          label: const Text('Request Re-Review'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final ok = await PropertyService.requestReReview(p);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Re-review requested ✅ — awaiting admin decision'
                                      : 'Could not submit request ❌',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Expired banner ────────────────────────────────────────
              if (isExpired) ...[
                _banner(
                  icon: Icons.timer_off_outlined,
                  iconColor: const Color(0xFF4E342E),
                  bg: const Color(0xFF4E342E),
                  border: const Color(0xFF4E342E),
                  title: 'Property Expired',
                  body:
                      'This property was registered but no payment was '
                      'recorded at the desk within 10 days.\n'
                      'Please visit the desk or contact admin to restore it to Pending.',
                  margin: const EdgeInsets.only(bottom: 12),
                  lightText: true,
                ),
              ],

              // ── Main info card ────────────────────────────────────────
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
                              color: isExpired
                                  ? const Color(
                                      0xFF4E342E,
                                    ).withValues(alpha: 0.10)
                                  : isRejected || isUnderReview
                                  ? Colors.orange.withValues(alpha: 0.10)
                                  : Colors.blue.shade50,
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
                            onPressed: () =>
                                _copy(context, 'Phone', p.receiverPhone),
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
                            const SizedBox(width: 4),
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
                      if (loadedBy.isNotEmpty)
                        Text(
                          'Loaded by: $loadedBy',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Trip progress — hide for expired / under review / rejected
              if (!isExpired && !isUnderReview && !isRejected) ...[
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
                        'Trip not started yet. Progress will appear once the driver departs.',
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
              ],

              // OTP notice
              if (p.status == PropertyStatus.delivered) ...[
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pickup OTP',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'An OTP has been issued for pickup. '
                          'The station staff will ask the receiver for their phone number '
                          'and the OTP to confirm pickup.\n\n'
                          'If the receiver has not received their OTP, ask the desk officer to resend it.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Pickup QR
              if (p.status == PropertyStatus.pickedUp ||
                  p.pickedUpAt != null) ...[
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
                else if (!qrReadyForDisplay)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Pickup QR not issued yet.\nAsk station staff/admin to re-issue.',
                      ),
                    ),
                  )
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
                              onPressed: () async {
                                final ok =
                                    await PickupQrService.refreshForDelivered(
                                      p,
                                    );
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
                              data: pickupQrPayload as String,
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
                            pickupQrPayload as String,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton.icon(
                              onPressed: () => _copy(
                                context,
                                'Pickup QR',
                                pickupQrPayload as String,
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

              // Payment
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
                if (payments.length != 1)
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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${x.currency} ${x.amount}  •  ${x.method.trim().isEmpty ? '—' : x.method}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Station: ${x.station.trim().isEmpty ? '—' : x.station}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    'TxnRef: ${x.txnRef.trim().isEmpty ? '—' : x.txnRef}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _fmt16(x.createdAt),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],

              const SizedBox(height: 12),

              // Timeline
              const Text(
                'Timeline',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    _timelineRow('Pending', p.createdAt, true),
                    _timelineRow('Loaded', p.loadedAt, loadedDone),
                    _timelineRow(
                      'In Transit',
                      p.inTransitAt,
                      p.inTransitAt != null,
                    ),
                    _timelineRow(
                      'Delivered',
                      p.deliveredAt,
                      p.deliveredAt != null,
                    ),
                    _timelineRow(
                      'Picked Up',
                      p.pickedUpAt,
                      p.pickedUpAt != null,
                    ),
                    if (isRejected || p.rejectedAt != null)
                      _timelineRow(
                        'Rejected',
                        p.rejectedAt,
                        true,
                        color: Colors.red,
                      ),
                    if (isUnderReview)
                      _timelineRow(
                        'Under Review — awaiting admin decision',
                        null,
                        true,
                        color: const Color(0xFFFF8F00),
                      ),
                    if (isExpired)
                      _timelineRow(
                        'Expired — no payment within 10 days',
                        null,
                        true,
                        color: const Color(0xFF4E342E),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  static Widget _banner({
    required IconData icon,
    required Color iconColor,
    required Color bg,
    required Color border,
    required String title,
    required String body,
    EdgeInsets margin = EdgeInsets.zero,
    bool lightText = false,
  }) {
    final titleColor = lightText ? Colors.white : iconColor;
    final bodyColor = lightText ? Colors.white70 : Colors.black54;
    final bgColor = lightText
        ? bg.withValues(alpha: 0.85)
        : bg.withValues(alpha: 0.08);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: margin,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(fontSize: 13, color: bodyColor)),
        ],
      ),
    );
  }

  static Widget _timelineRow(
    String label,
    DateTime? at,
    bool done, {
    Color? color,
  }) {
    final effectiveColor = color ?? (done ? Colors.green : Colors.grey);
    return ListTile(
      dense: true,
      leading: Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: effectiveColor,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: color != null ? FontWeight.w700 : null,
        ),
      ),
      subtitle: at != null
          ? Text(_fmt16(at), style: const TextStyle(fontSize: 12))
          : null,
    );
  }
}
