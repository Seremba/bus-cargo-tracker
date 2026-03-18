import 'package:bus_cargo_tracker/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/outbound_message.dart';
import '../../models/staff_station_mode.dart';
import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/user_role.dart';

import '../../services/hive_service.dart';
import '../../services/outbound_message_service.dart';
import '../../services/property_service.dart';
import '../../services/session.dart';
import '../../services/audit_service.dart';
import '../../services/role_guard.dart';
import '../../services/pickup_qr_service.dart';

import '../../screens/admin/pickup_qr_scanner_screen.dart';

class StaffStationScreen extends StatelessWidget {
  final StaffStationMode mode;
  const StaffStationScreen({super.key, required this.mode});

  bool _hasValidPhone(Property p) => p.receiverPhone.trim().length >= 9;

  /// OTP is stored as a hash — non-null/non-empty hash means OTP exists.
  bool _hasOtp(Property p) => (p.pickupOtp ?? '').trim().isNotEmpty;

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

  Future<void> _callReceiver(BuildContext context, Property p) async {
    final phone = p.receiverPhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Receiver phone missing ❌')));
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

  // ---------------------------------------------------------------------------
  // Admin reset OTP — returns plaintext so staff can act on it immediately.
  // ---------------------------------------------------------------------------
  Future<void> _adminResetOtpAndShow(BuildContext context, Property p) async {
    final messenger = ScaffoldMessenger.of(context);

    final newOtp = await PropertyService.adminResetOtp(p);

    await AuditService.log(
      action: 'admin_reset_otp',
      propertyKey: p.key.toString(),
      details: 'OTP reset by admin',
    );

    if (!context.mounted) return;

    if (newOtp == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('OTP reset failed ❌')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New OTP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copy or forward this OTP now.\n'
              'It cannot be retrieved again after closing this dialog.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            SelectableText(
              newOtp,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: newOtp));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('OTP copied ✅')));
            },
            child: const Text('Copy'),
          ),
          if (_hasValidPhone(p))
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final err = await PropertyService.sendPickupOtpViaWhatsApp(
                  p,
                  otpPlaintext: newOtp,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(err ?? 'WhatsApp opened ✅ (tap send)'),
                  ),
                );
              },
              child: const Text('Send via WhatsApp'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // F3: check whether an OTP SMS was queued/opened/sent for this property
  // ---------------------------------------------------------------------------
  bool _otpSmsSentOrQueued(String propertyKeyStr) {
    final box = HiveService.outboundMessageBox();
    return box.values.whereType<OutboundMessage>().any((m) {
      if (m.propertyKey != propertyKeyStr) return false;
      final ch = m.channel.trim().toLowerCase();
      if (ch != 'sms') return false;
      final st = m.status.trim().toLowerCase();
      return st == OutboundMessageService.statusQueued ||
          st == OutboundMessageService.statusOpened ||
          st == OutboundMessageService.statusSent;
    });
  }
  // ---------------------------------------------------------------------------

  // =========================
  // Build
  // =========================
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
      body: AnimatedBuilder(
        // F3: also listen to outboundMessageBox so the SMS badge updates live
        animation: Listenable.merge([
          box.listenable(),
          HiveService.outboundMessageBox().listenable(),
        ]),
        builder: (context, _) {
          final items = box.values.where((p) {
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              if (showArriving) ...[
                _sectionTitle(
                  context,
                  Icons.inventory_2_outlined,
                  'Arriving (In Transit)',
                  arriving.length,
                ),
                if (arriving.isEmpty)
                  _emptyState(
                    Icons.local_shipping_outlined,
                    'No arriving cargo for this station yet.',
                  )
                else
                  for (final p in arriving) _arrivingTile(context, p),
                const SizedBox(height: 16),
              ],
              if (showPickup) ...[
                _sectionTitle(
                  context,
                  Icons.lock_outline,
                  'Delivered — Waiting Pickup',
                  delivered.length,
                ),
                if (delivered.isEmpty)
                  _emptyState(
                    Icons.inbox_outlined,
                    'No delivered cargo waiting pickup at this station yet.',
                  )
                else
                  for (final p in delivered) _deliveredTile(context, p),
              ],
            ],
          );
        },
      ),
    );
  }

  // =========================
  // Section title
  // =========================
  Widget _sectionTitle(
    BuildContext context,
    IconData icon,
    String text,
    int count,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: count > 0
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: count > 0 ? AppColors.primary : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // Empty state
  // =========================
  Widget _emptyState(IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // Initials avatar
  // =========================
  Widget _initialsAvatar(String fullName, Color color) {
    final parts = fullName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : fullName.isNotEmpty
        ? fullName.substring(0, fullName.length.clamp(0, 2)).toUpperCase()
        : '??';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  // =========================
  // Arriving tile
  // =========================
  Widget _arrivingTile(BuildContext context, Property p) {
    final canMarkDelivered =
        RoleGuard.hasAny({UserRole.staff, UserRole.admin}) &&
        p.status == PropertyStatus.inTransit;
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _initialsAvatar(p.receiverName, Colors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.receiverName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 12, color: muted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          p.destination,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 12, color: muted),
                      const SizedBox(width: 3),
                      Text(
                        p.receiverPhone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _statusPill('In Transit', Colors.blue),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: !canMarkDelivered
                      ? null
                      : () async {
                          await PropertyService.markDelivered(p);
                          final fresh =
                              HiveService.propertyBox().get(p.key) ?? p;
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Mark Delivered',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // Delivered / awaiting pickup tile
  // =========================
  Widget _deliveredTile(BuildContext context, Property p) {
    final locked = PropertyService.isOtpLocked(p);
    final expired = PropertyService.isOtpExpired(p);
    final lockMins = PropertyService.remainingLockMinutes(p);
    final qrExpired = _isPickupQrExpired(p);
    final isAdmin = RoleGuard.hasRole(UserRole.admin);
    final hasValidPhone = _hasValidPhone(p);
    final hasOtp = _hasOtp(p);
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    // F3: check if OTP was queued/sent via SMS for this property
    final pKeyStr = p.key.toString();
    final otpSmsSent = _otpSmsSentOrQueued(pKeyStr);

    String otpStatus;
    Color otpColor;
    if (locked) {
      otpStatus = 'Locked ($lockMins min)';
      otpColor = Colors.red;
    } else if (expired) {
      otpStatus = 'OTP Expired';
      otpColor = Colors.orange.shade700;
    } else {
      otpStatus = 'OTP Required';
      otpColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _initialsAvatar(p.receiverName, Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.receiverName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.phone_outlined, size: 12, color: muted),
                          const SizedBox(width: 3),
                          Text(
                            p.receiverPhone.trim().isEmpty
                                ? '—'
                                : p.receiverPhone,
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _statusPill('Delivered', Colors.green),
                    const SizedBox(height: 4),
                    _statusPill(otpStatus, otpColor),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Attempts row ──
            Row(
              children: [
                Icon(Icons.repeat_outlined, size: 13, color: muted),
                const SizedBox(width: 4),
                Text(
                  'Attempts: ${p.otpAttempts} / 3',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),

            // ── F3: OTP SMS delivery confirmation badge ──
            if (otpSmsSent) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.sms_outlined, size: 13, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    'OTP delivery confirmed (SMS queued)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            // ── Warnings ──
            if (!hasValidPhone || !hasOtp || (qrExpired && !locked && !expired))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hasValidPhone)
                      _warningRow(
                        'Receiver phone missing — cannot send WhatsApp/call.',
                      ),
                    if (!hasOtp)
                      _warningRow('OTP missing — ask admin to reset.'),
                    if (qrExpired && !locked && !expired)
                      _warningRow('Pickup QR expired — tap Refresh QR.'),
                  ],
                ),
              ),

            const SizedBox(height: 10),

            // ── Action buttons ──
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Confirm OTP
                _tileButton(
                  label: locked
                      ? 'Locked'
                      : expired
                      ? 'Expired'
                      : 'Confirm OTP',
                  icon: Icons.lock_open_outlined,
                  disabled: locked || expired,
                  onTap: () async {
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
                    final lockMinsNow = PropertyService.remainingLockMinutes(p);
                    final msg = ok
                        ? 'Pickup confirmed ✅'
                        : lockedNow
                        ? 'Too many attempts — locked for $lockMinsNow min'
                        : expiredNow
                        ? 'OTP expired ⏱ Ask admin to reset.'
                        : 'Wrong OTP ❌';
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(msg)));
                  },
                ),

                // WhatsApp OTP (admin only — requires plaintext via reset)
                if (isAdmin)
                  _tileButton(
                    label: 'WhatsApp OTP',
                    icon: Icons.chat_outlined,
                    disabled: locked || expired || !hasValidPhone,
                    onTap: () async {
                      final newOtp = await PropertyService.adminResetOtp(p);
                      if (!context.mounted) return;
                      if (newOtp == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not generate OTP ❌'),
                          ),
                        );
                        return;
                      }
                      final err =
                          await PropertyService.sendPickupOtpViaWhatsApp(
                            p,
                            otpPlaintext: newOtp,
                          );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(err ?? 'WhatsApp opened ✅ (tap send)'),
                        ),
                      );
                    },
                  )
                else
                  _tileButton(
                    label: 'WhatsApp OTP',
                    icon: Icons.chat_outlined,
                    disabled: true,
                    onTap: () {},
                  ),

                // Call receiver
                _tileButton(
                  label: 'Call',
                  icon: Icons.phone_outlined,
                  disabled: !hasValidPhone,
                  onTap: () => _callReceiver(context, p),
                ),

                // Refresh QR (only if expired)
                if (qrExpired)
                  _tileButton(
                    label: 'Refresh QR',
                    icon: Icons.qr_code_outlined,
                    disabled: locked || expired,
                    onTap: () => _refreshQr(context, p),
                  ),

                // Scan QR
                _tileButton(
                  label: 'Scan QR',
                  icon: Icons.qr_code_scanner_outlined,
                  disabled: locked || expired,
                  onTap: () async {
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
                          content: Text(
                            'This QR does not match this property ❌',
                          ),
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
                ),

                // Admin tools
                if (isAdmin)
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
                        await _adminResetOtpAndShow(context, p);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'unlock', child: Text('Unlock OTP')),
                      PopupMenuItem(
                        value: 'reset',
                        child: Text('Reset OTP (new code)'),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.admin_panel_settings_outlined,
                            size: 15,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Admin',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // Small UI helpers
  // =========================

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _warningRow(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            size: 13,
            color: Colors.orange,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tileButton({
    required String label,
    required IconData icon,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: disabled ? null : onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: disabled ? Colors.grey.shade300 : AppColors.primary,
        ),
        foregroundColor: disabled ? Colors.grey : AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<String?> _askOtp(BuildContext context) async {
    final c = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Enter OTP'),
          content: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '6-digit OTP',
              filled: true,
              fillColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
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
