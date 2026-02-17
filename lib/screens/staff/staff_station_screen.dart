import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasAny({UserRole.staff, UserRole.admin})) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final station = Session.currentStationName;

    if (station == null || station.trim().isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('No station selected. Go back and select one.'),
        ),
      );
    }

    final box = HiveService.propertyBox();

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text('Station: $station')),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<Property> b, _) {
          final items = b.values.where((p) {
            return p.destination.trim().toLowerCase() ==
                station.trim().toLowerCase();
          }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final arriving = items
              .where((p) => p.status == PropertyStatus.inTransit)
              .toList();

          final delivered = items
              .where((p) => p.status == PropertyStatus.delivered)
              .toList();

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
                  'Delivered (Waiting OTP Pickup) — ${delivered.length}',
                ),
                if (delivered.isEmpty)
                  emptyHint(
                    'No delivered cargo waiting pickup at this station yet.',
                  ),
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
    final canMarkDelivered =
        RoleGuard.hasAny({UserRole.staff, UserRole.admin}) &&
        p.status == PropertyStatus.inTransit;

    return Card(
      child: ListTile(
        title: Text(p.receiverName),
        subtitle: Text('${p.destination} • ${p.receiverPhone}'),
        trailing: ElevatedButton(
          onPressed: !canMarkDelivered
              ? null
              : () async {
                  // ✅ Mark delivered (this should issue OTP + pickup QR inside PropertyService.markDelivered)
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

    String statusLine = 'OTP required • ${p.receiverPhone}';
    if (locked) statusLine = '🔒 Locked ($lockMins min) • ${p.receiverPhone}';
    if (!locked && expired) {
      statusLine = '⏱ OTP expired • Ask admin to reset • ${p.receiverPhone}';
    }

    final isAdmin = RoleGuard.hasRole(UserRole.admin);

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
                        details:
                            'Station: $st | ${ok ? 'OTP ok' : 'OTP failed'}',
                      );

                      if (!context.mounted) return;

                      final lockedNow = PropertyService.isOtpLocked(p);
                      final expiredNow = PropertyService.isOtpExpired(p);
                      final lockMinsNow = PropertyService.remainingLockMinutes(
                        p,
                      );

                      final msg = ok
                          ? 'Pickup confirmed ✅'
                          : lockedNow
                          ? 'Too many attempts — locked for $lockMinsNow min 🔒'
                          : expiredNow
                          ? 'OTP expired ⏱ Ask admin to reset OTP.'
                          : 'Wrong OTP ❌';

                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(msg)));
                    },
              child: Text(
                locked
                    ? 'Locked'
                    : expired
                    ? 'Expired'
                    : 'Confirm OTP',
              ),
            ),

            const SizedBox(width: 6),

            // ✅ WhatsApp OTP
            OutlinedButton(
              onPressed: (locked || expired)
                  ? null
                  : () async {
                      final ok = await PropertyService.sendPickupOtpViaWhatsApp(
                        p,
                      );

                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'WhatsApp opened ✅ (tap send)'
                                : 'Could not open WhatsApp ❌',
                          ),
                        ),
                      );
                    },
              child: const Text('WhatsApp OTP'),
            ),

            const SizedBox(width: 6),

            // ✅ QR Scan pickup (still requires OTP)
            OutlinedButton(
              onPressed: (locked || expired)
                  ? null
                  : () async {
                      final raw = await Navigator.push<String?>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PickupQrScannerScreen(),
                        ),
                      );

                      if (raw == null || raw.trim().isEmpty) return;
                      if (!context.mounted) return;

                      // 1️⃣ Parse QR
                      final parsed = PickupQrService.parsePayload(raw.trim());
                      if (parsed == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invalid pickup QR ❌')),
                        );
                        return;
                      }

                      // 2️⃣ Safety: QR must match this property
                      final tileKey = (p.key is int)
                          ? (p.key as int)
                          : int.tryParse(p.key.toString());

                      if (tileKey == null || parsed.propertyKey != tileKey) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'This QR does not match this property ❌',
                            ),
                          ),
                        );
                        return;
                      }

                      // 3️⃣ Ask OTP (authorization)
                      final otp = await _askOtp(context);
                      if (otp == null || otp.trim().isEmpty) return;
                      if (!context.mounted) return;

                      // 4️⃣ Confirm pickup
                      final err = await PickupQrService.confirmPickup(
                        propertyKey: parsed.propertyKey,
                        scannedNonce: parsed.nonce,
                        enteredOtp: otp.trim(),
                      );

                      final ok = err == null;

                      await AuditService.log(
                        action: ok
                            ? 'staff_qr_pickup_ok'
                            : 'staff_qr_pickup_failed',
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
              PopupMenuButton<String>(
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

  Future<String?> _askOtp(BuildContext context) async {
    final c = TextEditingController();
    try {
      return await showDialog<String?>(
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
