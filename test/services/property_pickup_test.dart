import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/models/audit_event.dart';
import 'package:bus_cargo_tracker/models/notification_item.dart';
import 'package:bus_cargo_tracker/models/property.dart';
import 'package:bus_cargo_tracker/models/property_item.dart';
import 'package:bus_cargo_tracker/models/property_item_status.dart';
import 'package:bus_cargo_tracker/models/property_status.dart';
import 'package:bus_cargo_tracker/models/sync_event.dart';
import 'package:bus_cargo_tracker/models/sync_event_type.dart';
import 'package:bus_cargo_tracker/models/user.dart';
import 'package:bus_cargo_tracker/models/user_role.dart';
import 'package:bus_cargo_tracker/services/hive_service.dart';
import 'package:bus_cargo_tracker/services/property_service.dart';
import 'package:bus_cargo_tracker/services/session.dart';

// S4: mirror PropertyService._hashOtp so tests can pre-hash OTPs before
// storing them on Property fixtures, matching the real service behaviour.
String _hashOtp(String otp, String propertyCode) {
  final salted = '$propertyCode:$otp';
  return sha256.convert(utf8.encode(salted)).toString();
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(PropertyStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(PropertyAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(PropertyItemStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(PropertyItemAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(NotificationItemAdapter());
    }
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(AuditEventAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(SyncEventTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(17)) {
      Hive.registerAdapter(SyncEventAdapter());
    }
    // S7: UserAdapter needed for hasAnyVerified
    if (!Hive.isAdapterRegistered(UserAdapter().typeId)) {
      Hive.registerAdapter(UserAdapter());
    }
    if (!Hive.isAdapterRegistered(UserRoleAdapter().typeId)) {
      Hive.registerAdapter(UserRoleAdapter());
    }
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_property_pickup_test_',
    );

    Hive.init(tempDir.path);

    await HiveService.openPropertyBox();
    await HiveService.openPropertyItemBox();
    await HiveService.openAuditBox();
    await HiveService.openNotificationBox();
    await HiveService.openSyncEventBox();
    await HiveService.openAppSettingsBox();
    // S7: open user box so hasAnyVerified can look up the actor
    await HiveService.openUserBox();

    // S7: insert a staff user into Hive so hasAnyVerified passes
    const actorId = 'staff-1';
    final actor = User(
      id: actorId,
      fullName: 'Station Staff Tester',
      phone: '0700000099',
      passwordHash: 'test-hash',
      role: UserRole.staff,
      createdAt: DateTime.now(),
    );
    await HiveService.userBox().put(actorId, actor);

    Session.currentUserId = actorId;
    Session.currentRole = UserRole.staff;
    Session.currentUserFullName = 'Station Staff Tester';
    Session.currentStationName = 'Juba';
  });

  tearDown(() async {
    Session.currentUserId = null;
    Session.currentRole = null;
    Session.currentUserFullName = null;
    Session.currentStationName = null;
    Session.currentAssignedRouteId = null;
    Session.currentAssignedRouteName = null;

    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PropertyService.confirmPickupWithOtp', () {
    test('marks delivered property as pickedUp when OTP is correct', () async {
      final now = DateTime.now();
      const propertyCode = 'P-PICKUP-001';
      const otpPlaintext = '123456';

      final property = Property(
        receiverName: 'Receiver One',
        receiverPhone: '0700000000',
        description: 'Box',
        destination: 'Juba',
        itemCount: 1,
        createdAt: now.subtract(const Duration(days: 1)),
        status: PropertyStatus.delivered,
        createdByUserId: 'sender-1',
        propertyCode: propertyCode,
        trackingCode: 'BC-PICK-001',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        tripId: 'TRIP-PICK-001',
        inTransitAt: now.subtract(const Duration(hours: 5)),
        deliveredAt: now.subtract(const Duration(hours: 1)),
        loadedAt: now.subtract(const Duration(hours: 6)),
        loadedAtStation: 'Kampala',
        loadedByUserId: 'desk-1',
        // S4: store hash, not plaintext
        pickupOtp: _hashOtp(otpPlaintext, propertyCode),
        otpGeneratedAt: now.subtract(const Duration(minutes: 10)),
        otpAttempts: 0,
        otpLockedUntil: null,
        qrIssuedAt: now.subtract(const Duration(minutes: 10)),
        qrNonce: 'nonce-1',
        qrConsumedAt: null,
        aggregateVersion: 5,
      );

      final key = await HiveService.propertyBox().add(property);
      final propertyKey = key.toString();

      await HiveService.propertyItemBox().put(
        '$propertyKey#1',
        PropertyItem(
          itemKey: '$propertyKey#1',
          propertyKey: propertyKey,
          itemNo: 1,
          status: PropertyItemStatus.delivered,
          tripId: 'TRIP-PICK-001',
          labelCode: 'BC-PICK-001|1',
          deliveredAt: now.subtract(const Duration(hours: 1)),
        ),
      );

      final saved = HiveService.propertyBox().get(key)!;

      // Pass plaintext — service hashes it internally to compare
      final ok = await PropertyService.confirmPickupWithOtp(
        saved,
        otpPlaintext,
      );

      final refreshed = HiveService.propertyBox().get(key)!;
      final item = HiveService.propertyItemBox().get('$propertyKey#1')!;

      expect(ok, isTrue);
      expect(refreshed.status, PropertyStatus.pickedUp);
      expect(refreshed.pickedUpAt, isNotNull);
      expect(refreshed.staffPickupConfirmed, isTrue);
      expect(refreshed.receiverPickupConfirmed, isTrue);
      expect(refreshed.pickupOtp, isNull);
      expect(refreshed.otpGeneratedAt, isNull);
      expect(refreshed.otpAttempts, 0);
      expect(refreshed.otpLockedUntil, isNull);
      expect(refreshed.qrConsumedAt, isNotNull);
      expect(refreshed.deliveredAt, isNotNull);
      expect(refreshed.inTransitAt, isNotNull);
      expect(refreshed.loadedAt, isNotNull);
      expect(refreshed.aggregateVersion, 6);

      expect(item.status, PropertyItemStatus.pickedUp);
      expect(item.pickedUpAt, isNotNull);
    });

    test('fails when OTP is incorrect and increments attempts', () async {
      final now = DateTime.now();
      const propertyCode = 'P-PICKUP-002';
      const otpPlaintext = '654321';

      final property = Property(
        receiverName: 'Receiver Two',
        receiverPhone: '0700000001',
        description: 'Bag',
        destination: 'Juba',
        itemCount: 1,
        createdAt: now.subtract(const Duration(days: 1)),
        status: PropertyStatus.delivered,
        createdByUserId: 'sender-2',
        propertyCode: propertyCode,
        trackingCode: 'BC-PICK-002',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        deliveredAt: now.subtract(const Duration(hours: 1)),
        loadedAt: now.subtract(const Duration(hours: 6)),
        // S4: store hash, not plaintext
        pickupOtp: _hashOtp(otpPlaintext, propertyCode),
        otpGeneratedAt: now.subtract(const Duration(minutes: 15)),
        otpAttempts: 0,
        aggregateVersion: 3,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      // Pass wrong OTP — should fail and increment attempts
      final ok = await PropertyService.confirmPickupWithOtp(saved, '111111');

      final refreshed = HiveService.propertyBox().get(key)!;

      expect(ok, isFalse);
      expect(refreshed.status, PropertyStatus.delivered);
      expect(refreshed.pickedUpAt, isNull);
      expect(refreshed.otpAttempts, 1);
      // Hash is still stored — not cleared on failure
      expect(refreshed.pickupOtp, isNotNull);
      expect(refreshed.pickupOtp!.trim().isNotEmpty, isTrue);
    });

    test('locks OTP after too many failed attempts', () async {
      final now = DateTime.now();
      const propertyCode = 'P-PICKUP-003';
      const otpPlaintext = '222333';

      final property = Property(
        receiverName: 'Receiver Three',
        receiverPhone: '0700000002',
        description: 'Parcel',
        destination: 'Juba',
        itemCount: 1,
        createdAt: now.subtract(const Duration(days: 1)),
        status: PropertyStatus.delivered,
        createdByUserId: 'sender-3',
        propertyCode: propertyCode,
        trackingCode: 'BC-PICK-003',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        deliveredAt: now.subtract(const Duration(hours: 1)),
        loadedAt: now.subtract(const Duration(hours: 6)),
        // S4: store hash, not plaintext
        pickupOtp: _hashOtp(otpPlaintext, propertyCode),
        otpGeneratedAt: now.subtract(const Duration(minutes: 20)),
        otpAttempts: 2, // one more wrong attempt will trigger lockout
        aggregateVersion: 4,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      final ok = await PropertyService.confirmPickupWithOtp(saved, '999999');

      final refreshed = HiveService.propertyBox().get(key)!;

      expect(ok, isFalse);
      expect(refreshed.status, PropertyStatus.delivered);
      expect(refreshed.otpAttempts, 3);
      expect(refreshed.otpLockedUntil, isNotNull);
    });

    test('fails when OTP is expired', () async {
      final now = DateTime.now();
      const propertyCode = 'P-PICKUP-004';
      const otpPlaintext = '444555';

      final property = Property(
        receiverName: 'Receiver Four',
        receiverPhone: '0700000003',
        description: 'Goods',
        destination: 'Juba',
        itemCount: 1,
        createdAt: now.subtract(const Duration(days: 1)),
        status: PropertyStatus.delivered,
        createdByUserId: 'sender-4',
        propertyCode: propertyCode,
        trackingCode: 'BC-PICK-004',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        deliveredAt: now.subtract(const Duration(hours: 2)),
        loadedAt: now.subtract(const Duration(hours: 7)),
        // S4: store hash, not plaintext
        pickupOtp: _hashOtp(otpPlaintext, propertyCode),
        // OTP generated 13 hours ago — exceeds 12h TTL
        otpGeneratedAt: now.subtract(const Duration(hours: 13)),
        otpAttempts: 0,
        aggregateVersion: 2,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      // Even the correct plaintext should fail because OTP is expired
      final ok = await PropertyService.confirmPickupWithOtp(
        saved,
        otpPlaintext,
      );

      final refreshed = HiveService.propertyBox().get(key)!;

      expect(ok, isFalse);
      expect(refreshed.status, PropertyStatus.delivered);
      expect(refreshed.pickedUpAt, isNull);
      expect(refreshed.pickupOtp, isNotNull);
    });

    test('fails when OTP is currently locked', () async {
      final now = DateTime.now();
      const propertyCode = 'P-PICKUP-005';
      const otpPlaintext = '777888';

      final property = Property(
        receiverName: 'Receiver Five',
        receiverPhone: '0700000004',
        description: 'Cargo',
        destination: 'Juba',
        itemCount: 1,
        createdAt: now.subtract(const Duration(days: 1)),
        status: PropertyStatus.delivered,
        createdByUserId: 'sender-5',
        propertyCode: propertyCode,
        trackingCode: 'BC-PICK-005',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        deliveredAt: now.subtract(const Duration(hours: 1)),
        loadedAt: now.subtract(const Duration(hours: 6)),
        // S4: store hash, not plaintext
        pickupOtp: _hashOtp(otpPlaintext, propertyCode),
        otpGeneratedAt: now.subtract(const Duration(minutes: 10)),
        otpAttempts: 3,
        otpLockedUntil: now.add(const Duration(minutes: 5)),
        aggregateVersion: 6,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      // Even the correct plaintext should fail because OTP is locked
      final ok = await PropertyService.confirmPickupWithOtp(
        saved,
        otpPlaintext,
      );

      final refreshed = HiveService.propertyBox().get(key)!;

      expect(ok, isFalse);
      expect(refreshed.status, PropertyStatus.delivered);
      expect(refreshed.pickedUpAt, isNull);
      expect(refreshed.pickupOtp, isNotNull);
      expect(refreshed.otpLockedUntil, isNotNull);
    });

    test('fails when property is not delivered', () async {
      const propertyCode = 'P-PICKUP-006';
      const otpPlaintext = '112233';

      final property = Property(
        receiverName: 'Receiver Six',
        receiverPhone: '0700000005',
        description: 'Envelope',
        destination: 'Juba',
        itemCount: 1,
        createdAt: DateTime.now(),
        status: PropertyStatus.inTransit,
        createdByUserId: 'sender-6',
        propertyCode: propertyCode,
        trackingCode: 'BC-PICK-006',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        // S4: store hash, not plaintext
        pickupOtp: _hashOtp(otpPlaintext, propertyCode),
        otpGeneratedAt: DateTime.now(),
        aggregateVersion: 1,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      final ok = await PropertyService.confirmPickupWithOtp(
        saved,
        otpPlaintext,
      );

      final refreshed = HiveService.propertyBox().get(key)!;

      expect(ok, isFalse);
      expect(refreshed.status, PropertyStatus.inTransit);
      expect(refreshed.pickedUpAt, isNull);
    });

    test('emits propertyPickedUp sync event on successful pickup', () async {
      final now = DateTime.now();
      const propertyCode = 'P-PICKUP-007';
      const otpPlaintext = '999111';

      final property = Property(
        receiverName: 'Receiver Seven',
        receiverPhone: '0700000006',
        description: 'Crate',
        destination: 'Juba',
        itemCount: 1,
        createdAt: now.subtract(const Duration(days: 1)),
        status: PropertyStatus.delivered,
        createdByUserId: 'sender-7',
        propertyCode: propertyCode,
        trackingCode: 'BC-PICK-007',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        tripId: 'TRIP-PICK-007',
        inTransitAt: now.subtract(const Duration(hours: 5)),
        deliveredAt: now.subtract(const Duration(hours: 1)),
        loadedAt: now.subtract(const Duration(hours: 6)),
        // S4: store hash, not plaintext
        pickupOtp: _hashOtp(otpPlaintext, propertyCode),
        otpGeneratedAt: now.subtract(const Duration(minutes: 5)),
        aggregateVersion: 8,
      );

      final key = await HiveService.propertyBox().add(property);
      final propertyKey = key.toString();

      await HiveService.propertyItemBox().put(
        '$propertyKey#1',
        PropertyItem(
          itemKey: '$propertyKey#1',
          propertyKey: propertyKey,
          itemNo: 1,
          status: PropertyItemStatus.delivered,
          tripId: 'TRIP-PICK-007',
          labelCode: 'BC-PICK-007|1',
          deliveredAt: now.subtract(const Duration(hours: 1)),
        ),
      );

      final saved = HiveService.propertyBox().get(key)!;

      final ok = await PropertyService.confirmPickupWithOtp(
        saved,
        otpPlaintext,
      );

      final refreshed = HiveService.propertyBox().get(key)!;
      final events = HiveService.syncEventBox().values.toList();

      final pickedUpEvents = events
          .where((e) => e.type == SyncEventType.propertyPickedUp)
          .toList();

      expect(ok, isTrue);
      expect(pickedUpEvents.length, 1);

      final event = pickedUpEvents.first;
      expect(event.aggregateType, 'property');
      expect(event.aggregateId, refreshed.propertyCode);
      expect(event.payload['propertyCode'], refreshed.propertyCode);
      expect(event.payload['aggregateVersion'], refreshed.aggregateVersion);
      expect(event.payload['pickedUpAt'], isNotNull);
    });
  });
}
