import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/staff_station_mode.dart';
import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/user_role.dart';

import '../../services/hive_service.dart';
import '../../services/property_service.dart';
import '../../services/session.dart';
import '../../services/audit_service.dart';
import '../../services/role_guard.dart';

// QR scan screen
import '../../screens/admin/pickup_qr_scanner_screen.dart';

// ✅ Pickup QR service (single source of truth for pickup QR)
import '../../services/pickup_qr_service.dart';

class StaffStationScreen extends StatelessWidget {
  final StaffStationMode mode;
  const StaffStationScreen({super.key, required this.mode});

  bool _hasValidPhone(Property p) {
    final phone = p.receiverPhone.trim();
    return phone.length >= 9; // simple safety check
  }

  bool _hasOtp(Property p) => (p.pickupOtp ?? '').trim().isNotEmpty;

  // ✅ QR expiry helper (5 min TTL from PickupQrService)
  bool _isPickupQrExpired(Property p) {
    final issued = p.qrIssuedAt;
    if (issued == null) return true;
    return DateTime.now().isAfter(issued.add(PickupQrService.ttl));
  }

  Future<void> _refreshQr(BuildContext context, Property p) async {
    final messenger = ScaffoldMessenger.of(context);

    final ok = await PickupQrService.refreshForDelivered(p);

    if (!context.mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Pickup QR refreshed ✅' : 'Cannot refresh QR ❌'),
      ),
    );
  }

  Future<void> _copyOtp(BuildContext context, Property p) async {
    final otp = (p.pickupOtp ?? '').trim();
    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP missing ❌')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: otp));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('OTP copied ✅')),
    );
  }

  Future<void> _callReceiver(BuildContext context, Property p) async {
    final phone = p.receiverPhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receiver phone missing ❌')),
      );
      return;
    }

    final uri = Uri.parse('tel:$phone');
    final can = await canLaunchUrl(uri);

    if (!context.mounted) return;

    if (!can) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot start call on this device ❌')),
      );
      return;
    }

    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasAny({UserRole.staff, UserRole.admin})) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final station = Session.currentStationName;
    if (station == null || station.trim().isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('No station selected.\nGo back and select one.'),
        ),
      );
    }

    final box = HiveService.propertyBox();

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text('Station: $station')),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box b, _) {
          final items = b.values.where((p) {
            return p.destination.trim().toLowerCase() ==
                station.trim().toLowerCase();
          }).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final arriving =
              items.where((p) => p.status == PropertyStatus.inTransit).toList();
          final delivered =
              items.where((p) => p.status == PropertyStatus.delivered).toList();

          final showArriving = mode == StaffStationMode.arriving;
          final showPickup = mode == StaffStationMode.pickup;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (showArriving) ...[
                _sectionTitle('Arriving (In Transit) — ${arriving.length}'),
                if (arriving.isEmpty)
                  emptyHint('No arriving cargo for this station yet.'),
                for (final p in arriving) _arrivingTile(context, p),
                const SizedBox(height: 16),
              ],
              if (showPickup) ...[
                _sectionTitle(
                    'Delivered (Waiting OTP Pickup) — ${delivered.length}'),
                if (delivered.isEmpty)
                  emptyHint(
                      'No delivered cargo waiting pickup at this station yet.'),
                for (final p in delivered) _deliveredTile(context, p),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: const TextStyle(color: Colors.black54)),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      );

  Widget _arrivingTile(BuildContext context, Property p) {
    final canMarkDelivered = RoleGuard.hasAny({UserRole.staff, UserRole.admin}) &&
        p.status == PropertyStatus.inTransit;

    return Card(
      child: ListTile(
        title: Text(p.receiverName),
        subtitle: Text('${p.destination} • ${p.receiverPhone}'),
        trailing: ElevatedButton(
          onPressed: !canMarkDelivered
              ? null
              : () async {
                  await PropertyService.markDelivered(p);

                  final fresh = HiveService.propertyBox().get(p.key) ?? p;

                  await AuditService.log(
                    action: 'staff_mark_delivered',
                    propertyKey: fresh.key.toString(),
                    details:
                        'Marked delivered at station: ${Session.currentStationName}',
                  );

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Marked Delivered ✅')),
                  );
                },
          child: const Text('Mark Delivered'),
        ),
      ),
    );
  }

  Widget _deliveredTile(BuildContext context, Property p) {
    final locked = PropertyService.isOtpLocked(p);
    final expired = PropertyService.isOtpExpired(p);
    final lockMins = PropertyService.remainingLockMinutes(p);

    final qrExpired = _isPickupQrExpired(p);

    String statusLine = 'OTP required • ${p.receiverPhone}';
    if (locked) statusLine = 'Locked ($lockMins min) • ${p.receiverPhone}';
    if (!locked && expired) {
      statusLine = '⏱ OTP expired • Ask admin to reset • ${p.receiverPhone}';
    }

    final isAdmin = RoleGuard.hasRole(UserRole.admin);
    final hasValidPhone = _hasValidPhone(p);
    final hasOtp = _hasOtp(p);

    return Card(
      child: ListTile(
        title: Text(p.receiverName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(statusLine),
            const SizedBox(height: 4),
            Text(
              'Attempts: ${p.otpAttempts} / 3',
              style: const TextStyle(fontSize: 12),
            ),
            if (!hasValidPhone)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Receiver phone missing/invalid — cannot send WhatsApp/call.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            if (!hasOtp)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'OTP missing — ask admin to reset.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            if (qrExpired && !locked && !expired)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Pickup QR expired — tap Refresh QR.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✅ Manual OTP
            OutlinedButton(
              onPressed: (locked || expired)
                  ? null
                  : () async {
                      final otp = await _askOtp(context);
                      if (otp == null || otp.trim().isEmpty) return;

                      final ok = await PropertyService.confirmPickupWithOtp(
                        p,
                        otp.trim(),
                      );

                      final st = Session.currentStationName ?? '—';
                      await AuditService.log(
                        action: ok
                            ? 'staff_confirm_pickup_ok'
                            : 'staff_confirm_pickup_failed',
                        propertyKey: p.key.toString(),
                        details: 'Station: $st | ${ok ? 'OTP ok' : 'OTP failed'}',
                      );

                      if (!context.mounted) return;

                      final lockedNow = PropertyService.isOtpLocked(p);
                      final expiredNow = PropertyService.isOtpExpired(p);
                      final lockMinsNow =
                          PropertyService.remainingLockMinutes(p);

                      final msg = ok
                          ? 'Pickup confirmed ✅'
                          : lockedNow
                              ? 'Too many attempts — locked for $lockMinsNow min'
                              : expiredNow
                                  ? 'OTP expired ⏱ Ask admin to reset OTP.'
                                  : 'Wrong OTP ❌';

                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(msg)));
                    },
              child: Text(locked ? 'Locked' : expired ? 'Expired' : 'Confirm OTP'),
            ),

            const SizedBox(width: 6),

            // ✅ WhatsApp OTP (improved)
            OutlinedButton(
              onPressed: (locked || expired || !hasValidPhone || !hasOtp)
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);

                      final err =
                          await PropertyService.sendPickupOtpViaWhatsApp(p);

                      if (!context.mounted) return;

                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            err ?? 'WhatsApp opened ✅ (tap send)',
                          ),
                        ),
                      );
                    },
              child: const Text('WhatsApp OTP'),
            ),

            const SizedBox(width: 6),

            // ✅ Copy OTP fallback
            IconButton(
              tooltip: 'Copy OTP',
              onPressed: (!hasOtp) ? null : () => _copyOtp(context, p),
              icon: const Icon(Icons.copy),
            ),

            // ✅ Call receiver fallback
            IconButton(
              tooltip: 'Call receiver',
              onPressed:
                  (!hasValidPhone) ? null : () => _callReceiver(context, p),
              icon: const Icon(Icons.call),
            ),

            const SizedBox(width: 6),

            // ✅ Refresh QR (only if expired)
            if (qrExpired) ...[
              OutlinedButton(
                onPressed: (locked || expired) ? null : () => _refreshQr(context, p),
                child: const Text('Refresh QR'),
              ),
              const SizedBox(width: 6),
            ],

            // ✅ QR Scan pickup (still requires OTP)
            OutlinedButton(
              onPressed: (locked || expired)
                  ? null
                  : () async {
                      final raw = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PickupQrScannerScreen(),
                        ),
                      );

                      if (raw == null || raw.trim().isEmpty) return;
                      if (!context.mounted) return;

                      final parsed = PickupQrService.parsePayload(raw.trim());
                      if (parsed == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invalid pickup QR ❌')),
                        );
                        return;
                      }

                      final tileKey = (p.key is int)
                          ? (p.key as int)
                          : int.tryParse(p.key.toString());

                      if (tileKey == null || parsed.propertyKey != tileKey) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('This QR does not match this property ❌'),
                          ),
                        );
                        return;
                      }

                      final otp = await _askOtp(context);
                      if (otp == null || otp.trim().isEmpty) return;
                      if (!context.mounted) return;

                      final err = await PickupQrService.confirmPickup(
                        propertyKey: parsed.propertyKey,
                        scannedNonce: parsed.nonce,
                        enteredOtp: otp.trim(),
                      );

                      final ok = err == null;
                      await AuditService.log(
                        action:
                            ok ? 'staff_qr_pickup_ok' : 'staff_qr_pickup_failed',
                        propertyKey: p.key.toString(),
                        details: ok ? 'Pickup via QR OK' : 'QR rejected: $err',
                      );

                      if (!context.mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ok ? 'Pickup via QR ✅' : err)),
                      );
                    },
              child: const Text('Scan QR'),
            ),

            if (isAdmin) ...[
              const SizedBox(width: 6),
              PopupMenuButton(
                tooltip: 'Admin tools',
                onSelected: (v) async {
                  if (v == 'unlock') {
                    await PropertyService.adminUnlockOtp(p);

                    await AuditService.log(
                      action: 'admin_unlock_otp',
                      propertyKey: p.key.toString(),
                      details: 'OTP unlocked by admin',
                    );

                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('OTP unlocked ✅')),
                    );
                  }

                  if (v == 'reset') {
                    await PropertyService.adminResetOtp(p);

                    await AuditService.log(
                      action: 'admin_reset_otp',
                      propertyKey: p.key.toString(),
                      details: 'OTP reset by admin',
                    );

                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('OTP reset ✅')),
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'unlock', child: Text('Unlock OTP')),
                  PopupMenuItem(
                    value: 'reset',
                    child: Text('Reset OTP (new code)'),
                  ),
                ],
                child: const Icon(Icons.more_vert),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future _askOtp(BuildContext context) async {
    final c = TextEditingController();
    try {
      return await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Enter OTP'),
          content: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '6-digit OTP',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    } finally {
      c.dispose();
    }
  }
}