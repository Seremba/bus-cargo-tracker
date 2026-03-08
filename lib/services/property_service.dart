import '../data/routes_helpers.dart';
import '../models/property.dart';
import '../models/property_item_status.dart';
import '../models/property_status.dart';
import '../models/sync_event.dart';
import '../models/trip.dart';
import '../models/user_role.dart';

import 'audit_service.dart';
import 'hive_service.dart';
import 'notification_service.dart';
import 'outbound_message_service.dart';
import 'pickup_qr_service.dart';
import 'property_item_service.dart';
import 'receiver_tracking_service.dart';
import 'role_guard.dart';
import 'session.dart';
import 'sync_service.dart';
import 'trip_service.dart';
import 'whatsapp_service.dart';
import 'phone_normalizer.dart';

class PropertyService {
  static String _generatePropertyCode() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');

    final ms = now.millisecondsSinceEpoch;
    final suffix = (ms % 1679616)
        .toRadixString(36)
        .toUpperCase()
        .padLeft(4, '0');

    return 'P-$y$m$d-$suffix';
  }

  static Future<Property> registerProperty({
    required String receiverName,
    required String receiverPhone,
    required String description,
    required String destination,
    required int itemCount,
    required String createdByUserId,
    required String routeId,
    required String routeName,
  }) async {
    final box = HiveService.propertyBox();

    final cleanReceiverName = receiverName.trim();
    final cleanReceiverPhone = receiverPhone.trim();
    final cleanDescription = description.trim();
    final cleanDestination = destination.trim();
    final cleanCreatedByUserId = createdByUserId.trim();
    final cleanRouteId = routeId.trim();
    final cleanRouteName = routeName.trim();

    if (cleanCreatedByUserId.isEmpty) {
      throw ArgumentError('Created-by user is required');
    }
    if (cleanReceiverName.isEmpty) {
      throw ArgumentError('Receiver name is required');
    }
    if (cleanReceiverPhone.isEmpty) {
      throw ArgumentError('Receiver phone is required');
    }
    if (cleanDescription.isEmpty) {
      throw ArgumentError('Description is required');
    }
    if (cleanDestination.isEmpty) {
      throw ArgumentError('Destination is required');
    }
    if (cleanRouteId.isEmpty || cleanRouteName.isEmpty) {
      throw ArgumentError('Route is required');
    }
    if (itemCount < 1) {
      throw ArgumentError('Item count must be at least 1');
    }

    final now = DateTime.now();
    final propertyCode = _generatePropertyCode();

    final property = Property(
      receiverName: cleanReceiverName,
      receiverPhone: cleanReceiverPhone,
      description: cleanDescription,
      destination: cleanDestination,
      itemCount: itemCount,
      routeId: cleanRouteId,
      routeName: cleanRouteName,
      createdAt: now,
      status: PropertyStatus.pending,
      createdByUserId: cleanCreatedByUserId,
      propertyCode: propertyCode,
      amountPaidTotal: 0,
      currency: 'UGX',
      lastPaidAt: null,
      lastPaymentMethod: '',
      lastPaidByUserId: '',
      lastPaidAtStation: '',
      lastTxnRef: '',
      aggregateVersion: 1,
    );

    final key = await box.add(property);
    final saved = box.get(key) ?? property;

    await AuditService.log(
      action: 'PROPERTY_REGISTERED',
      propertyKey: key.toString(),
      details:
          'Receiver=${saved.receiverName}, Phone=${saved.receiverPhone}, '
          'Destination=${saved.destination}, Route=${saved.routeName}, '
          'Items=${saved.itemCount}, Code=${saved.propertyCode}',
    );

    await SyncService.enqueuePropertyCreated(
      propertyId: saved.propertyCode.trim(),
      actorUserId: cleanCreatedByUserId,
      aggregateVersion: saved.aggregateVersion,
      payload: {
        'propertyCode': saved.propertyCode,
        'receiverName': saved.receiverName,
        'receiverPhone': saved.receiverPhone,
        'description': saved.description,
        'destination': saved.destination,
        'itemCount': saved.itemCount,
        'routeId': saved.routeId,
        'routeName': saved.routeName,
        'status': saved.status.name,
        'createdAt': saved.createdAt.toIso8601String(),
        'createdByUserId': saved.createdByUserId,
        'amountPaidTotal': saved.amountPaidTotal,
        'currency': saved.currency,
        'aggregateVersion': saved.aggregateVersion,
      },
    );

    return saved;
  }

  static Future<void> applyPropertyCreatedFromSync(SyncEvent event) async {
    final box = HiveService.propertyBox();
    final payload = event.payload;

    final propertyCode = (payload['propertyCode'] ?? '').toString().trim();
    if (propertyCode.isEmpty) {
      throw StateError('propertyCreated sync event missing propertyCode');
    }

    final incomingVersion =
        (payload['aggregateVersion'] as num?)?.toInt() ??
        event.aggregateVersion;

    Property? existing;
    for (final p in box.values) {
      if (p.propertyCode.trim() == propertyCode) {
        existing = p;
        break;
      }
    }

    // Creation replay rule:
    // if it already exists locally, do not recreate or mutate it.
    if (existing != null) {
      return;
    }

    final property = Property(
      receiverName: (payload['receiverName'] ?? '').toString(),
      receiverPhone: (payload['receiverPhone'] ?? '').toString(),
      description: (payload['description'] ?? '').toString(),
      destination: (payload['destination'] ?? '').toString(),
      itemCount: (payload['itemCount'] as num).toInt(),
      routeId: (payload['routeId'] ?? '').toString(),
      routeName: (payload['routeName'] ?? '').toString(),
      createdAt: DateTime.parse((payload['createdAt'] ?? '').toString()),
      status: PropertyStatus.values.byName(
        (payload['status'] ?? 'pending').toString(),
      ),
      createdByUserId: (payload['createdByUserId'] ?? '').toString(),
      propertyCode: propertyCode,
      amountPaidTotal: (payload['amountPaidTotal'] as num?)?.toInt() ?? 0,
      currency: (payload['currency'] ?? 'UGX').toString(),
      aggregateVersion: incomingVersion,
    );

    await box.add(property);
  }

  static String _generateOtp() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    return (100000 + (ms % 900000)).toString();
  }

  static const Duration _otpTtl = Duration(hours: 12);
  static const int _maxOtpAttempts = 3;
  static const Duration _otpLockDuration = Duration(minutes: 10);

  static String _newNonce() {
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
      try {
        await AuditService.log(
          action: 'receiver_notify_failed',
          propertyKey: fresh.key.toString(),
          details: 'Failed to queue receiver update ($eventLabel): $e',
        );
      } catch (_) {}
    }
  }

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

  static bool _alreadyQueuedOtpSms({
    required String propertyKey,
    required String otp,
  }) {
    final needle = otp.trim();
    if (needle.isEmpty) return false;

    final box = HiveService.outboundMessageBox();

    for (final m in box.values) {
      if (m.propertyKey != propertyKey) continue;

      final ch = m.channel.trim().toLowerCase();
      if (ch != 'sms') continue;

      final st = m.status.trim().toLowerCase();
      final active =
          st == OutboundMessageService.statusQueued ||
          st == OutboundMessageService.statusOpened ||
          st == OutboundMessageService.statusSent;

      if (!active) continue;

      if (m.body.contains(needle)) return true;
    }

    return false;
  }

  static Future _safeSendOtpIfSms({
    required Property fresh,
    required String otp,
  }) async {
    try {
      if (!fresh.notifyReceiver) return;

      final ch = fresh.receiverNotifyChannel.trim().toLowerCase();
      if (ch != 'sms') return;

      final rawPhone = fresh.receiverPhone.trim();
      if (rawPhone.isEmpty) return;

      final phone = PhoneNormalizer.normalizeForMessaging(rawPhone);

      if (phone.isEmpty) {
        final pKey = fresh.key.toString();

        try {
          await AuditService.log(
            action: 'OTP_SMS_INVALID_PHONE',
            propertyKey: pKey,
            details:
                'Receiver phone not message-ready. raw="$rawPhone".\n'
                'SMS OTP not queued.',
          );
        } catch (_) {}

        try {
          await NotificationService.notify(
            targetUserId: NotificationService.adminInbox,
            title: 'OTP not sent (invalid phone)',
            message:
                'Property for ${fresh.receiverName}: receiver phone is not message-ready.\n'
                'Phone entered: "$rawPhone"\n'
                'Fix the receiver phone number to enable SMS OTP.',
          );
        } catch (_) {}

        try {
          if (fresh.createdByUserId.trim().isNotEmpty) {
            await NotificationService.notify(
              targetUserId: fresh.createdByUserId,
              title: 'OTP not sent (check receiver phone)',
              message:
                  'Receiver phone for ${fresh.receiverName} is not message-ready.\n'
                  'Phone entered: "$rawPhone"\n'
                  'Please correct it to enable SMS OTP.',
            );
          }
        } catch (_) {}

        return;
      }

      final pKey = fresh.key.toString();

      // DEDUPE: don't queue if same OTP SMS already exists for this property
      if (_alreadyQueuedOtpSms(propertyKey: pKey, otp: otp)) {
        await AuditService.log(
          action: 'OTP_SMS_SKIPPED_DUPLICATE',
          propertyKey: pKey,
          details: 'Skipped duplicate OTP SMS queue (otp=$otp)',
        );
        return;
      }

      final code = fresh.trackingCode.trim().isEmpty
          ? '—'
          : fresh.trackingCode.trim();

      final body =
          'Bebeto Cargo OTP: $otp\n'
          'Do not share this code.\n'
          'Track: $code';

      await OutboundMessageService.queue(
        toPhone: phone,
        channel: 'sms',
        body: body,
        propertyKey: pKey,
      );

      await AuditService.log(
        action: 'OTP_SMS_QUEUED',
        propertyKey: pKey,
        details: 'Queued OTP SMS to receiver phone="$phone" (raw="$rawPhone")',
      );
    } catch (e) {
      try {
        await AuditService.log(
          action: 'OTP_SMS_QUEUE_FAILED',
          propertyKey: fresh.key.toString(),
          details: 'Failed to queue OTP SMS: $e',
        );
      } catch (_) {}
    }
  }

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
          'Repaired loadedAt because status implied loaded.\nloadedAt set to $best',
    );

    return true;
  }

  static Future<void> markDelivered(Property p) async {
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

    final otp = (fresh.pickupOtp ?? '').trim().isEmpty
        ? _generateOtp()
        : fresh.pickupOtp!.trim();

    fresh.pickupOtp = otp;
    fresh.otpGeneratedAt ??= now;
    fresh.otpAttempts = 0;
    fresh.otpLockedUntil = null;

    await fresh.save();

    await PickupQrService.issueForDelivered(fresh, otp: otp);

    await _safeSendOtpIfSms(fresh: fresh, otp: otp);

    await _safeNotifyReceiver(fresh: fresh, eventLabel: 'DELIVERED');

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'Property delivered to station',
      message:
          'Your property arrived at the destination station.\nOTP/QR issued for pickup.',
    );

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Store update: Delivered',
      message:
          'Property for ${fresh.receiverName} delivered.\nOTP/QR issued for pickup.',
    );
  }

  static Future<bool> confirmPickupWithOtp(Property p, String otp) async {
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

  static Future<void> adminUnlockOtp(Property p) async {
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

  static Future<void> adminResetOtp(Property p) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;

    final fresh = HiveService.propertyBox().get(p.key) ?? p;
    if (fresh.status != PropertyStatus.delivered) return;

    final otp = _generateOtp();

    fresh.pickupOtp = otp;
    fresh.otpGeneratedAt = DateTime.now();
    fresh.otpAttempts = 0;
    fresh.otpLockedUntil = null;

    fresh.qrIssuedAt = DateTime.now();
    fresh.qrNonce = _newNonce();
    fresh.qrConsumedAt = null;

    await fresh.save();

    await _safeSendOtpIfSms(fresh: fresh, otp: otp);

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'OTP reset',
      message:
          'The pickup OTP was reset at the station.\nIf you need it, contact the station staff.',
    );

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'OTP reset',
      message:
          'Admin reset OTP for ${fresh.receiverName} (${fresh.receiverPhone}).',
    );
  }

  static Future<void> markInTransit(Property p) async {
    if (!RoleGuard.hasAny({UserRole.driver, UserRole.admin})) return;

    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(p.key) ?? p;

    if (fresh.status != PropertyStatus.pending) {
      return;
    }

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

    final now = DateTime.now();
    Trip trip;

    try {
      trip = await TripService.ensureActiveTrip(
        routeId: route.id,
        routeName: route.name,
        checkpoints: cps,
      );
    } catch (e, st) {
      await AuditService.log(
        action: 'trip_ensure_failed',
        propertyKey: fresh.key.toString(),
        details: 'ensureActiveTrip failed: $e\n$st',
      );
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'Trip start failed',
        message: 'Failed to start trip for route "${route.name}".\nError: $e',
      );
      return;
    }

    await itemSvc.onTripStartedMoveLoadedToInTransitForProperty(
      propertyKey: fresh.key.toString(),
      tripId: trip.tripId,
      now: now,
    );

    // Refresh counts after move
    final counts = itemSvc.computeTripCounts(
      propertyKey: fresh.key.toString(),
      tripId: trip.tripId,
    );

    // Update property
    fresh.routeId = route.id;
    fresh.routeName = route.name;
    fresh.status = PropertyStatus
        .inTransit; // aggregate: if ANY item inTransit -> inTransit
    fresh.inTransitAt = now;
    fresh.tripId = trip.tripId;
    await fresh.save();

    final msg =
        'Departed today: ${counts.loadedForTrip}/${counts.total}\n'
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

    // ✅ Receiver notification: choose ONE path (partial OR normal)
    if (counts.remainingAtStation > 0) {
      await _safeNotifyReceiverPartialLoad(
        fresh: fresh,
        counts: counts,
        routeName: route.name,
      );
    } else {
      await _safeNotifyReceiver(fresh: fresh, eventLabel: 'IN TRANSIT');
    }
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

  static Future<void> adminSetStatus(
    Property p,
    PropertyStatus newStatus,
  ) async {
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

      fresh.inTransitAt ??= DateTime.now();
      fresh.loadedAt ??= fresh.inTransitAt;

      if (fresh.loadedByUserId.trim().isEmpty) {
        fresh.loadedByUserId = (Session.currentUserId ?? 'admin').trim();
      }

      await AuditService.log(
        action: 'admin_prepare_inTransit',
        propertyKey: fresh.key.toString(),
        details:
            'Prepared inTransit: loadedAt=${fresh.loadedAt} inTransitAt=${fresh.inTransitAt}',
      );
    }

    if (newStatus == PropertyStatus.delivered) {
      fresh.deliveredAt ??= DateTime.now();
      fresh.inTransitAt ??= fresh.deliveredAt;
      fresh.loadedAt ??= fresh.inTransitAt;

      final otp = (fresh.pickupOtp ?? '').trim().isEmpty
          ? _generateOtp()
          : fresh.pickupOtp!.trim();

      fresh.pickupOtp = otp;
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

      await _safeSendOtpIfSms(fresh: fresh, otp: otp);
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

  static Future<void> refreshPickupQr(Property p) async {
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
}
