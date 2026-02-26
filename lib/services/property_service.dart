import '../models/property.dart';
import '../models/property_status.dart';
import '../models/trip.dart';
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
import '../models/property_item_status.dart';
import 'property_item_service.dart';

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

  // ✅ Partial-load receiver message after trip starts
  static Future<void> _safeNotifyReceiverPartialLoad({
    required Property fresh,
    required PropertyItemTripCounts counts,
    required String routeName,
  }) async {
    try {
      await ReceiverTrackingService.notifyReceiverPartialLoadOnTripStart(
        property: fresh,
        loadedForTrip: counts.loadedForTrip,
        total: counts.total,
        remainingAtStation: counts.remainingAtStation,
        routeName: routeName,
      );
    } catch (e) {
      try {
        await AuditService.log(
          action: 'receiver_partial_notify_failed',
          propertyKey: fresh.key.toString(),
          details: 'Failed to queue receiver partial-load update: $e',
        );
      } catch (_) {}
    }
  }

  // Auto-repair: fix already-broken records (status implies loaded)
  static Future<bool> repairMissingLoadedMilestone(Property p) async {
    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    final impliesLoaded =
        fresh.status == PropertyStatus.inTransit ||
        fresh.status == PropertyStatus.delivered ||
        fresh.status == PropertyStatus.pickedUp;

    if (!impliesLoaded) return false;
    if (fresh.loadedAt != null) return false;

    final best =
        fresh.inTransitAt ??
        fresh.deliveredAt ??
        fresh.pickedUpAt ??
        DateTime.now();

    fresh.loadedAt = best;

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

    await repairMissingLoadedMilestone(fresh);

    if (fresh.status != PropertyStatus.inTransit) return;

    fresh.loadedAt ??= fresh.inTransitAt ?? DateTime.now();
    if (fresh.loadedByUserId.trim().isEmpty) {
      fresh.loadedByUserId = (Session.currentUserId ?? 'system').trim();
    }

    final now = DateTime.now();

    fresh.status = PropertyStatus.delivered;
    fresh.deliveredAt = now;
    await fresh.save();

    final otp = (fresh.pickupOtp ?? '').trim().isEmpty
        ? _generateOtp()
        : fresh.pickupOtp!.trim();

    await PickupQrService.issueForDelivered(fresh, otp: otp);

    await _safeNotifyReceiver(fresh: fresh, eventLabel: 'DELIVERED');

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

    fresh.qrConsumedAt = DateTime.now();

    await fresh.save();

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
  static Future markInTransit(Property p) async {
    if (!RoleGuard.hasAny({UserRole.driver, UserRole.admin})) return;

    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(p.key) ?? p;

    if (fresh.status != PropertyStatus.pending) return;

    final route = findRouteById(fresh.routeId);
    if (route == null) {
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'Route missing',
        message:
            'Cannot start trip: property for ${fresh.receiverName} has no valid routeId.',
      );
      return;
    }
    final cps = validatedCheckpoints(route);
    if (cps.isEmpty) {
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'Route invalid',
        message:
            'Route "${route.name}" has invalid checkpoints.\nFix coordinates before tracking.',
      );
      return;
    }

    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    await itemSvc.ensureItemsForProperty(
      propertyKey: fresh.key.toString(),
      trackingCode: fresh.trackingCode,
      itemCount: fresh.itemCount,
    );

    final items = itemSvc.getItemsForProperty(fresh.key.toString());
    final hasLoaded = items.any(
      (x) => x.status == PropertyItemStatus.loaded && x.tripId.trim().isEmpty,
    );
    if (!hasLoaded) {
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'No loaded items',
        message:
            'Driver tried to start trip but no items are marked LOADED for ${fresh.receiverName}.',
      );
      return;
    }

    final active = TripService.getActiveTripForCurrentDriver();
    if (active != null && active.routeId != route.id) {
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'Route mismatch blocked',
        message:
            'Driver has an active trip (${active.routeName}) but tried to load cargo for route (${route.name}).\nBlocked to avoid mixing routes.',
      );
      return;
    }

    // Trip creation first. We only mutate/persist property route+trip fields AFTER this succeeds.
    final now = DateTime.now();

    Trip trip;
    try {
      trip = await TripService.ensureActiveTrip(
        routeId: route.id,
        routeName: route.name,
        checkpoints: cps,
      );
    } catch (e, st) {
      // ✅ improvement: capture stacktrace too
      await AuditService.log(
        action: 'trip_ensure_failed',
        propertyKey: fresh.key.toString(),
        details: 'ensureActiveTrip failed: $e\n$st',
      );
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'Trip start failed',
        message: 'Failed to start trip for route "${route.name}". Error: $e',
      );
      return;
    }

    await itemSvc.onTripStartedMoveLoadedToInTransitForProperty(
      propertyKey: fresh.key.toString(),
      tripId: trip.tripId,
      now: now,
    );

    //  Now persist property as inTransit, with trip + route context.
    fresh.routeId = route.id;
    fresh.routeName = route.name;
    fresh.status = PropertyStatus.inTransit;
    fresh.inTransitAt = now;
    fresh.tripId = trip.tripId;
    await fresh.save();

    final counts = itemSvc.computeTripCounts(
      propertyKey: fresh.key.toString(),
      tripId: trip.tripId,
    );

    final msg =
        'Loaded today: ${counts.loadedForTrip}/${counts.total}\n'
        'Remaining at station: ${counts.remainingAtStation}/${counts.total}\n'
        'Route: ${route.name}';

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'Property in transit',
      message: 'Your property is now in transit.\n$msg',
    );
    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Driver update: In transit',
      message: 'Property for ${fresh.receiverName} is in transit.\n$msg',
    );

    //  Receiver partial-load message (after trip start)
    await _safeNotifyReceiverPartialLoad(
      fresh: fresh,
      counts: counts,
      routeName: route.name,
    );

    //  Optional (as requested): normal status notify too (rate-limited in ReceiverTrackingService)
    await _safeNotifyReceiver(fresh: fresh, eventLabel: 'IN TRANSIT');
  }

  static Future adminSetStatus(Property p, PropertyStatus newStatus) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;

    final fresh = HiveService.propertyBox().get(p.key) ?? p;
    if (fresh.status == newStatus) return;

    await repairMissingLoadedMilestone(fresh);

    if (newStatus == PropertyStatus.inTransit &&
        fresh.status == PropertyStatus.pending) {
      await markInTransit(fresh);
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

      fresh.qrIssuedAt = null;
      fresh.qrNonce = '';
      fresh.qrConsumedAt = null;

      fresh.loadedAt = null;
      fresh.loadedAtStation = '';
      fresh.loadedByUserId = '';

      await fresh.save();

      await _safeNotifyReceiver(fresh: fresh, eventLabel: 'PENDING');

      await AuditService.log(
        action: 'admin_set_status',
        propertyKey: fresh.key.toString(),
        details: 'Admin set status to pending (full reset)',
      );
      return;
    }

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

    if (newStatus == PropertyStatus.inTransit) {
      fresh.inTransitAt ??= DateTime.now();
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
      fresh.inTransitAt ??= fresh.deliveredAt;
      fresh.loadedAt ??= fresh.inTransitAt;

      fresh.pickupOtp ??= _generateOtp();
      fresh.otpGeneratedAt ??= DateTime.now();
      fresh.otpAttempts = 0;
      fresh.otpLockedUntil = null;

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
      fresh.deliveredAt ??= fresh.pickedUpAt;
      fresh.inTransitAt ??= fresh.deliveredAt;
      fresh.loadedAt ??= fresh.inTransitAt;

      fresh.staffPickupConfirmed = true;
      fresh.receiverPickupConfirmed = true;

      fresh.pickupOtp = null;
      fresh.otpGeneratedAt = null;
      fresh.otpAttempts = 0;
      fresh.otpLockedUntil = null;

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

  static String _propertyCodeLabel(Property p) {
    final c = p.propertyCode.trim();
    return c.isEmpty ? p.key.toString() : c;
  }

  static String _otpMessage(Property p) {
    final otp = (p.pickupOtp ?? '').trim();
    final station = p.destination.trim();
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

  static Future<String?> sendPickupOtpViaWhatsApp(Property p) async {
    if (!RoleGuard.hasAny({UserRole.staff, UserRole.admin})) {
      return 'Not authorized.';
    }

    final fresh = HiveService.propertyBox().get(p.key) ?? p;
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

  static Future refreshPickupQr(Property p) async {
    final fresh = HiveService.propertyBox().get(p.key) ?? p;
    await repairMissingLoadedMilestone(fresh);

    if (fresh.status != PropertyStatus.delivered) return;
    if (fresh.pickupOtp == null || fresh.otpGeneratedAt == null) return;
    if (_isOtpLocked(fresh) || _isOtpExpired(fresh)) return;
    if (fresh.qrConsumedAt != null) return;

    fresh.qrIssuedAt = DateTime.now();
    fresh.qrNonce = _newNonce();
    await fresh.save();
  }

  static Future<bool> markLoaded(
    Property p, {
    required String station,
    List<int>? itemNos,
  }) async {
    if (!RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin})) {
      return false;
    }

    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(p.key) ?? p;

    if (fresh.status != PropertyStatus.pending) return false;

    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    await itemSvc.ensureItemsForProperty(
      propertyKey: fresh.key.toString(),
      trackingCode: fresh.trackingCode,
      itemCount: fresh.itemCount,
    );

    final selectedNos = (itemNos == null || itemNos.isEmpty)
        ? List<int>.generate(fresh.itemCount, (i) => i + 1)
        : itemNos;

    final now = DateTime.now();

    await itemSvc.markSelectedItemsLoaded(
      propertyKey: fresh.key.toString(),
      itemNos: selectedNos,
      tripId: '',
      now: now,
    );

    fresh.loadedAt ??= now;
    fresh.loadedAtStation = station.trim();
    fresh.loadedByUserId = (Session.currentUserId ?? '').trim();
    await fresh.save();

    await AuditService.log(
      action: 'desk_mark_loaded_items',
      propertyKey: fresh.key.toString(),
      details:
          'Loaded items: ${selectedNos.join(",")} at station: ${fresh.loadedAtStation}',
    );

    return true;
  }
}
