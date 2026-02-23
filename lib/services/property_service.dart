import '../models/property.dart';
import '../models/property_status.dart';
import '../models/user_role.dart';
import 'hive_service.dart';
import 'notification_service.dart';
import 'role_guard.dart';
import '../data/routes_helpers.dart';
import 'trip_service.dart';
import 'whatsapp_service.dart';
import 'audit_service.dart';
import 'pickup_qr_service.dart';
import 'session.dart';
import 'receiver_tracking_service.dart';

class PropertyService {
  static String _generateOtp() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    return (100000 + (ms % 900000)).toString();
  }

  static const Duration _otpTtl = Duration(hours: 12);
  static const int _maxOtpAttempts = 3;
  static const Duration _otpLockDuration = Duration(minutes: 10);

  static String _newNonce() {
    // offline-friendly unique-ish value
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  static bool _isOtpExpired(Property p) {
    final gen = p.otpGeneratedAt;
    if (gen == null) return true;
    return DateTime.now().isAfter(gen.add(_otpTtl));
  }

  static bool _isOtpLocked(Property p) {
    final until = p.otpLockedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  static bool isOtpExpired(Property p) => _isOtpExpired(p);
  static bool isOtpLocked(Property p) => _isOtpLocked(p);

  static int remainingLockMinutes(Property p) {
    final until = p.otpLockedUntil;
    if (until == null) return 0;
    final diff = until.difference(DateTime.now());
    return diff.inMinutes < 0 ? 0 : diff.inMinutes;
  }

  // Receiver tracking (safe hook)

  static Future<void> _safeNotifyReceiver({
    required Property fresh,
    required String eventLabel,
  }) async {
    try {
      await ReceiverTrackingService.notifyReceiverOnStatusChange(
        property: fresh,
        eventLabel: eventLabel,
      );
    } catch (e) {
      // Never block business flow (even audit must not crash)
      try {
        await AuditService.log(
          action: 'receiver_notify_failed',
          propertyKey: fresh.key.toString(),
          details: 'Failed to queue receiver update ($eventLabel): $e',
        );
      } catch (_) {}
    }
  }
  // Auto-repair: fix already-broken records (status implies loaded)

  /// Repairs legacy invalid state where status is inTransit/delivered/pickedUp
  /// but loadedAt is null. Writes an audit entry.
  /// Returns true if a repair was applied.
  static Future<bool> repairMissingLoadedMilestone(Property p) async {
    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    final impliesLoaded =
        fresh.status == PropertyStatus.inTransit ||
        fresh.status == PropertyStatus.delivered ||
        fresh.status == PropertyStatus.pickedUp;

    if (!impliesLoaded) return false;
    if (fresh.loadedAt != null) return false;

    // Pick the safest timestamp we already have
    final best =
        fresh.inTransitAt ??
        fresh.deliveredAt ??
        fresh.pickedUpAt ??
        DateTime.now();

    fresh.loadedAt = best;

    // Do not guess station (no origin field). Keep empty if unknown.
    if (fresh.loadedAtStation.trim().isEmpty) {
      fresh.loadedAtStation = '';
    }
    if (fresh.loadedByUserId.trim().isEmpty) {
      fresh.loadedByUserId = 'system_repair';
    }

    await fresh.save();

    await AuditService.log(
      action: 'auto_repair_missing_loadedAt',
      propertyKey: fresh.key.toString(),
      details:
          'Repaired loadedAt because status implied loaded. loadedAt set to $best',
    );

    return true;
  }

  // Delivered + OTP + Pickup QR

  static Future markDelivered(Property p) async {
    if (!RoleGuard.hasAny({UserRole.staff, UserRole.admin})) return;

    final box = HiveService.propertyBox();
    final fresh = box.get(p.key) ?? p;

    // Optional safety: repair legacy inconsistency
    await repairMissingLoadedMilestone(fresh);

    if (fresh.status != PropertyStatus.inTransit) return;

    // Consistency: if inTransit then loaded must exist (guard anyway)
    fresh.loadedAt ??= fresh.inTransitAt ?? DateTime.now();
    if (fresh.loadedByUserId.trim().isEmpty) {
      fresh.loadedByUserId = (Session.currentUserId ?? 'system').trim();
    }

    final now = DateTime.now();

    // Step 1: mark delivered FIRST (persist)
    fresh.status = PropertyStatus.delivered;
    fresh.deliveredAt = now;
    await fresh.save();

    // Step 2: issue OTP + QR using PickupQrService (single source of truth)
    final otp = (fresh.pickupOtp ?? '').trim().isEmpty
        ? _generateOtp()
        : fresh.pickupOtp!.trim();

    await PickupQrService.issueForDelivered(fresh, otp: otp);

    // Receiver update (non-blocking) AFTER QR/OTP exists
    await _safeNotifyReceiver(fresh: fresh, eventLabel: 'DELIVERED');

    // Notifications
    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'Property delivered to station',
      message:
          'Your property arrived at the destination station.\n'
          'OTP/QR issued for pickup.',
    );

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Store update: Delivered',
      message:
          'Property for ${fresh.receiverName} delivered.\n'
          'OTP/QR issued for pickup.',
    );
  }

  static Future confirmPickupWithOtp(Property p, String otp) async {
    if (!RoleGuard.hasAny({UserRole.staff, UserRole.admin})) return false;

    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    // Optional safety: repair legacy inconsistency
    await repairMissingLoadedMilestone(fresh);

    if (fresh.status != PropertyStatus.delivered) return false;
    if (fresh.pickupOtp == null) return false;
    if (_isOtpLocked(fresh)) return false;
    if (_isOtpExpired(fresh)) return false;

    if (otp.trim() != fresh.pickupOtp) {
      fresh.otpAttempts = fresh.otpAttempts + 1;

      if (fresh.otpAttempts >= _maxOtpAttempts) {
        fresh.otpLockedUntil = DateTime.now().add(_otpLockDuration);
      }
      await fresh.save();
      return false;
    }

    // Ensure milestone chain exists (consistency)
    fresh.deliveredAt ??= DateTime.now();
    fresh.inTransitAt ??= fresh.deliveredAt;
    fresh.loadedAt ??= fresh.inTransitAt;

    fresh.status = PropertyStatus.pickedUp;
    fresh.pickedUpAt = DateTime.now();
    fresh.staffPickupConfirmed = true;

    fresh.pickupOtp = null;
    fresh.otpGeneratedAt = null;
    fresh.otpAttempts = 0;
    fresh.otpLockedUntil = null;

    // one-time QR: consumed after successful pickup
    fresh.qrConsumedAt = DateTime.now();

    await fresh.save();

    // Receiver update (non-blocking)
    await _safeNotifyReceiver(fresh: fresh, eventLabel: 'PICKED UP');

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'Property picked up',
      message: 'Your property was picked up by the receiver.',
    );
    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Pickup confirmed',
      message:
          'Receiver pickup confirmed for ${fresh.receiverName} (${fresh.receiverPhone}).',
    );

    return true;
  }

  static Future adminUnlockOtp(Property p) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;

    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    fresh.otpAttempts = 0;
    fresh.otpLockedUntil = null;
    await fresh.save();

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'OTP unlocked',
      message:
          'Admin unlocked OTP for ${fresh.receiverName} (${fresh.receiverPhone}).',
    );
  }

  static Future adminResetOtp(Property p) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;

    final fresh = HiveService.propertyBox().get(p.key) ?? p;
    if (fresh.status != PropertyStatus.delivered) return;

    fresh.pickupOtp = _generateOtp();
    fresh.otpGeneratedAt = DateTime.now();
    fresh.otpAttempts = 0;
    fresh.otpLockedUntil = null;

    // reset QR session on OTP reset
    fresh.qrIssuedAt = DateTime.now();
    fresh.qrNonce = _newNonce();
    fresh.qrConsumedAt = null;

    await fresh.save();

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'OTP reset',
      message:
          'The pickup OTP was reset at the station.\n'
          'If you need it, contact the station staff.',
    );

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'OTP reset',
      message:
          'Admin reset OTP for ${fresh.receiverName} (${fresh.receiverPhone}).',
    );
  }

  /// STRICT FLOW:
  /// pending → (desk marks Loaded → loadedAt) → driver starts trip → inTransit
  ///
  /// Returns null on success, or a human-friendly error string (for UI).
  static Future<String?> markInTransit(Property p) async {
    if (!RoleGuard.hasAny({UserRole.driver, UserRole.admin})) {
      return 'Not authorized.';
    }

    final fresh = HiveService.propertyBox().get(p.key) ?? p;
    if (fresh.status != PropertyStatus.pending) {
      return 'Only Pending cargo can be loaded.';
    }

    // STRICT FLOW: cannot go inTransit unless Desk marked LOADED (timestamp-based)
    if (fresh.loadedAt == null) {
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'Load blocked (missing LOADED milestone)',
        message:
            'Driver tried to start trip but LOADED milestone is missing.\n'
            'Property: ${fresh.receiverName} (${fresh.receiverPhone}).\n'
            'Desk must mark LOADED first.',
      );

      await AuditService.log(
        action: 'driver_load_blocked_missing_loadedAt',
        propertyKey: fresh.key.toString(),
        details: 'Blocked pending→inTransit because loadedAt == null',
      );

      return 'Not loaded yet ❌ Desk must mark LOADED first.';
    }

    final route = findRouteById(fresh.routeId);
    if (route == null) {
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'Route missing',
        message:
            'Cannot start trip: property for ${fresh.receiverName} has no valid routeId.',
      );
      return 'Route missing ❌ Ask admin/staff.';
    }

    final cps = validatedCheckpoints(route);
    if (cps.isEmpty) {
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'Route invalid',
        message:
            'Route "${route.name}" has invalid checkpoints.\n'
            'Fix coordinates before tracking.',
      );
      return 'Route "${route.name}" invalid ❌ Ask admin to fix checkpoints.';
    }

    final active = TripService.getActiveTripForCurrentDriver();
    if (active != null && active.routeId != route.id) {
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'Route mismatch blocked',
        message:
            'Driver has an active trip (${active.routeName}) but tried to load cargo for route (${route.name}).\n'
            'Blocked to avoid mixing routes.',
      );
      return 'Route mismatch ❌ Finish current trip first.';
    }

    fresh.routeId = route.id;
    fresh.routeName = route.name;
    fresh.status = PropertyStatus.inTransit;
    fresh.inTransitAt = DateTime.now();

    final trip = await TripService.ensureActiveTrip(
      routeId: route.id,
      routeName: route.name,
      checkpoints: cps,
    );

    fresh.tripId = trip.tripId;

    await fresh.save();

    // Receiver update (non-blocking)
    await _safeNotifyReceiver(fresh: fresh, eventLabel: 'IN TRANSIT');

    await AuditService.log(
      action: 'driver_mark_in_transit',
      propertyKey: fresh.key.toString(),
      details:
          'Started trip: ${route.name} | tripId=${fresh.tripId} | loadedAt=${fresh.loadedAt}',
    );

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'Property in transit',
      message: 'Your property is now in transit.\nRoute: ${route.name}',
    );

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Driver update: In transit',
      message:
          'Property for ${fresh.receiverName} is in transit.\nRoute: ${route.name}',
    );

    return null; // success
  }

  // Admin override (CONSISTENT)

  static Future adminSetStatus(Property p, PropertyStatus newStatus) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;

    final fresh = HiveService.propertyBox().get(p.key) ?? p;
    if (fresh.status == newStatus) return;

    // Safety: repair legacy inconsistency before admin action
    await repairMissingLoadedMilestone(fresh);

    // Preserve “normal path” flows when possible
    if (newStatus == PropertyStatus.inTransit &&
        fresh.status == PropertyStatus.pending) {
      await markInTransit(fresh); // enforces loadedAt
      return;
    }

    if (newStatus == PropertyStatus.delivered &&
        fresh.status == PropertyStatus.inTransit) {
      await markDelivered(fresh);
      return;
    }

    if (newStatus == PropertyStatus.pending) {
      fresh.status = PropertyStatus.pending;
      fresh.inTransitAt = null;
      fresh.deliveredAt = null;
      fresh.pickedUpAt = null;

      fresh.pickupOtp = null;
      fresh.otpGeneratedAt = null;
      fresh.otpAttempts = 0;
      fresh.otpLockedUntil = null;

      fresh.staffPickupConfirmed = false;
      fresh.receiverPickupConfirmed = false;

      fresh.tripId = null;

      // reset QR state
      fresh.qrIssuedAt = null;
      fresh.qrNonce = '';
      fresh.qrConsumedAt = null;

      // reset loaded milestone
      fresh.loadedAt = null;
      fresh.loadedAtStation = '';
      fresh.loadedByUserId = '';

      await fresh.save();

      // Receiver update on admin reset
      await _safeNotifyReceiver(fresh: fresh, eventLabel: 'PENDING');

      await AuditService.log(
        action: 'admin_set_status',
        propertyKey: fresh.key.toString(),
        details: 'Admin set status to pending (full reset)',
      );
      return;
    }

    // If admin pushes to inTransit, try to ensure trip context exists
    if (newStatus == PropertyStatus.inTransit) {
      final route = findRouteById(fresh.routeId);
      if (route != null) {
        final cps = validatedCheckpoints(route);
        if (cps.isNotEmpty) {
          final trip = await TripService.ensureActiveTrip(
            routeId: route.id,
            routeName: route.name,
            checkpoints: cps,
          );
          fresh.tripId = trip.tripId;
          fresh.routeId = route.id;
          fresh.routeName = route.name;
        }
      }
    }

    // timestamps + milestone consistency
    if (newStatus == PropertyStatus.inTransit) {
      fresh.inTransitAt ??= DateTime.now();

      // inTransit implies LOADED exists
      fresh.loadedAt ??= fresh.inTransitAt;

      if (fresh.loadedByUserId.trim().isEmpty) {
        fresh.loadedByUserId = (Session.currentUserId ?? 'admin').trim();
      }

      await AuditService.log(
        action: 'admin_ensure_loaded_for_inTransit',
        propertyKey: fresh.key.toString(),
        details:
            'Ensured loadedAt for inTransit. loadedAt=${fresh.loadedAt} inTransitAt=${fresh.inTransitAt}',
      );
    }

    if (newStatus == PropertyStatus.delivered) {
      fresh.deliveredAt ??= DateTime.now();

      // Delivered implies it must have been inTransit; ensure inTransitAt exists
      fresh.inTransitAt ??= fresh.deliveredAt;

      // Delivered implies LOADED exists as well
      fresh.loadedAt ??= fresh.inTransitAt;

      fresh.pickupOtp ??= _generateOtp();
      fresh.otpGeneratedAt ??= DateTime.now();
      fresh.otpAttempts = 0;
      fresh.otpLockedUntil = null;

      // ensure QR session exists for delivered
      fresh.qrIssuedAt ??= DateTime.now();
      if (fresh.qrNonce.trim().isEmpty) fresh.qrNonce = _newNonce();
      fresh.qrConsumedAt = null;

      await AuditService.log(
        action: 'admin_prepare_delivered',
        propertyKey: fresh.key.toString(),
        details:
            'Prepared delivered: deliveredAt=${fresh.deliveredAt}, inTransitAt=${fresh.inTransitAt}, loadedAt=${fresh.loadedAt}',
      );
    }

    if (newStatus == PropertyStatus.pickedUp) {
      fresh.pickedUpAt ??= DateTime.now();

      // PickedUp implies delivered/inTransit/loaded exist
      fresh.deliveredAt ??= fresh.pickedUpAt;
      fresh.inTransitAt ??= fresh.deliveredAt;
      fresh.loadedAt ??= fresh.inTransitAt;

      fresh.staffPickupConfirmed = true;
      fresh.receiverPickupConfirmed = true;

      fresh.pickupOtp = null;
      fresh.otpGeneratedAt = null;
      fresh.otpAttempts = 0;
      fresh.otpLockedUntil = null;

      // consume QR
      fresh.qrConsumedAt ??= DateTime.now();

      await AuditService.log(
        action: 'admin_prepare_pickedUp',
        propertyKey: fresh.key.toString(),
        details:
            'Prepared pickedUp: pickedUpAt=${fresh.pickedUpAt}, deliveredAt=${fresh.deliveredAt}, inTransitAt=${fresh.inTransitAt}, loadedAt=${fresh.loadedAt}',
      );
    }

    fresh.status = newStatus;
    await fresh.save();

    // Receiver update on admin override too (only if opted-in)
    final label = (newStatus == PropertyStatus.inTransit)
        ? 'IN TRANSIT'
        : (newStatus == PropertyStatus.delivered)
        ? 'DELIVERED'
        : (newStatus == PropertyStatus.pickedUp)
        ? 'PICKED UP'
        : 'PENDING';
    await _safeNotifyReceiver(fresh: fresh, eventLabel: label);

    await AuditService.log(
      action: 'admin_set_status',
      propertyKey: fresh.key.toString(),
      details: 'Admin set status to ${newStatus.name}',
    );

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'Admin status update',
      message:
          'Admin updated your property for ${fresh.receiverName} to ${newStatus.name}.',
    );

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Admin override applied',
      message:
          'Status set to ${newStatus.name} for ${fresh.receiverName} (${fresh.receiverPhone}).',
    );
  }

  // WhatsApp OTP (Improved)

  static String _propertyCodeLabel(Property p) {
    final c = p.propertyCode.trim();
    return c.isEmpty ? p.key.toString() : c;
  }

  static String _otpMessage(Property p) {
    final otp = (p.pickupOtp ?? '').trim();
    final station = p.destination.trim(); // your existing station mapping
    final code = _propertyCodeLabel(p);

    final until = p.otpGeneratedAt?.add(_otpTtl);
    final untilText = until == null
        ? ''
        : 'Valid until: ${until.toLocal().toString().substring(0, 16)}';
    return [
      'BEBETO CARGO — Pickup OTP',
      'Property: $code',
      'Receiver: ${p.receiverName.trim().isEmpty ? '—' : p.receiverName.trim()}',
      if (station.isNotEmpty) 'Station: $station',
      'OTP: ${otp.isEmpty ? '—' : otp}',
      'Instruction: Show this OTP at the pickup desk to receive your cargo.',
      if (untilText.isNotEmpty) untilText,
    ].join('\n');
  }

  /// Returns null on success, or a human-friendly error string.
  static Future<String?> sendPickupOtpViaWhatsApp(Property p) async {
    if (!RoleGuard.hasAny({UserRole.staff, UserRole.admin})) {
      return 'Not authorized.';
    }

    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    // Optional safety: repair legacy inconsistency
    await repairMissingLoadedMilestone(fresh);

    if (fresh.status != PropertyStatus.delivered) {
      return 'Property is not in Delivered state.';
    }

    final otp = (fresh.pickupOtp ?? '').trim();
    if (otp.isEmpty) {
      return 'OTP missing. Ask admin to reset OTP.';
    }

    if (_isOtpLocked(fresh)) {
      final mins = remainingLockMinutes(fresh);
      return 'OTP locked. Try again in $mins min.';
    }

    if (_isOtpExpired(fresh)) {
      return 'OTP expired. Ask admin to reset OTP.';
    }

    final phoneRaw = fresh.receiverPhone.trim();
    if (phoneRaw.isEmpty || phoneRaw.length < 9) {
      return 'Receiver phone missing/invalid.';
    }

    final phoneE164 = WhatsAppService.ugToE164(phoneRaw);

    final err = await WhatsAppService.openChat(
      phoneE164: phoneE164,
      message: _otpMessage(fresh),
    );

    await AuditService.log(
      action: err == null
          ? 'staff_whatsapp_otp_opened'
          : 'staff_whatsapp_otp_failed',
      propertyKey: fresh.key.toString(),
      details: err == null
          ? 'WhatsApp OTP to ${fresh.receiverPhone}'
          : 'WhatsApp failed: $err | to ${fresh.receiverPhone}',
    );

    return err;
  }

  /// Call this from UI to force-refresh QR (optional).
  static Future refreshPickupQr(Property p) async {
    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    // Optional safety: repair legacy inconsistency
    await repairMissingLoadedMilestone(fresh);

    if (fresh.status != PropertyStatus.delivered) return;
    if (fresh.pickupOtp == null || fresh.otpGeneratedAt == null) return;
    if (_isOtpLocked(fresh) || _isOtpExpired(fresh)) return;
    if (fresh.qrConsumedAt != null) return;

    fresh.qrIssuedAt = DateTime.now();
    fresh.qrNonce = _newNonce();
    await fresh.save();
  }

  // Desk "Loaded" milestone

  static Future markLoaded(Property p, {required String station}) async {
    if (!RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin})) {
      return false;
    }

    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    // only allow when still pending
    if (fresh.status != PropertyStatus.pending) return false;

    // idempotent
    if (fresh.loadedAt != null) return true;

    fresh.loadedAt = DateTime.now();
    fresh.loadedAtStation = station.trim();
    fresh.loadedByUserId = (Session.currentUserId ?? '').trim();

    await fresh.save();

    await AuditService.log(
      action: 'desk_mark_loaded',
      propertyKey: fresh.key.toString(),
      details: 'Marked loaded at station: ${fresh.loadedAtStation}',
    );

    await _safeNotifyReceiver(fresh: fresh, eventLabel: 'LOADED');

    return true;
  }
}
