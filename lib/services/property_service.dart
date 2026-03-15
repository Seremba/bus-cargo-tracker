import '../data/routes.dart';
import '../data/routes_helpers.dart';
import '../models/property.dart';
import '../models/property_item_status.dart';
import '../models/property_status.dart';
import '../models/sync_event.dart';
import '../models/sync_event_type.dart';
import '../models/trip.dart';
import '../models/user_role.dart';

import 'audit_service.dart';
import 'hive_service.dart';
import 'notification_service.dart';
import 'outbound_message_service.dart';
import 'payment_service.dart';
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
    bool routeConfirmed = true,
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
    if (routeConfirmed && (cleanRouteId.isEmpty || cleanRouteName.isEmpty)) {
      throw ArgumentError('Confirmed route is required');
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
      routeConfirmed: routeConfirmed,
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
        'routeConfirmed': saved.routeConfirmed,
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
      routeConfirmed: (payload['routeConfirmed'] as bool?) ?? true,
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

  static Future<void> applyItemsLoadedPartialFromSync(SyncEvent event) async {
    final pBox = HiveService.propertyBox();
    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    final payload = event.payload;

    final propertyCode = (payload['propertyCode'] ?? '').toString().trim();
    if (propertyCode.isEmpty) return;

    Property? property;
    for (final p in pBox.values) {
      if (p.propertyCode.trim() == propertyCode) {
        property = p;
        break;
      }
    }

    if (property == null) return;

    final incomingVersion =
        (payload['aggregateVersion'] as num?)?.toInt() ??
        event.aggregateVersion;

    if (property.aggregateVersion >= incomingVersion) return;

    final rawItemNos = (payload['itemNos'] as List?) ?? const [];
    final itemNos =
        rawItemNos
            .map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();

    if (itemNos.isEmpty) return;

    final loadedAtRaw = (payload['loadedAt'] ?? '').toString().trim();
    final loadedAt = DateTime.tryParse(loadedAtRaw);
    if (loadedAt == null) return;

    final loadedAtStation = (payload['loadedAtStation'] ?? '')
        .toString()
        .trim();

    await itemSvc.ensureItemsForProperty(
      propertyKey: property.key.toString(),
      trackingCode: property.trackingCode,
      itemCount: property.itemCount,
    );

    final items = itemSvc.getItemsForProperty(property.key.toString());

    for (final item in items) {
      if (!itemNos.contains(item.itemNo)) continue;

      if (item.status == PropertyItemStatus.pending) {
        item.status = PropertyItemStatus.loaded;
        item.loadedAt ??= loadedAt;
        await item.save();
      }
    }

    property.loadedAt ??= loadedAt;
    if (property.loadedAtStation.trim().isEmpty && loadedAtStation.isNotEmpty) {
      property.loadedAtStation = loadedAtStation;
    }
    property.aggregateVersion = incomingVersion;
    await property.save();

    await itemSvc.recomputePropertyAggregate(property: property);
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
        fresh.status == PropertyStatus.loaded ||
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

    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    await itemSvc.ensureItemsForProperty(
      propertyKey: fresh.key.toString(),
      trackingCode: fresh.trackingCode,
      itemCount: fresh.itemCount,
    );

    final now = DateTime.now();
    final items = itemSvc.getItemsForProperty(fresh.key.toString());

    final inTransitNos =
        items
            .where((x) => x.status == PropertyItemStatus.inTransit)
            .map((x) => x.itemNo)
            .toList()
          ..sort();

    if (inTransitNos.isEmpty) {
      return;
    }

    await itemSvc.markItemsDelivered(
      propertyKey: fresh.key.toString(),
      itemNos: inTransitNos,
      now: now,
    );

    fresh.loadedAt ??= fresh.inTransitAt ?? now;
    if (fresh.loadedByUserId.trim().isEmpty) {
      fresh.loadedByUserId = (Session.currentUserId ?? 'system').trim();
    }

    fresh.deliveredAt ??= now;

    final otp = (fresh.pickupOtp ?? '').trim().isEmpty
        ? _generateOtp()
        : fresh.pickupOtp!.trim();

    fresh.pickupOtp = otp;
    fresh.otpGeneratedAt ??= now;
    fresh.otpAttempts = 0;
    fresh.otpLockedUntil = null;

    fresh.aggregateVersion += 1;
    await fresh.save();

    await itemSvc.recomputePropertyAggregate(property: fresh);

    final refreshed = box.get(fresh.key) ?? fresh;
    refreshed.deliveredAt ??= now;
    refreshed.inTransitAt ??= now;
    refreshed.loadedAt ??= now;
    await refreshed.save();

    await SyncService.enqueuePropertyDelivered(
      propertyId: refreshed.propertyCode.trim(),
      actorUserId: (Session.currentUserId ?? '').trim().isEmpty
          ? refreshed.createdByUserId
          : (Session.currentUserId ?? '').trim(),
      aggregateVersion: refreshed.aggregateVersion,
      payload: {
        'propertyCode': refreshed.propertyCode,
        'deliveredAt': now.toIso8601String(),
        'aggregateVersion': refreshed.aggregateVersion,
      },
    );

    await PickupQrService.issueForDelivered(refreshed, otp: otp);

    await _safeSendOtpIfSms(fresh: refreshed, otp: otp);

    await _safeNotifyReceiver(fresh: refreshed, eventLabel: 'DELIVERED');

    await NotificationService.notify(
      targetUserId: refreshed.createdByUserId,
      title: 'Property delivered to station',
      message:
          'Your property arrived at the destination station.\nOTP/QR issued for pickup.',
    );

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Store update: Delivered',
      message:
          'Property for ${refreshed.receiverName} delivered.\nOTP/QR issued for pickup.',
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

    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    await itemSvc.ensureItemsForProperty(
      propertyKey: fresh.key.toString(),
      trackingCode: fresh.trackingCode,
      itemCount: fresh.itemCount,
    );

    final now = DateTime.now();
    final items = itemSvc.getItemsForProperty(fresh.key.toString());

    final deliveredNos =
        items
            .where((x) => x.status == PropertyItemStatus.delivered)
            .map((x) => x.itemNo)
            .toList()
          ..sort();

    if (deliveredNos.isEmpty) return false;

    await itemSvc.markItemsPickedUp(
      propertyKey: fresh.key.toString(),
      itemNos: deliveredNos,
      now: now,
    );

    fresh.deliveredAt ??= now;
    fresh.inTransitAt ??= fresh.deliveredAt;
    fresh.loadedAt ??= fresh.inTransitAt;

    fresh.pickedUpAt = now;
    fresh.staffPickupConfirmed = true;
    fresh.receiverPickupConfirmed = true;

    fresh.pickupOtp = null;
    fresh.otpGeneratedAt = null;
    fresh.otpAttempts = 0;
    fresh.otpLockedUntil = null;

    fresh.qrConsumedAt = now;

    fresh.aggregateVersion += 1;
    await fresh.save();

    await itemSvc.recomputePropertyAggregate(property: fresh);

    final refreshed = HiveService.propertyBox().get(fresh.key) ?? fresh;
    refreshed.pickedUpAt ??= now;
    refreshed.deliveredAt ??= now;
    refreshed.inTransitAt ??= refreshed.deliveredAt;
    refreshed.loadedAt ??= refreshed.inTransitAt;
    refreshed.staffPickupConfirmed = true;
    refreshed.receiverPickupConfirmed = true;
    refreshed.qrConsumedAt ??= now;
    await refreshed.save();

    await SyncService.enqueuePropertyPickedUp(
      propertyId: refreshed.propertyCode.trim(),
      actorUserId: (Session.currentUserId ?? '').trim().isEmpty
          ? refreshed.createdByUserId
          : (Session.currentUserId ?? '').trim(),
      aggregateVersion: refreshed.aggregateVersion,
      payload: {
        'propertyCode': refreshed.propertyCode,
        'pickedUpAt': now.toIso8601String(),
        'aggregateVersion': refreshed.aggregateVersion,
      },
    );

    await _safeNotifyReceiver(fresh: refreshed, eventLabel: 'PICKED UP');

    await NotificationService.notify(
      targetUserId: refreshed.createdByUserId,
      title: 'Property picked up',
      message: 'Your property was picked up by the receiver.',
    );

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Pickup confirmed',
      message:
          'Receiver pickup confirmed for ${refreshed.receiverName} (${refreshed.receiverPhone}).',
    );

    return true;
  }

  static Future<void> applyPropertyPickedUpFromSync(SyncEvent event) async {
    final box = HiveService.propertyBox();
    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);
    final payload = event.payload;

    final propertyCode = (payload['propertyCode'] ?? '').toString().trim();
    if (propertyCode.isEmpty) return;

    Property? property;
    for (final p in box.values) {
      if (p.propertyCode.trim() == propertyCode) {
        property = p;
        break;
      }
    }

    if (property == null) return;

    final incomingVersion =
        (payload['aggregateVersion'] as num?)?.toInt() ??
        event.aggregateVersion;

    if (property.aggregateVersion >= incomingVersion) return;

    final pickedUpAtRaw = (payload['pickedUpAt'] ?? '').toString().trim();
    final pickedUpAt = DateTime.tryParse(pickedUpAtRaw);
    if (pickedUpAt == null) return;

    if (property.status != PropertyStatus.delivered) {
      property.aggregateVersion = incomingVersion;
      await property.save();
      return;
    }

    await itemSvc.ensureItemsForProperty(
      propertyKey: property.key.toString(),
      trackingCode: property.trackingCode,
      itemCount: property.itemCount,
    );

    final items = itemSvc.getItemsForProperty(property.key.toString());

    final deliveredNos =
        items
            .where((x) => x.status == PropertyItemStatus.delivered)
            .map((x) => x.itemNo)
            .toList()
          ..sort();

    if (deliveredNos.isNotEmpty) {
      await itemSvc.markItemsPickedUp(
        propertyKey: property.key.toString(),
        itemNos: deliveredNos,
        now: pickedUpAt,
      );
    }

    property.status = PropertyStatus.pickedUp;
    property.pickedUpAt ??= pickedUpAt;
    property.deliveredAt ??= pickedUpAt;
    property.inTransitAt ??= property.deliveredAt;
    property.loadedAt ??= property.inTransitAt;

    property.staffPickupConfirmed = true;
    property.receiverPickupConfirmed = true;
    property.qrConsumedAt ??= pickedUpAt;

    property.pickupOtp = null;
    property.otpGeneratedAt = null;
    property.otpAttempts = 0;
    property.otpLockedUntil = null;

    property.aggregateVersion = incomingVersion;

    await property.save();
    await itemSvc.recomputePropertyAggregate(property: property);

    final refreshed = box.get(property.key) ?? property;
    refreshed.status = PropertyStatus.pickedUp;
    refreshed.pickedUpAt ??= pickedUpAt;
    refreshed.deliveredAt ??= pickedUpAt;
    refreshed.inTransitAt ??= refreshed.deliveredAt;
    refreshed.loadedAt ??= refreshed.inTransitAt;
    refreshed.staffPickupConfirmed = true;
    refreshed.receiverPickupConfirmed = true;
    refreshed.qrConsumedAt ??= pickedUpAt;
    refreshed.pickupOtp = null;
    refreshed.otpGeneratedAt = null;
    refreshed.otpAttempts = 0;
    refreshed.otpLockedUntil = null;
    refreshed.aggregateVersion = incomingVersion;
    await refreshed.save();
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

    if (fresh.status != PropertyStatus.pending &&
        fresh.status != PropertyStatus.loaded) {
      return;
    }

    AppRoute? route = findRouteById(fresh.routeId);

    if (route == null) {
      final assigned = findRouteById(Session.currentAssignedRouteId);
      if (assigned != null) {
        route = assigned;
        fresh.routeId = assigned.id;
        fresh.routeName = assigned.name;
      }
    }

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
    final propertyKey = fresh.key.toString();

    await itemSvc.ensureItemsForProperty(
      propertyKey: propertyKey,
      trackingCode: fresh.trackingCode,
      itemCount: fresh.itemCount,
    );

    final itemsBefore = itemSvc.getItemsForProperty(propertyKey);

    final readyToMove = itemsBefore
        .where(
          (x) =>
              x.status == PropertyItemStatus.loaded && x.tripId.trim().isEmpty,
        )
        .toList();

    if (readyToMove.isEmpty) {
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

    Trip? trip = TripService.getActiveTripForCurrentDriver(routeId: route.id);

    if (trip == null) {
      try {
        trip = await TripService.ensureActiveTrip(
          routeId: route.id,
          routeName: route.name,
          checkpoints: cps,
        );
      } catch (e, st) {
        trip = TripService.getActiveTripForCurrentDriver(routeId: route.id);

        if (trip == null) {
          await AuditService.log(
            action: 'trip_ensure_failed',
            propertyKey: propertyKey,
            details: 'ensureActiveTrip failed: $e\n$st',
          );

          await NotificationService.notify(
            targetUserId: NotificationService.adminInbox,
            title: 'Trip start failed',
            message:
                'Failed to start trip for route "${route.name}".\nError: $e',
          );
          return;
        }
      }
    }

    await itemSvc.onTripStartedMoveLoadedToInTransitForProperty(
      propertyKey: propertyKey,
      tripId: trip.tripId,
      now: now,
    );

    var refreshedItems = itemSvc.getItemsForProperty(propertyKey);
    var movedCount = refreshedItems
        .where(
          (x) =>
              x.tripId.trim() == trip!.tripId &&
              x.status == PropertyItemStatus.inTransit,
        )
        .length;

    if (movedCount == 0) {
      for (final item in readyToMove) {
        final live = HiveService.propertyItemBox().get(item.itemKey);
        if (live == null) continue;

        if (live.status == PropertyItemStatus.loaded &&
            live.tripId.trim().isEmpty) {
          live.tripId = trip.tripId;
          live.status = PropertyItemStatus.inTransit;
          live.inTransitAt = now;
          await live.save();

          try {
            await SyncService.enqueueItemEvent(
              type: SyncEventType.propertyItemInTransit,
              itemId: live.itemKey,
              actorUserId: (Session.currentUserId ?? '').trim().isEmpty
                  ? 'system'
                  : (Session.currentUserId ?? '').trim(),
              payload: {
                'itemKey': live.itemKey,
                'propertyKey': live.propertyKey,
                'propertyCode': fresh.propertyCode,
                'itemNo': live.itemNo,
                'status': 'inTransit',
                'tripId': live.tripId,
                'labelCode': live.labelCode,
                'loadedAt': live.loadedAt?.toIso8601String(),
                'inTransitAt': live.inTransitAt?.toIso8601String(),
                'deliveredAt': live.deliveredAt?.toIso8601String(),
                'pickedUpAt': live.pickedUpAt?.toIso8601String(),
                'eventAt': now.toIso8601String(),
              },
            );
          } catch (_) {}
        }
      }

      refreshedItems = itemSvc.getItemsForProperty(propertyKey);
      movedCount = refreshedItems
          .where(
            (x) =>
                x.tripId.trim() == trip!.tripId &&
                x.status == PropertyItemStatus.inTransit,
          )
          .length;
    }

    if (movedCount == 0) {
      await AuditService.log(
        action: 'mark_in_transit_no_items_moved',
        propertyKey: propertyKey,
        details:
            'Trip ${trip.tripId} created/found, but no loaded items moved to inTransit.',
      );
      return;
    }

    final counts = itemSvc.computeTripCounts(
      propertyKey: propertyKey,
      tripId: trip.tripId,
    );

    fresh.routeId = route.id;
    fresh.routeName = route.name;
    fresh.status = PropertyStatus.inTransit;
    fresh.inTransitAt = now;
    fresh.loadedAt ??= now;
    fresh.tripId = trip.tripId;
    fresh.aggregateVersion += 1;
    await fresh.save();

    try {
      await SyncService.enqueuePropertyInTransit(
        propertyId: fresh.propertyCode.trim(),
        actorUserId: (Session.currentUserId ?? '').trim().isEmpty
            ? fresh.createdByUserId
            : (Session.currentUserId ?? '').trim(),
        aggregateVersion: fresh.aggregateVersion,
        payload: {
          'propertyCode': fresh.propertyCode,
          'tripId': trip.tripId,
          'routeId': fresh.routeId,
          'routeName': fresh.routeName,
          'inTransitAt': now.toIso8601String(),
          'loadedForTrip': counts.loadedForTrip,
          'remainingAtStation': counts.remainingAtStation,
          'total': counts.total,
          'aggregateVersion': fresh.aggregateVersion,
        },
      );
    } catch (e) {
      await AuditService.log(
        action: 'property_in_transit_sync_enqueue_failed',
        propertyKey: propertyKey,
        details:
            'Local transition succeeded, but enqueuePropertyInTransit failed: $e',
      );
    }

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

  static Future<void> applyPropertyInTransitFromSync(SyncEvent event) async {
    final pBox = HiveService.propertyBox();
    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    final payload = event.payload;
    final propertyCode = (payload['propertyCode'] ?? '').toString().trim();
    if (propertyCode.isEmpty) return;

    Property? property;
    for (final p in pBox.values) {
      if (p.propertyCode.trim() == propertyCode) {
        property = p;
        break;
      }
    }

    if (property == null) return;

    final incomingVersion =
        (payload['aggregateVersion'] as num?)?.toInt() ??
        event.aggregateVersion;

    if (property.aggregateVersion >= incomingVersion) return;

    final tripId = (payload['tripId'] ?? '').toString().trim();
    final routeId = (payload['routeId'] ?? '').toString().trim();
    final routeName = (payload['routeName'] ?? '').toString().trim();
    final inTransitAtRaw = (payload['inTransitAt'] ?? '').toString().trim();
    final inTransitAt = DateTime.tryParse(inTransitAtRaw);

    if (tripId.isEmpty || inTransitAt == null) return;

    await itemSvc.ensureItemsForProperty(
      propertyKey: property.key.toString(),
      trackingCode: property.trackingCode,
      itemCount: property.itemCount,
    );

    await itemSvc.onTripStartedMoveLoadedToInTransitForProperty(
      propertyKey: property.key.toString(),
      tripId: tripId,
      now: inTransitAt,
    );

    property.status = PropertyStatus.inTransit;
    property.tripId = tripId;
    if (routeId.isNotEmpty) property.routeId = routeId;
    if (routeName.isNotEmpty) property.routeName = routeName;
    property.inTransitAt ??= inTransitAt;
    property.loadedAt ??= inTransitAt;
    property.aggregateVersion = incomingVersion;

    await property.save();
    await itemSvc.recomputePropertyAggregate(property: property);

    final refreshed = pBox.get(property.key) ?? property;
    refreshed.status = PropertyStatus.inTransit;
    refreshed.tripId = tripId;
    if (routeId.isNotEmpty) refreshed.routeId = routeId;
    if (routeName.isNotEmpty) refreshed.routeName = routeName;
    refreshed.inTransitAt ??= inTransitAt;
    refreshed.loadedAt ??= inTransitAt;
    refreshed.aggregateVersion = incomingVersion;
    await refreshed.save();
  }

  static Future<void> applyPropertyDeliveredFromSync(SyncEvent event) async {
    final box = HiveService.propertyBox();
    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);
    final payload = event.payload;

    final propertyCode = (payload['propertyCode'] ?? '').toString().trim();
    if (propertyCode.isEmpty) return;

    Property? property;
    for (final p in box.values) {
      if (p.propertyCode.trim() == propertyCode) {
        property = p;
        break;
      }
    }

    if (property == null) return;

    final incomingVersion =
        (payload['aggregateVersion'] as num?)?.toInt() ??
        event.aggregateVersion;

    if (property.aggregateVersion >= incomingVersion) return;

    final deliveredAtRaw = (payload['deliveredAt'] ?? '').toString().trim();
    final deliveredAt = DateTime.tryParse(deliveredAtRaw);
    if (deliveredAt == null) return;

    if (property.status != PropertyStatus.inTransit) {
      property.aggregateVersion = incomingVersion;
      await property.save();
      return;
    }

    await itemSvc.ensureItemsForProperty(
      propertyKey: property.key.toString(),
      trackingCode: property.trackingCode,
      itemCount: property.itemCount,
    );

    final items = itemSvc.getItemsForProperty(property.key.toString());

    final inTransitNos =
        items
            .where((x) => x.status == PropertyItemStatus.inTransit)
            .map((x) => x.itemNo)
            .toList()
          ..sort();

    if (inTransitNos.isNotEmpty) {
      await itemSvc.markItemsDelivered(
        propertyKey: property.key.toString(),
        itemNos: inTransitNos,
        now: deliveredAt,
      );
    }

    property.status = PropertyStatus.delivered;
    property.deliveredAt ??= deliveredAt;
    property.inTransitAt ??= deliveredAt;
    property.loadedAt ??= property.inTransitAt;
    property.aggregateVersion = incomingVersion;

    await property.save();
    await itemSvc.recomputePropertyAggregate(property: property);

    final refreshed = box.get(property.key) ?? property;
    refreshed.status = PropertyStatus.delivered;
    refreshed.deliveredAt ??= deliveredAt;
    refreshed.inTransitAt ??= deliveredAt;
    refreshed.loadedAt ??= refreshed.inTransitAt;
    refreshed.aggregateVersion = incomingVersion;
    await refreshed.save();
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

    if (fresh.status != PropertyStatus.pending &&
        fresh.status != PropertyStatus.loaded) {
      return false;
    }

    final propertyKey = fresh.key.toString();

    final isPaid = PaymentService.hasValidPaymentForProperty(propertyKey);
    if (!isPaid) {
      await AuditService.log(
        action: 'desk_mark_loaded_blocked_unpaid',
        propertyKey: propertyKey,
        details:
            'Blocked loading because no valid payment exists for property '
            '${fresh.propertyCode.trim().isEmpty ? propertyKey : fresh.propertyCode.trim()}',
      );
      return false;
    }

    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    await itemSvc.ensureItemsForProperty(
      propertyKey: propertyKey,
      trackingCode: fresh.trackingCode,
      itemCount: fresh.itemCount,
    );

    final selectedNos =
        (itemNos == null || itemNos.isEmpty)
              ? List<int>.generate(fresh.itemCount, (i) => i + 1)
              : itemNos.toSet().toList()
          ..sort();

    final now = DateTime.now();

    await itemSvc.markSelectedItemsLoaded(
      propertyKey: propertyKey,
      itemNos: selectedNos,
      now: now,
    );

    fresh.loadedAt ??= now;
    fresh.loadedAtStation = station.trim();
    fresh.loadedByUserId = (Session.currentUserId ?? '').trim();
    fresh.aggregateVersion += 1;
    await fresh.save();

    await itemSvc.recomputePropertyAggregate(property: fresh);

    final items = itemSvc.getItemsForProperty(propertyKey);
    final loadedCount = items
        .where((x) => x.status == PropertyItemStatus.loaded)
        .length;
    final remainingCount = items
        .where((x) => x.status == PropertyItemStatus.pending)
        .length;

    await AuditService.log(
      action: 'desk_mark_loaded_items',
      propertyKey: propertyKey,
      details:
          'Loaded items: ${selectedNos.join(",")} at station: ${fresh.loadedAtStation}',
    );

    await SyncService.enqueueItemsLoadedPartial(
      propertyId: fresh.propertyCode.trim(),
      actorUserId: (Session.currentUserId ?? '').trim().isEmpty
          ? fresh.createdByUserId
          : (Session.currentUserId ?? '').trim(),
      aggregateVersion: fresh.aggregateVersion,
      payload: {
        'propertyCode': fresh.propertyCode,
        'propertyKey': propertyKey,
        'itemNos': selectedNos,
        'loadedCount': loadedCount,
        'remainingCount': remainingCount,
        'loadedAt': now.toIso8601String(),
        'loadedAtStation': fresh.loadedAtStation,
        'aggregateVersion': fresh.aggregateVersion,
      },
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

    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    await itemSvc.ensureItemsForProperty(
      propertyKey: fresh.key.toString(),
      trackingCode: fresh.trackingCode,
      itemCount: fresh.itemCount,
    );

    final actorUserId = (Session.currentUserId ?? '').trim().isEmpty
        ? 'admin'
        : (Session.currentUserId ?? '').trim();

    final fromStatus = fresh.status.name;

    if (newStatus == PropertyStatus.inTransit &&
        (fresh.status == PropertyStatus.pending ||
            fresh.status == PropertyStatus.loaded)) {
      await markInTransit(fresh);

      final updated = HiveService.propertyBox().get(fresh.key) ?? fresh;
      await SyncService.enqueueAdminOverrideApplied(
        aggregateType: 'property',
        aggregateId: updated.propertyCode.trim(),
        actorUserId: actorUserId,
        payload: {
          'propertyCode': updated.propertyCode,
          'fromStatus': fromStatus,
          'toStatus': PropertyStatus.inTransit.name,
          'propertyKey': updated.key.toString(),
          'resetItems': false,
          'appliedAt': DateTime.now().toIso8601String(),
        },
      );
      return;
    }

    if (newStatus == PropertyStatus.delivered &&
        fresh.status == PropertyStatus.inTransit) {
      await markDelivered(fresh);

      final updated = HiveService.propertyBox().get(fresh.key) ?? fresh;
      await SyncService.enqueueAdminOverrideApplied(
        aggregateType: 'property',
        aggregateId: updated.propertyCode.trim(),
        actorUserId: actorUserId,
        payload: {
          'propertyCode': updated.propertyCode,
          'fromStatus': fromStatus,
          'toStatus': PropertyStatus.delivered.name,
          'propertyKey': updated.key.toString(),
          'resetItems': false,
          'appliedAt': DateTime.now().toIso8601String(),
        },
      );
      return;
    }

    if (newStatus == PropertyStatus.pickedUp &&
        fresh.status == PropertyStatus.delivered) {
      final otp = (fresh.pickupOtp ?? '').trim();
      final usedNormalOtpFlow = otp.isNotEmpty;

      if (usedNormalOtpFlow) {
        final ok = await confirmPickupWithOtp(fresh, otp);
        if (!ok) return;
      } else {
        final now = DateTime.now();

        final items = itemSvc.getItemsForProperty(fresh.key.toString());
        final deliveredNos =
            items
                .where((x) => x.status == PropertyItemStatus.delivered)
                .map((x) => x.itemNo)
                .toList()
              ..sort();

        if (deliveredNos.isNotEmpty) {
          await itemSvc.markItemsPickedUp(
            propertyKey: fresh.key.toString(),
            itemNos: deliveredNos,
            now: now,
          );
        }

        fresh.pickedUpAt ??= now;
        fresh.deliveredAt ??= now;
        fresh.inTransitAt ??= fresh.deliveredAt;
        fresh.loadedAt ??= fresh.inTransitAt;

        fresh.status = PropertyStatus.pickedUp;
        fresh.staffPickupConfirmed = true;
        fresh.receiverPickupConfirmed = true;

        fresh.pickupOtp = null;
        fresh.otpGeneratedAt = null;
        fresh.otpAttempts = 0;
        fresh.otpLockedUntil = null;

        fresh.qrConsumedAt ??= now;
        fresh.aggregateVersion += 1;
        await fresh.save();

        await itemSvc.recomputePropertyAggregate(property: fresh);

        await SyncService.enqueuePropertyPickedUp(
          propertyId: fresh.propertyCode.trim(),
          actorUserId: actorUserId,
          aggregateVersion: fresh.aggregateVersion,
          payload: {
            'propertyCode': fresh.propertyCode,
            'pickedUpAt': now.toIso8601String(),
            'aggregateVersion': fresh.aggregateVersion,
          },
        );
      }

      final updated = HiveService.propertyBox().get(fresh.key) ?? fresh;

      await SyncService.enqueueAdminOverrideApplied(
        aggregateType: 'property',
        aggregateId: updated.propertyCode.trim(),
        actorUserId: actorUserId,
        payload: {
          'propertyCode': updated.propertyCode,
          'fromStatus': fromStatus,
          'toStatus': PropertyStatus.pickedUp.name,
          'propertyKey': updated.key.toString(),
          'resetItems': false,
          'appliedAt': DateTime.now().toIso8601String(),
        },
      );

      await AuditService.log(
        action: 'admin_set_status',
        propertyKey: updated.key.toString(),
        details: 'Admin set status to pickedUp',
      );

      if (!usedNormalOtpFlow) {
        await _safeNotifyReceiver(fresh: updated, eventLabel: 'PICKED UP');

        await NotificationService.notify(
          targetUserId: updated.createdByUserId,
          title: 'Admin status update',
          message:
              'Admin updated your property for ${updated.receiverName} to pickedUp.',
        );

        await NotificationService.notify(
          targetUserId: NotificationService.adminInbox,
          title: 'Admin override applied',
          message:
              'Status set to pickedUp for ${updated.receiverName} (${updated.receiverPhone}).',
        );
      }

      return;
    }

    if (newStatus == PropertyStatus.pending) {
      final items = itemSvc.getItemsForProperty(fresh.key.toString());

      for (final item in items) {
        item.status = PropertyItemStatus.pending;
        item.tripId = '';
        item.loadedAt = null;
        item.inTransitAt = null;
        item.deliveredAt = null;
        item.pickedUpAt = null;
        await item.save();
      }

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

      fresh.aggregateVersion += 1;
      await fresh.save();

      await SyncService.enqueueAdminOverrideApplied(
        aggregateType: 'property',
        aggregateId: fresh.propertyCode.trim(),
        actorUserId: actorUserId,
        payload: {
          'propertyCode': fresh.propertyCode,
          'fromStatus': fromStatus,
          'toStatus': PropertyStatus.pending.name,
          'propertyKey': fresh.key.toString(),
          'resetItems': true,
          'appliedAt': DateTime.now().toIso8601String(),
        },
      );

      await _safeNotifyReceiver(fresh: fresh, eventLabel: 'PENDING');

      await AuditService.log(
        action: 'admin_set_status',
        propertyKey: fresh.key.toString(),
        details: 'Admin set status to pending (full reset)',
      );
      return;
    }

    await AuditService.log(
      action: 'admin_set_status_skipped',
      propertyKey: fresh.key.toString(),
      details:
          'Admin attempted unsupported transition ${fresh.status.name} -> ${newStatus.name}',
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

  static Future<Trip?> startRouteTrip({required String routeId}) async {
    if (!RoleGuard.hasAny({UserRole.driver, UserRole.admin})) return null;

    final route = findRouteById(routeId);
    if (route == null) {
      throw StateError('Route not found');
    }

    final cps = validatedCheckpoints(route);
    if (cps.isEmpty) {
      throw StateError('Route has invalid checkpoints');
    }

    final itemBox = HiveService.propertyItemBox();
    final pBox = HiveService.propertyBox();
    final itemSvc = PropertyItemService(itemBox);

    final now = DateTime.now();

    final trip = await TripService.ensureActiveTrip(
      routeId: route.id,
      routeName: route.name,
      checkpoints: cps,
    );

    final candidates = pBox.values.where((p) {
      if (p.routeId != route.id) return false;
      if (p.status != PropertyStatus.pending &&
          p.status != PropertyStatus.loaded) {
        return false;
      }
      return true;
    }).toList();

    for (final property in candidates) {
      await itemSvc.ensureItemsForProperty(
        propertyKey: property.key.toString(),
        trackingCode: property.trackingCode,
        itemCount: property.itemCount,
      );

      final items = itemSvc.getItemsForProperty(property.key.toString());

      final hasLoadedReady = items.any(
        (x) => x.status == PropertyItemStatus.loaded && x.tripId.trim().isEmpty,
      );

      if (!hasLoadedReady) continue;

      await itemSvc.onTripStartedMoveLoadedToInTransitForProperty(
        propertyKey: property.key.toString(),
        tripId: trip.tripId,
        now: now,
      );

      final counts = itemSvc.computeTripCounts(
        propertyKey: property.key.toString(),
        tripId: trip.tripId,
      );

      property.status = PropertyStatus.inTransit;
      property.inTransitAt = now;
      property.loadedAt ??= now;
      property.tripId = trip.tripId;
      property.aggregateVersion += 1;
      await property.save();

      await SyncService.enqueuePropertyInTransit(
        propertyId: property.propertyCode.trim(),
        actorUserId: (Session.currentUserId ?? '').trim().isEmpty
            ? property.createdByUserId
            : (Session.currentUserId ?? '').trim(),
        aggregateVersion: property.aggregateVersion,
        payload: {
          'propertyCode': property.propertyCode,
          'tripId': trip.tripId,
          'routeId': property.routeId,
          'routeName': property.routeName,
          'inTransitAt': now.toIso8601String(),
          'loadedForTrip': counts.loadedForTrip,
          'remainingAtStation': counts.remainingAtStation,
          'total': counts.total,
          'aggregateVersion': property.aggregateVersion,
        },
      );

      final msg =
          'Departed today: ${counts.loadedForTrip}/${counts.total}\n'
          'Remaining at station: ${counts.remainingAtStation}/${counts.total}\n'
          'Route: ${route.name}';

      await NotificationService.notify(
        targetUserId: property.createdByUserId,
        title: 'Property in transit',
        message: 'Your property is now in transit.\n$msg',
      );

      if (counts.remainingAtStation > 0) {
        await _safeNotifyReceiverPartialLoad(
          fresh: property,
          counts: counts,
          routeName: route.name,
        );
      } else {
        await _safeNotifyReceiver(fresh: property, eventLabel: 'IN TRANSIT');
      }
    }

    return trip;
  }
}
