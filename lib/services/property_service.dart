import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

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
import 'property_ttl_service.dart';
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

    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final rng = Random.secure();
    final suffix = List.generate(
      6,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();

    return 'P-$y$m$d-$suffix';
  }

  static String _generateOtp() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  static String _hashOtp(String otp, String propertyCode) {
    final salted = '$propertyCode:$otp';
    return sha256.convert(utf8.encode(salted)).toString();
  }

  static String _newNonce() {
    final rng = Random.secure();
    return List.generate(
      16,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _computeCommitHash(Property p) {
    final canonical =
        '${p.propertyCode}|${p.receiverName.trim()}'
        '|${p.receiverPhone.trim()}|${p.destination.trim()}'
        '|${p.itemCount}|${p.routeId.trim()}';
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static Future<void> lockProperty(Property p) async {
    final fresh = HiveService.propertyBox().get(p.key) ?? p;
    if (fresh.isLocked) return;

    fresh.isLocked = true;
    fresh.commitHash = _computeCommitHash(fresh);
    await fresh.save();

    await AuditService.log(
      action: 'PROPERTY_LOCKED',
      propertyKey: fresh.key.toString(),
      details: 'Locked. commitHash=${fresh.commitHash}',
    );
  }

  static bool verifyCommitHash(Property p) {
    final stored = (p.commitHash ?? '').trim();
    if (stored.isEmpty) return false;
    return _computeCommitHash(p) == stored;
  }

  static const Duration _otpTtl = Duration(hours: 12);
  static const int _maxOtpAttempts = 3;
  static const Duration _otpLockDuration = Duration(minutes: 10);

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

  static const List<String> rejectionCategories = [
    'item_count_mismatch',
    'wrong_goods',
    'damaged_prohibited',
    'other',
  ];

  static String rejectionCategoryLabel(String category) {
    switch (category) {
      case 'item_count_mismatch':
        return 'Item count mismatch';
      case 'wrong_goods':
        return 'Wrong goods description';
      case 'damaged_prohibited':
        return 'Damaged / prohibited goods';
      case 'other':
        return 'Other';
      default:
        return category;
    }
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
      isLocked: false,
      commitHash: null,
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

    if (existing != null) return;

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
      isLocked: (payload['isLocked'] as bool?) ?? false,
      commitHash: payload['commitHash'] as String?,
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

    if (fresh.loadedAtStation.trim().isEmpty) fresh.loadedAtStation = '';
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

  static Future<bool> markLoaded(
    Property p, {
    required String station,
    List<int>? itemNos,
  }) async {
    if (!RoleGuard.hasAnyVerified({
      UserRole.deskCargoOfficer,
      UserRole.admin,
    })) {
      return false;
    }

    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(p.key) ?? p;

    if (fresh.status != PropertyStatus.pending &&
        fresh.status != PropertyStatus.loaded) {
      return false;
    }

    if (fresh.isLocked) {
      if ((fresh.commitHash ?? '').trim().isEmpty) {
        fresh.commitHash = _computeCommitHash(fresh);
        await fresh.save();

        await AuditService.log(
          action: 'MARK_LOADED_HASH_REPAIRED',
          propertyKey: fresh.key.toString(),
          details:
              'Property was locked but had no commitHash. '
              'Hash computed and stored at load time.',
        );
      } else if (!verifyCommitHash(fresh)) {
        await AuditService.log(
          action: 'MARK_LOADED_HASH_MISMATCH',
          propertyKey: fresh.key.toString(),
          details:
              'markLoaded blocked: commitHash mismatch. '
              'Property data may have been tampered with after QR issuance.',
        );
        await NotificationService.notify(
          targetUserId: NotificationService.adminInbox,
          title: 'Security alert: property hash mismatch',
          message:
              'Property ${fresh.propertyCode} for ${fresh.receiverName} failed '
              'commit-hash verification at load time. '
              'Data may have been altered after QR issuance.',
        );
        return false;
      }
    }

    final hasPayment =
        fresh.amountPaidTotal > 0 ||
        HiveService.paymentBox().values.any(
          (x) => x.propertyKey.trim() == fresh.key.toString(),
        );

    if (!hasPayment) return false;

    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    await itemSvc.ensureItemsForProperty(
      propertyKey: fresh.key.toString(),
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
      propertyKey: fresh.key.toString(),
      itemNos: selectedNos,
      now: now,
    );

    fresh.loadedAt ??= now;
    fresh.loadedAtStation = station.trim();
    fresh.loadedByUserId = (Session.currentUserId ?? '').trim();
    fresh.aggregateVersion += 1;
    await fresh.save();

    await itemSvc.recomputePropertyAggregate(property: fresh);

    final items = itemSvc.getItemsForProperty(fresh.key.toString());
    final loadedCount = items
        .where((x) => x.status == PropertyItemStatus.loaded)
        .length;
    final remainingCount = items
        .where((x) => x.status == PropertyItemStatus.pending)
        .length;

    await AuditService.log(
      action: 'desk_mark_loaded_items',
      propertyKey: fresh.key.toString(),
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
        'propertyKey': fresh.key.toString(),
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

  static Future<void> markDelivered(Property p) async {
    if (!RoleGuard.hasAnyVerified({UserRole.staff, UserRole.admin})) return;

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

    if (inTransitNos.isEmpty) return;

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

    final bool isFirstDelivery =
        fresh.pickupOtp == null || fresh.pickupOtp!.trim().isEmpty;
    final String otpPlaintext = isFirstDelivery ? _generateOtp() : '';

    if (isFirstDelivery) {
      fresh.pickupOtp = _hashOtp(otpPlaintext, fresh.propertyCode);
      fresh.otpGeneratedAt = now;
    }

    fresh.otpAttempts = 0;
    fresh.otpLockedUntil = null;
    fresh.qrNonce = _newNonce();
    fresh.qrIssuedAt = now;
    fresh.qrConsumedAt = null;

    fresh.aggregateVersion += 1;
    await fresh.save();

    await itemSvc.recomputePropertyAggregate(property: fresh);

    final refreshed = box.get(fresh.key) ?? fresh;
    refreshed.deliveredAt ??= now;
    refreshed.inTransitAt ??= now;
    refreshed.loadedAt ??= refreshed.inTransitAt;
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

    if (otpPlaintext.isNotEmpty) {
      await PickupQrService.issueForDelivered(refreshed, otp: otpPlaintext);
      await _safeSendOtpIfSms(fresh: refreshed, otp: otpPlaintext);
    }

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
    final result = await confirmPickupWithOtpAndPhone(
      p,
      otp: otp,
      receiverPhoneLast4: '',
    );
    return result == PickupResult.success;
  }

  static Future<PickupResult> confirmPickupWithOtpAndPhone(
    Property p, {
    required String otp,
    required String receiverPhoneLast4,
  }) async {
    if (!RoleGuard.hasAnyVerified({UserRole.staff, UserRole.admin})) {
      return PickupResult.notAuthorized;
    }

    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    await repairMissingLoadedMilestone(fresh);

    if (fresh.status != PropertyStatus.delivered) {
      return PickupResult.notDelivered;
    }
    if (fresh.pickupOtp == null) return PickupResult.otpMissing;
    if (_isOtpLocked(fresh)) return PickupResult.otpLocked;
    if (_isOtpExpired(fresh)) return PickupResult.otpExpired;

    if (receiverPhoneLast4.trim().isNotEmpty) {
      final storedPhone = fresh.receiverPhone.trim();
      final storedDigits = storedPhone.replaceAll(RegExp(r'\D'), '');
      final enteredDigits = receiverPhoneLast4.trim().replaceAll(
        RegExp(r'\D'),
        '',
      );

      if (enteredDigits.length != 4) return PickupResult.phoneMismatch;

      if (!storedDigits.endsWith(enteredDigits)) {
        await AuditService.log(
          action: 'PICKUP_PHONE_MISMATCH',
          propertyKey: fresh.key.toString(),
          details:
              'Phone last-4 mismatch. Staff entered: $enteredDigits. '
              'Station: ${(Session.currentStationName ?? '').trim()}',
        );
        return PickupResult.phoneMismatch;
      }
    }

    final inputHash = _hashOtp(otp.trim(), fresh.propertyCode);

    if (inputHash != fresh.pickupOtp) {
      fresh.otpAttempts = fresh.otpAttempts + 1;
      fresh.qrNonce = _newNonce();

      if (fresh.otpAttempts >= _maxOtpAttempts) {
        fresh.otpLockedUntil = DateTime.now().add(_otpLockDuration);
      }
      await fresh.save();

      await AuditService.log(
        action: 'OTP_FAILED_ATTEMPT',
        propertyKey: fresh.key.toString(),
        details:
            'Failed OTP attempt ${fresh.otpAttempts}/$_maxOtpAttempts. '
            'QR nonce rotated.',
      );

      return PickupResult.otpWrong;
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

    if (deliveredNos.isEmpty) return PickupResult.noItems;

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
          'Receiver pickup confirmed for ${refreshed.receiverName} '
          '(${refreshed.receiverPhone}).',
    );

    return PickupResult.success;
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
    if (!RoleGuard.hasRoleVerified(UserRole.admin)) return;

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

  static Future<String?> adminResetOtp(Property p) async {
    if (!RoleGuard.hasRoleVerified(UserRole.admin)) return null;

    final fresh = HiveService.propertyBox().get(p.key) ?? p;
    if (fresh.status != PropertyStatus.delivered) return null;

    final otp = _generateOtp();

    fresh.pickupOtp = _hashOtp(otp, fresh.propertyCode);
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

    return otp;
  }

  static Future<bool> rejectProperty(
    Property p, {
    required String category,
    String reason = '',
  }) async {
    if (!RoleGuard.hasAnyVerified({
      UserRole.deskCargoOfficer,
      UserRole.admin,
    })) {
      return false;
    }

    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    if (fresh.status != PropertyStatus.pending &&
        fresh.status != PropertyStatus.loaded) {
      return false;
    }

    final cleanCategory = category.trim();
    if (!rejectionCategories.contains(cleanCategory)) return false;

    final now = DateTime.now();

    fresh.status = PropertyStatus.rejected;
    fresh.rejectionCategory = cleanCategory;
    fresh.rejectionReason = reason.trim();
    fresh.rejectedByUserId = (Session.currentUserId ?? '').trim();
    fresh.rejectedAt = now;
    fresh.aggregateVersion += 1;
    await fresh.save();

    await AuditService.log(
      action: 'PROPERTY_REJECTED',
      propertyKey: fresh.key.toString(),
      details:
          'Rejected by ${fresh.rejectedByUserId} | '
          'Category: ${rejectionCategoryLabel(cleanCategory)} | '
          'Reason: ${reason.trim().isEmpty ? '—' : reason.trim()}',
    );

    await SyncService.enqueueAdminOverrideApplied(
      aggregateType: 'property',
      aggregateId: fresh.propertyCode.trim(),
      actorUserId: (Session.currentUserId ?? '').trim(),
      payload: {
        'propertyCode': fresh.propertyCode,
        'fromStatus': PropertyStatus.pending.name,
        'toStatus': PropertyStatus.rejected.name,
        'rejectionCategory': cleanCategory,
        'rejectionReason': reason.trim(),
        'rejectedAt': now.toIso8601String(),
        'aggregateVersion': fresh.aggregateVersion,
      },
    );

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'Property rejected at station',
      message:
          'Your property (${fresh.propertyCode}) was rejected at '
          '${(Session.currentStationName ?? 'the station').trim()}.\n'
          'Reason: ${rejectionCategoryLabel(cleanCategory)}'
          '${reason.trim().isEmpty ? '' : ' — ${reason.trim()}'}.\n'
          'You may request a review if you believe this is an error.',
    );

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Property rejected',
      message:
          'Property ${fresh.propertyCode} for ${fresh.receiverName} was '
          'rejected by ${fresh.rejectedByUserId}.\n'
          'Category: ${rejectionCategoryLabel(cleanCategory)}\n'
          '${reason.trim().isEmpty ? '' : 'Reason: ${reason.trim()}'}',
    );

    return true;
  }

  // ── Re-review flow ──────────────────────────────────────────────────────
  // Sender requests a review. Status moves to underReview — NOT pending.
  // Admin must approve (→ pending) or deny (→ rejected) before anything
  // can proceed at the desk.

  /// Sender taps "Request Re-Review" on a rejected property.
  /// Sets status to [PropertyStatus.underReview] and notifies admin.
  /// Does NOT restore to pending — that is admin's decision only.
  /// Sender submits edited property for re-review after making changes.
  /// [changeSummary] is a human-readable summary of what changed, shown to admin.
  /// Should only be called after the sender has saved edits via EditRejectedPropertyScreen.
  static Future<bool> requestReReview(
    Property p, {
    String changeSummary = '',
  }) async {
    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    // Only callable from rejected
    if (fresh.status != PropertyStatus.rejected) return false;

    final currentUserId = (Session.currentUserId ?? '').trim();
    if (currentUserId != fresh.createdByUserId.trim()) return false;

    fresh.status = PropertyStatus.underReview;
    fresh.aggregateVersion += 1;
    await fresh.save();

    await AuditService.log(
      action: 'PROPERTY_REREVIEW_REQUESTED',
      propertyKey: fresh.key.toString(),
      details:
          'Sender $currentUserId submitted re-review for ${fresh.propertyCode}.'
          '${changeSummary.isEmpty ? '' : '\nChanges: $changeSummary'}',
    );

    await SyncService.enqueueAdminOverrideApplied(
      aggregateType: 'property',
      aggregateId: fresh.propertyCode.trim(),
      actorUserId: currentUserId,
      payload: {
        'propertyCode': fresh.propertyCode,
        'fromStatus': PropertyStatus.rejected.name,
        'toStatus': PropertyStatus.underReview.name,
        'changeSummary': changeSummary,
        'aggregateVersion': fresh.aggregateVersion,
      },
    );

    final changeNote = changeSummary.isEmpty
        ? ''
        : '\nEdited fields: $changeSummary';

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Re-review requested — property edited',
      message:
          'Sender has edited and resubmitted property ${fresh.propertyCode} '
          'for ${fresh.receiverName}.\n'
          'Original rejection: ${rejectionCategoryLabel(fresh.rejectionCategory ?? 'other')}'
          '$changeNote\n'
          'Please review and either approve (restore to Pending) or deny.',
    );

    return true;
  }

  /// Admin approves the re-review: resets items and restores property to pending.
  /// Accepts both [PropertyStatus.rejected] and [PropertyStatus.underReview].
  static Future<bool> adminRestoreRejected(Property p) async {
    if (!RoleGuard.hasRoleVerified(UserRole.admin)) return false;

    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    if (fresh.status != PropertyStatus.rejected &&
        fresh.status != PropertyStatus.underReview) {
      return false;
    }

    // Reset all items that haven't completed the full journey back to pending
    // so the desk officer can re-select and re-load them.
    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    await itemSvc.ensureItemsForProperty(
      propertyKey: fresh.key.toString(),
      trackingCode: fresh.trackingCode,
      itemCount: fresh.itemCount,
    );

    final items = itemSvc.getItemsForProperty(fresh.key.toString());
    int resetCount = 0;

    for (final item in items) {
      if (item.status == PropertyItemStatus.pickedUp) continue;
      item.status = PropertyItemStatus.pending;
      item.tripId = '';
      item.loadedAt = null;
      item.inTransitAt = null;
      item.deliveredAt = null;
      await item.save();
      resetCount++;
    }

    final fromStatus = fresh.status.name;

    fresh.status = PropertyStatus.pending;
    fresh.rejectionCategory = null;
    fresh.rejectionReason = null;
    fresh.rejectedByUserId = null;
    fresh.rejectedAt = null;
    fresh.isLocked = false;
    fresh.commitHash = null;
    fresh.loadedAt = null;
    fresh.loadedAtStation = '';
    fresh.loadedByUserId = '';
    fresh.tripId = null;
    fresh.inTransitAt = null;
    fresh.aggregateVersion += 1;
    await fresh.save();

    await itemSvc.recomputePropertyAggregate(property: fresh);

    await AuditService.log(
      action: 'PROPERTY_REJECTION_RESTORED',
      propertyKey: fresh.key.toString(),
      details:
          'Admin ${(Session.currentUserId ?? '').trim()} approved re-review, '
          'restored $fromStatus → pending. '
          '$resetCount item(s) reset for re-loading.',
    );

    await SyncService.enqueueAdminOverrideApplied(
      aggregateType: 'property',
      aggregateId: fresh.propertyCode.trim(),
      actorUserId: (Session.currentUserId ?? '').trim(),
      payload: {
        'propertyCode': fresh.propertyCode,
        'fromStatus': fromStatus,
        'toStatus': PropertyStatus.pending.name,
        'resetItems': true,
        'appliedAt': DateTime.now().toIso8601String(),
        'aggregateVersion': fresh.aggregateVersion,
      },
    );

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'Re-review approved',
      message:
          'Admin has approved your re-review request for property '
          '(${fresh.propertyCode}). It has been restored to Pending.\n'
          'Please re-present it at the desk for loading.',
    );

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Re-review approved — desk action needed',
      message:
          'Property ${fresh.propertyCode} for ${fresh.receiverName} restored '
          'to Pending. $resetCount item(s) reset. '
          'Desk officer should re-load and re-process.',
    );

    return true;
  }

  /// Admin denies the re-review: sets status back to rejected, notifies sender.
  static Future<bool> adminDenyReReview(Property p, {String note = ''}) async {
    if (!RoleGuard.hasRoleVerified(UserRole.admin)) return false;

    final fresh = HiveService.propertyBox().get(p.key) ?? p;
    if (fresh.status != PropertyStatus.underReview) return false;

    fresh.status = PropertyStatus.rejected;
    fresh.aggregateVersion += 1;
    await fresh.save();

    await AuditService.log(
      action: 'PROPERTY_REREVIEW_DENIED',
      propertyKey: fresh.key.toString(),
      details:
          'Admin ${(Session.currentUserId ?? '').trim()} denied re-review. '
          '${note.trim().isEmpty ? '' : 'Note: ${note.trim()}'}',
    );

    await SyncService.enqueueAdminOverrideApplied(
      aggregateType: 'property',
      aggregateId: fresh.propertyCode.trim(),
      actorUserId: (Session.currentUserId ?? '').trim(),
      payload: {
        'propertyCode': fresh.propertyCode,
        'fromStatus': PropertyStatus.underReview.name,
        'toStatus': PropertyStatus.rejected.name,
        'note': note.trim(),
        'aggregateVersion': fresh.aggregateVersion,
      },
    );

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'Re-review denied',
      message:
          'Your re-review request for property (${fresh.propertyCode}) '
          'has been denied by admin. The rejection stands.\n'
          '${note.trim().isEmpty ? '' : 'Note: ${note.trim()}\n'}'
          'Contact the desk or admin if you have questions.',
    );

    return true;
  }

  // ── F5 + adminSetStatus ─────────────────────────────────────────────────
  static Future<void> adminSetStatus(
    Property p,
    PropertyStatus newStatus,
  ) async {
    if (!RoleGuard.hasRoleVerified(UserRole.admin)) return;

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

    // F5: expired → pending via PropertyTtlService
    if (fresh.status == PropertyStatus.expired &&
        newStatus == PropertyStatus.pending) {
      await PropertyTtlService.adminRestoreExpired(fresh);
      return;
    }

    // Guard: expired transitions only via PropertyTtlService
    if (fresh.status == PropertyStatus.expired ||
        newStatus == PropertyStatus.expired) {
      await AuditService.log(
        action: 'admin_set_status_skipped',
        propertyKey: fresh.key.toString(),
        details:
            'Blocked unsupported expired transition: '
            '${fresh.status.name} -> ${newStatus.name}.',
      );
      return;
    }

    // underReview: approve (→ pending) or deny (→ rejected) via dedicated methods
    if (fresh.status == PropertyStatus.underReview ||
        newStatus == PropertyStatus.underReview) {
      await AuditService.log(
        action: 'admin_set_status_skipped',
        propertyKey: fresh.key.toString(),
        details:
            'Blocked direct underReview transition: '
            '${fresh.status.name} -> ${newStatus.name}. '
            'Use adminRestoreRejected or adminDenyReReview.',
      );
      return;
    }

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
        details: 'Admin set status to pickedUp (direct override)',
      );

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

      return;
    }

    // Restore rejected → pending (direct, no re-review flow)
    if (newStatus == PropertyStatus.pending &&
        fresh.status == PropertyStatus.rejected) {
      await adminRestoreRejected(fresh);
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
          'Admin attempted unsupported transition '
          '${fresh.status.name} -> ${newStatus.name}',
    );
  }

  static Future<void> markInTransit(Property p) async {
    if (!RoleGuard.hasAnyVerified({UserRole.driver, UserRole.admin})) return;

    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(p.key) ?? p;

    if (fresh.status != PropertyStatus.pending &&
        fresh.status != PropertyStatus.loaded) {
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

    final beforeItems = itemSvc.getItemsForProperty(fresh.key.toString());

    final hasLoaded = beforeItems.any(
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

    final activeSameRoute = TripService.getActiveTripForCurrentDriver(
      routeId: route.id,
    );

    if (activeSameRoute == null) {
      final activeAnyRoute = TripService.getActiveTripForCurrentDriver();
      if (activeAnyRoute != null && activeAnyRoute.routeId != route.id) {
        await NotificationService.notify(
          targetUserId: NotificationService.adminInbox,
          title: 'Route mismatch blocked',
          message:
              'Driver has an active trip (${activeAnyRoute.routeName}) but tried '
              'to load cargo for route (${route.name}).\nBlocked to avoid mixing routes.',
        );
        return;
      }
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
      throw StateError('markInTransit ensureActiveTrip failed: $e\n$st');
    }

    await itemSvc.onTripStartedMoveLoadedToInTransitForProperty(
      propertyKey: fresh.key.toString(),
      tripId: trip.tripId,
      now: now,
    );

    final afterItems = itemSvc.getItemsForProperty(fresh.key.toString());

    final movedCount = afterItems.where((x) {
      return x.tripId.trim() == trip.tripId &&
          x.status == PropertyItemStatus.inTransit;
    }).length;

    if (movedCount <= 0) {
      await AuditService.log(
        action: 'property_in_transit_no_items_moved',
        propertyKey: fresh.key.toString(),
        details:
            'Trip ${trip.tripId} started but no items moved to inTransit '
            'for property ${fresh.propertyCode}.',
      );
      return;
    }

    final total = afterItems.length;
    final remainingAtStation = afterItems.where((x) {
      return x.status == PropertyItemStatus.pending ||
          (x.status == PropertyItemStatus.loaded && x.tripId.trim().isEmpty);
    }).length;

    fresh.routeId = route.id;
    fresh.routeName = route.name;
    fresh.status = PropertyStatus.inTransit;
    fresh.inTransitAt = now;
    fresh.loadedAt ??= now;
    fresh.tripId = trip.tripId;
    fresh.aggregateVersion += 1;
    await fresh.save();

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
        'loadedForTrip': movedCount,
        'remainingAtStation': remainingAtStation,
        'total': total,
        'aggregateVersion': fresh.aggregateVersion,
      },
    );

    final msg =
        'Departed today: $movedCount/$total\n'
        'Remaining at station: $remainingAtStation/$total\n'
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

    if (remainingAtStation > 0) {
      await _safeNotifyReceiverPartialLoad(
        fresh: fresh,
        counts: PropertyItemTripCounts(
          total: total,
          loadedForTrip: movedCount,
          remainingAtStation: remainingAtStation,
        ),
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

    property.tripId = tripId;
    if (routeId.isNotEmpty) property.routeId = routeId;
    if (routeName.isNotEmpty) property.routeName = routeName;
    property.inTransitAt ??= inTransitAt;
    property.loadedAt ??= inTransitAt;
    property.aggregateVersion = incomingVersion;

    await property.save();
    await itemSvc.recomputePropertyAggregate(property: property);
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

  static Future<Trip?> startRouteTrip({required String routeId}) async {
    final currentRole = Session.currentRole;
    if (currentRole != UserRole.driver && currentRole != UserRole.admin) {
      return null;
    }

    final route = findRouteById(routeId);
    if (route == null) throw StateError('Route not found');

    final cps = validatedCheckpoints(route);
    if (cps.isEmpty) throw StateError('Route has invalid checkpoints');

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
      return p.status == PropertyStatus.pending ||
          p.status == PropertyStatus.loaded;
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

      if (counts.loadedForTrip <= 0) continue;

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
            details: 'Receiver phone not message-ready. raw="$rawPhone".',
          );
        } catch (_) {}
        try {
          await NotificationService.notify(
            targetUserId: NotificationService.adminInbox,
            title: 'OTP not sent (invalid phone)',
            message:
                'Property for ${fresh.receiverName}: receiver phone is not message-ready.\n'
                'Phone entered: "$rawPhone"',
          );
        } catch (_) {}
        try {
          if (fresh.createdByUserId.trim().isNotEmpty) {
            await NotificationService.notify(
              targetUserId: fresh.createdByUserId,
              title: 'OTP not sent (check receiver phone)',
              message:
                  'Receiver phone for ${fresh.receiverName} is not message-ready.\n'
                  'Phone entered: "$rawPhone"',
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

      final queuedMsg = await OutboundMessageService.queue(
        toPhone: phone,
        channel: 'sms',
        body: body,
        propertyKey: pKey,
      );

      await OutboundMessageService.logDeliveryAttempt(
        msg: queuedMsg,
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

  static String _propertyCodeLabel(Property p) {
    final c = p.propertyCode.trim();
    return c.isEmpty ? p.key.toString() : c;
  }

  static String _otpMessage(Property p, String otpPlaintext) {
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
      'OTP: ${otpPlaintext.isEmpty ? '—' : otpPlaintext}',
      'Instruction: Show this OTP at the pickup desk to receive your cargo.',
      if (untilText.isNotEmpty) untilText,
    ].join('\n');
  }

  static Future<String?> sendPickupOtpViaWhatsApp(
    Property p, {
    required String otpPlaintext,
  }) async {
    if (!RoleGuard.hasAnyVerified({UserRole.staff, UserRole.admin})) {
      return 'Not authorized.';
    }

    final fresh = HiveService.propertyBox().get(p.key) ?? p;
    await repairMissingLoadedMilestone(fresh);

    if (fresh.status != PropertyStatus.delivered) {
      return 'Property is not in Delivered state.';
    }
    if (otpPlaintext.trim().isEmpty) {
      return 'OTP not available. Ask admin to reset OTP to get a fresh one.';
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
      message: _otpMessage(fresh, otpPlaintext),
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

/// Result enum for [PropertyService.confirmPickupWithOtpAndPhone].
enum PickupResult {
  success,
  notAuthorized,
  notDelivered,
  otpMissing,
  otpLocked,
  otpExpired,
  otpWrong,
  phoneMismatch,
  noItems,
}

extension PickupResultMessage on PickupResult {
  String get message {
    switch (this) {
      case PickupResult.success:
        return 'Pickup confirmed ✅';
      case PickupResult.notAuthorized:
        return 'Not authorized ❌';
      case PickupResult.notDelivered:
        return 'Property is not in Delivered state ❌';
      case PickupResult.otpMissing:
        return 'OTP missing — ask admin to reset ❌';
      case PickupResult.otpLocked:
        return 'Too many attempts — OTP locked ❌';
      case PickupResult.otpExpired:
        return 'OTP expired — ask admin to reset ❌';
      case PickupResult.otpWrong:
        return 'Wrong OTP ❌';
      case PickupResult.phoneMismatch:
        return 'Phone number does not match receiver records ❌';
      case PickupResult.noItems:
        return 'No delivered items found ❌';
    }
  }
}
