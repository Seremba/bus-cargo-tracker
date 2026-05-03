import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/payment_record.dart';
import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/trip.dart';
import '../../models/trip_status.dart';
import '../../services/hive_service.dart';
import '../../services/user_resolver.dart';
import '../../services/property_service.dart';
import '../../services/property_ttl_service.dart';

class AdminPropertyDetailScreen extends StatelessWidget {
  final Property property;
  const AdminPropertyDetailScreen({super.key, required this.property});

  static String _fmt16(DateTime? d) {
    if (d == null) return '—';
    return d.toLocal().toString().substring(0, 16);
  }

  static String _money(String currency, int amount) {
    final cur = currency.trim().isEmpty ? 'UGX' : currency.trim();
    return '$cur $amount';
  }

  static Trip? _findTrip(Iterable<Trip> trips, String? tripId) {
    if (tripId == null || tripId.trim().isEmpty) return null;
    for (final t in trips) {
      if (t.tripId == tripId.trim()) return t;
    }
    return null;
  }

  String _statusLabel(PropertyStatus s) {
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

  String _tripStatusLabel(TripStatus s) {
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied ✅')));
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
        HiveService.userBox().listenable(),
      ]),
      builder: (context, _) {
        // Always read the freshest copy from the box.
        final p = propertyBox.values.firstWhere(
          (x) => x.key == property.key,
          orElse: () => property,
        );

        final trip = _findTrip(tripBox.values, p.tripId);

        final totalCps = trip?.checkpoints.length ?? 0;
        final lastIndex = trip?.lastCheckpointIndex ?? -1;
        final reachedCount = (lastIndex + 1).clamp(0, totalCps);
        final progress =
            totalCps == 0 ? 0.0 : (reachedCount / totalCps).clamp(0.0, 1.0);

        String? nextCheckpoint;
        if (trip != null) {
          final nextIndex = trip.lastCheckpointIndex + 1;
          if (nextIndex >= 0 && nextIndex < trip.checkpoints.length) {
            nextCheckpoint = trip.checkpoints[nextIndex].name;
          } else {
            nextCheckpoint = trip.status == TripStatus.cancelled
                ? 'Trip cancelled'
                : trip.status == TripStatus.ended
                    ? 'Trip ended'
                    : 'Completed';
          }
        }

        final currency = p.currency.trim().isEmpty ? 'UGX' : p.currency.trim();
        final paidTotal = p.amountPaidTotal;
        final propKeyStr = p.key.toString();

        final payments = payBox.values
            .whereType<PaymentRecord>()
            .where((x) => x.propertyKey == propKeyStr)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // Resolve sender and loaded-by names via shared UserResolver
        final senderLabel = UserResolver.senderName(p.createdByUserId);
        final loadedByLabel = UserResolver.nameFor(p.loadedByUserId);

        final bool loadedDone = p.loadedAt != null ||
            p.status == PropertyStatus.inTransit ||
            p.status == PropertyStatus.delivered ||
            p.status == PropertyStatus.pickedUp;

        final bool isRejected = p.status == PropertyStatus.rejected;
        final bool isExpired = p.status == PropertyStatus.expired;
        final bool isUnderReview = p.status == PropertyStatus.underReview;

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            elevation: 2,
            title: Text(
              p.propertyCode.trim().isEmpty
                  ? 'Property Details'
                  : p.propertyCode,
            ),
            actions: [
              IconButton(
                tooltip: 'Copy property code',
                icon: const Icon(Icons.copy_outlined),
                onPressed: p.propertyCode.trim().isEmpty
                    ? null
                    : () => _copy(context, 'Property code', p.propertyCode),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // ── Status banners ──────────────────────────────────────────
              if (isUnderReview)
                _banner(
                  icon: Icons.manage_search_outlined,
                  color: const Color(0xFFFF8F00),
                  bg: const Color(0xFFFFF8E1),
                  title: 'Under Review',
                  body:
                      'Sender has submitted a re-review request. '
                      'Use the All Properties screen to Approve or Deny.',
                  margin: const EdgeInsets.only(bottom: 10),
                ),

              if (isRejected)
                _banner(
                  icon: Icons.cancel_outlined,
                  color: Colors.red,
                  bg: const Color(0xFFFFEBEE),
                  title:
                      'Rejected — ${PropertyService.rejectionCategoryLabel(p.rejectionCategory ?? '')}',
                  body: (p.rejectionReason ?? '').trim().isEmpty
                      ? 'No additional details provided.'
                      : p.rejectionReason!.trim(),
                  margin: const EdgeInsets.only(bottom: 10),
                ),

              if (isExpired)
                _banner(
                  icon: Icons.timer_off_outlined,
                  color: const Color(0xFF4E342E),
                  bg: const Color(0xFFEFEBE9),
                  title: 'Expired',
                  body:
                      'No payment was recorded within 10 days of registration.',
                  margin: const EdgeInsets.only(bottom: 10),
                  actions: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restore),
                      label: const Text('Restore to Pending'),
                      onPressed: () async {
                        final ok =
                            await PropertyTtlService.adminRestoreExpired(p);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Restored to Pending ✅'
                              : 'Could not restore ❌'),
                        ));
                      },
                    ),
                  ],
                ),

              // ── Core info card ──────────────────────────────────────────
              _sectionCard(children: [
                _sectionTitle('Property'),
                const SizedBox(height: 10),
                _row('Status', _statusLabel(p.status)),
                _row(
                  'Property Code',
                  p.propertyCode.trim().isEmpty ? '—' : p.propertyCode,
                  copy: () =>
                      _copy(context, 'Property code', p.propertyCode),
                ),
                _row(
                  'Tracking Code',
                  p.trackingCode.trim().isEmpty ? '—' : p.trackingCode,
                  copy: () =>
                      _copy(context, 'Tracking code', p.trackingCode),
                ),
                const Divider(height: 20),
                _sectionTitle('Receiver'),
                const SizedBox(height: 8),
                _row('Name', p.receiverName.trim().isEmpty ? '—' : p.receiverName),
                _row(
                  'Phone',
                  p.receiverPhone.trim().isEmpty ? '—' : p.receiverPhone,
                  copy: () =>
                      _copy(context, 'Receiver phone', p.receiverPhone),
                ),
                _row('Destination',
                    p.destination.trim().isEmpty ? '—' : p.destination),
                const Divider(height: 20),
                _sectionTitle('Shipment'),
                const SizedBox(height: 8),
                _row('Description',
                    p.description.trim().isEmpty ? '—' : p.description),
                _row('Items', '${p.itemCount}'),
                _row('Route',
                    p.routeName.trim().isEmpty ? '—' : p.routeName),
                _row('Sender', senderLabel),
                const Divider(height: 20),
                _sectionTitle('Timestamps'),
                const SizedBox(height: 8),
                _row('Created', _fmt16(p.createdAt)),
                if (p.loadedAt != null || loadedDone)
                  _row('Loaded', _fmt16(p.loadedAt)),
                if (p.loadedAtStation.trim().isNotEmpty)
                  _row('Loaded at station', p.loadedAtStation.trim()),
                _row('Loaded by', loadedByLabel),
                if (p.inTransitAt != null)
                  _row('In Transit', _fmt16(p.inTransitAt)),
                if (p.deliveredAt != null)
                  _row('Delivered', _fmt16(p.deliveredAt)),
                if (p.pickedUpAt != null)
                  _row('Picked Up', _fmt16(p.pickedUpAt)),
                if (isRejected && p.rejectedAt != null)
                  _row('Rejected', _fmt16(p.rejectedAt)),
              ]),

              const SizedBox(height: 12),

              // ── Trip progress ───────────────────────────────────────────
              if (!isExpired && !isRejected) ...[
                _sectionCard(children: [
                  _sectionTitle('Trip Progress'),
                  const SizedBox(height: 10),
                  if (trip == null)
                    const Text(
                      'Trip not started yet. Progress will appear once the driver departs.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    )
                  else ...[
                    _row('Trip Status', _tripStatusLabel(trip.status)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    _row('Checkpoints', '$reachedCount / $totalCps reached'),
                    if (nextCheckpoint != null)
                      _row('Next checkpoint', nextCheckpoint),
                  ],
                ]),
                const SizedBox(height: 12),
              ],

              // ── Payment ─────────────────────────────────────────────────
              _sectionCard(children: [
                _sectionTitle('Payment'),
                const SizedBox(height: 10),
                if (paidTotal <= 0 && payments.isEmpty)
                  const Text(
                    'No payment recorded yet.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  )
                else ...[
                  _row('Total Paid',
                      _money(currency, paidTotal),
                      bold: true),
                  if (p.lastPaymentMethod.trim().isNotEmpty)
                    _row('Method', p.lastPaymentMethod.trim()),
                  if (p.lastPaidAtStation.trim().isNotEmpty)
                    _row('Station', p.lastPaidAtStation.trim()),
                  if (p.lastTxnRef.trim().isNotEmpty)
                    _row('TxnRef', p.lastTxnRef.trim()),
                  if (p.lastPaidAt != null)
                    _row('Last paid at', _fmt16(p.lastPaidAt)),
                  if (payments.length > 1) ...[
                    const SizedBox(height: 10),
                    Text(
                      'History (${payments.length} transactions)',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    for (final x in payments) _paymentRow(x),
                  ],
                ],
              ]),

              const SizedBox(height: 12),

              // ── Timeline ────────────────────────────────────────────────
              _sectionCard(children: [
                _sectionTitle('Timeline'),
                const SizedBox(height: 8),
                _timelineRow('Pending', p.createdAt, true),
                _timelineRow('Loaded', p.loadedAt, loadedDone),
                _timelineRow(
                    'In Transit', p.inTransitAt, p.inTransitAt != null),
                _timelineRow(
                    'Delivered', p.deliveredAt, p.deliveredAt != null),
                _timelineRow(
                    'Picked Up', p.pickedUpAt, p.pickedUpAt != null),
                if (isRejected || p.rejectedAt != null)
                  _timelineRow('Rejected', p.rejectedAt, true,
                      color: Colors.red),
                if (isUnderReview)
                  _timelineRow('Under Review (pending admin decision)',
                      null, true,
                      color: const Color(0xFFFF8F00)),
                if (isExpired)
                  _timelineRow('Expired — no payment within 10 days',
                      null, true,
                      color: const Color(0xFF4E342E)),
              ]),

              // ── Aggregate version (debug info for admin) ────────────────
              const SizedBox(height: 12),
              _sectionCard(children: [
                _sectionTitle('Sync Info'),
                const SizedBox(height: 8),
                _row('Aggregate Version', '${p.aggregateVersion}'),
                if ((p.commitHash ?? '').trim().isNotEmpty)
                  _row('Commit Hash', p.commitHash!.trim()),
                _row('Locked', p.isLocked ? 'Yes' : 'No'),
              ]),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionCard({required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    );
  }

  Widget _row(String label, String value,
      {VoidCallback? copy, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (copy != null)
            GestureDetector(
              onTap: copy,
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.copy_outlined, size: 15, color: Colors.black38),
              ),
            ),
        ],
      ),
    );
  }

  Widget _paymentRow(PaymentRecord x) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${x.currency} ${x.amount}  •  '
                  '${x.kind == "refund" ? "Refund" : x.kind == "adjustment" ? "Adjustment" : "Payment"}'
                  '${x.method.trim().isNotEmpty ? "  •  ${x.method}" : ""}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                if (x.station.trim().isNotEmpty)
                  Text('Station: ${x.station}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (x.txnRef.trim().isNotEmpty)
                  Text('TxnRef: ${x.txnRef}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (x.note.trim().isNotEmpty)
                  Text('Note: ${x.note}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          Text(
            x.createdAt.toLocal().toString().substring(0, 16),
            style: const TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required Color bg,
    required String title,
    required String body,
    EdgeInsets margin = EdgeInsets.zero,
    List<Widget> actions = const [],
  }) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: color,
                      fontSize: 13)),
            ),
          ]),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(body,
                style: TextStyle(
                    fontSize: 12, color: color.withValues(alpha: 0.80))),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...actions,
          ],
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
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: effectiveColor,
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: color,
          fontWeight: color != null ? FontWeight.w700 : null,
        ),
      ),
      subtitle: at != null
          ? Text(at.toLocal().toString().substring(0, 16),
              style: const TextStyle(fontSize: 11))
          : null,
    );
  }
}