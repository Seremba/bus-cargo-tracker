import 'dart:io';  
  
import 'package:flutter_test/flutter_test.dart';  
import 'package:hive/hive.dart';  
  
import 'package:bus_cargo_tracker/models/audit_event.dart';  
import 'package:bus_cargo_tracker/models/notification_item.dart';  
import 'package:bus_cargo_tracker/models/property.dart';  
import 'package:bus_cargo_tracker/models/property_status.dart';  
import 'package:bus_cargo_tracker/models/sync_event.dart';  
import 'package:bus_cargo_tracker/models/sync_event_type.dart';  
import 'package:bus_cargo_tracker/models/user_role.dart';  
import 'package:bus_cargo_tracker/services/hive_service.dart';  
import 'package:bus_cargo_tracker/services/property_service.dart';  
import 'package:bus_cargo_tracker/services/session.dart';  
  
void main() {  
  late Directory tempDir;  
  
  setUpAll(() {  
    if (!Hive.isAdapterRegistered(4)) {  
      Hive.registerAdapter(PropertyStatusAdapter());  
    }  
    if (!Hive.isAdapterRegistered(5)) {  
      Hive.registerAdapter(PropertyAdapter());  
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
  });  
  
  setUp(() async {  
    tempDir = await Directory.systemTemp.createTemp(  
      'bebeto_property_pickup_test_',  
    );  
  
    Hive.init(tempDir.path);  
  
    await HiveService.openPropertyBox();  
    await HiveService.openAuditBox();  
    await HiveService.openNotificationBox();  
    await HiveService.openSyncEventBox();  
    await HiveService.openAppSettingsBox();  
  
    Session.currentUserId = 'staff-1';  
    Session.currentRole = UserRole.staff;  
    Session.currentUserFullName = 'Station Staff Tester';  
    Session.currentStationName = 'Juba';  
  });  
  
  tearDown(() async {  
    Session.currentUserId = null;  
    Session.currentRole = null;  
    Session.currentUserFullName = null;  
    Session.currentStationName = null;  
  
    await Hive.close();  
    if (await tempDir.exists()) {  
      await tempDir.delete(recursive: true);  
    }  
  });  
  
  group('PropertyService.confirmPickupWithOtp', () {  
    test('marks delivered property as pickedUp when OTP is correct', () async {  
      final now = DateTime.now();  
  
      final property = Property(  
        receiverName: 'Receiver One',  
        receiverPhone: '0700000000',  
        description: 'Box',  
        destination: 'Juba',  
        itemCount: 1,  
        createdAt: now.subtract(const Duration(days: 1)),  
        status: PropertyStatus.delivered,  
        createdByUserId: 'sender-1',  
        propertyCode: 'P-PICKUP-001',  
        routeId: 'kla_juba',  
        routeName: 'Kampala → Juba',  
        routeConfirmed: true,  
        inTransitAt: now.subtract(const Duration(hours: 5)),  
        deliveredAt: now.subtract(const Duration(hours: 1)),  
        loadedAt: now.subtract(const Duration(hours: 6)),  
        loadedAtStation: 'Kampala',  
        loadedByUserId: 'desk-1',  
        pickupOtp: '123456',  
        otpGeneratedAt: now.subtract(const Duration(minutes: 10)),  
        otpAttempts: 0,  
        otpLockedUntil: null,  
        qrIssuedAt: now.subtract(const Duration(minutes: 10)),  
        qrNonce: 'nonce-1',  
        qrConsumedAt: null,  
        aggregateVersion: 5,  
      );  
  
      final key = await HiveService.propertyBox().add(property);  
      final saved = HiveService.propertyBox().get(key)!;  
  
      final ok = await PropertyService.confirmPickupWithOtp(  
        saved,  
        '123456',  
      );  
  
      final refreshed = HiveService.propertyBox().get(key)!;  
  
      expect(ok, isTrue);  
      expect(refreshed.status, PropertyStatus.pickedUp);  
      expect(refreshed.pickedUpAt, isNotNull);  
      expect(refreshed.staffPickupConfirmed, isTrue);  
      expect(refreshed.pickupOtp, isNull);  
      expect(refreshed.otpGeneratedAt, isNull);  
      expect(refreshed.otpAttempts, 0);  
      expect(refreshed.otpLockedUntil, isNull);  
      expect(refreshed.qrConsumedAt, isNotNull);  
      expect(refreshed.deliveredAt, isNotNull);  
      expect(refreshed.inTransitAt, isNotNull);  
      expect(refreshed.loadedAt, isNotNull);  
    });  
  
    test('fails when OTP is incorrect and increments attempts', () async {  
      final now = DateTime.now();  
  
      final property = Property(  
        receiverName: 'Receiver Two',  
        receiverPhone: '0700000001',  
        description: 'Bag',  
        destination: 'Juba',  
        itemCount: 1,  
        createdAt: now.subtract(const Duration(days: 1)),  
        status: PropertyStatus.delivered,  
        createdByUserId: 'sender-2',  
        propertyCode: 'P-PICKUP-002',  
        routeId: 'kla_juba',  
        routeName: 'Kampala → Juba',  
        routeConfirmed: true,  
        deliveredAt: now.subtract(const Duration(hours: 1)),  
        loadedAt: now.subtract(const Duration(hours: 6)),  
        pickupOtp: '654321',  
        otpGeneratedAt: now.subtract(const Duration(minutes: 15)),  
        otpAttempts: 0,  
        aggregateVersion: 3,  
      );  
  
      final key = await HiveService.propertyBox().add(property);  
      final saved = HiveService.propertyBox().get(key)!;  
  
      final ok = await PropertyService.confirmPickupWithOtp(  
        saved,  
        '111111',  
      );  
  
      final refreshed = HiveService.propertyBox().get(key)!;  
  
      expect(ok, isFalse);  
      expect(refreshed.status, PropertyStatus.delivered);  
      expect(refreshed.pickedUpAt, isNull);  
      expect(refreshed.otpAttempts, 1);  
      expect(refreshed.pickupOtp, '654321');  
    });  
  
    test('locks OTP after too many failed attempts', () async {  
      final now = DateTime.now();  
  
      final property = Property(  
        receiverName: 'Receiver Three',  
        receiverPhone: '0700000002',  
        description: 'Parcel',  
        destination: 'Juba',  
        itemCount: 1,  
        createdAt: now.subtract(const Duration(days: 1)),  
        status: PropertyStatus.delivered,  
        createdByUserId: 'sender-3',  
        propertyCode: 'P-PICKUP-003',  
        routeId: 'kla_juba',  
        routeName: 'Kampala → Juba',  
        routeConfirmed: true,  
        deliveredAt: now.subtract(const Duration(hours: 1)),  
        loadedAt: now.subtract(const Duration(hours: 6)),  
        pickupOtp: '222333',  
        otpGeneratedAt: now.subtract(const Duration(minutes: 20)),  
        otpAttempts: 2,  
        aggregateVersion: 4,  
      );  
  
      final key = await HiveService.propertyBox().add(property);  
      final saved = HiveService.propertyBox().get(key)!;  
  
      final ok = await PropertyService.confirmPickupWithOtp(  
        saved,  
        '999999',  
      );  
  
      final refreshed = HiveService.propertyBox().get(key)!;  
  
      expect(ok, isFalse);  
      expect(refreshed.status, PropertyStatus.delivered);  
      expect(refreshed.otpAttempts, 3);  
      expect(refreshed.otpLockedUntil, isNotNull);  
    });  
  
    test('fails when OTP is expired', () async {  
      final now = DateTime.now();  
  
      final property = Property(  
        receiverName: 'Receiver Four',  
        receiverPhone: '0700000003',  
        description: 'Goods',  
        destination: 'Juba',  
        itemCount: 1,  
        createdAt: now.subtract(const Duration(days: 1)),  
        status: PropertyStatus.delivered,  
        createdByUserId: 'sender-4',  
        propertyCode: 'P-PICKUP-004',  
        routeId: 'kla_juba',  
        routeName: 'Kampala → Juba',  
        routeConfirmed: true,  
        deliveredAt: now.subtract(const Duration(hours: 2)),  
        loadedAt: now.subtract(const Duration(hours: 7)),  
        pickupOtp: '444555',  
        otpGeneratedAt: now.subtract(const Duration(hours: 13)),  
        otpAttempts: 0,  
        aggregateVersion: 2,  
      );  
  
      final key = await HiveService.propertyBox().add(property);  
      final saved = HiveService.propertyBox().get(key)!;  
  
      final ok = await PropertyService.confirmPickupWithOtp(  
        saved,  
        '444555',  
      );  
  
      final refreshed = HiveService.propertyBox().get(key)!;  
  
      expect(ok, isFalse);  
      expect(refreshed.status, PropertyStatus.delivered);  
      expect(refreshed.pickedUpAt, isNull);  
      expect(refreshed.pickupOtp, '444555');  
    });  
  
    test('fails when OTP is currently locked', () async {  
      final now = DateTime.now();  
  
      final property = Property(  
        receiverName: 'Receiver Five',  
        receiverPhone: '0700000004',  
        description: 'Cargo',  
        destination: 'Juba',  
        itemCount: 1,  
        createdAt: now.subtract(const Duration(days: 1)),  
        status: PropertyStatus.delivered,  
        createdByUserId: 'sender-5',  
        propertyCode: 'P-PICKUP-005',  
        routeId: 'kla_juba',  
        routeName: 'Kampala → Juba',  
        routeConfirmed: true,  
        deliveredAt: now.subtract(const Duration(hours: 1)),  
        loadedAt: now.subtract(const Duration(hours: 6)),  
        pickupOtp: '777888',  
        otpGeneratedAt: now.subtract(const Duration(minutes: 10)),  
        otpAttempts: 3,  
        otpLockedUntil: now.add(const Duration(minutes: 5)),  
        aggregateVersion: 6,  
      );  
  
      final key = await HiveService.propertyBox().add(property);  
      final saved = HiveService.propertyBox().get(key)!;  
  
      final ok = await PropertyService.confirmPickupWithOtp(  
        saved,  
        '777888',  
      );  
  
      final refreshed = HiveService.propertyBox().get(key)!;  
  
      expect(ok, isFalse);  
      expect(refreshed.status, PropertyStatus.delivered);  
      expect(refreshed.pickedUpAt, isNull);  
      expect(refreshed.pickupOtp, '777888');  
      expect(refreshed.otpLockedUntil, isNotNull);  
    });  
  
    test('fails when property is not delivered', () async {  
      final property = Property(  
        receiverName: 'Receiver Six',  
        receiverPhone: '0700000005',  
        description: 'Envelope',  
        destination: 'Juba',  
        itemCount: 1,  
        createdAt: DateTime.now(),  
        status: PropertyStatus.inTransit,  
        createdByUserId: 'sender-6',  
        propertyCode: 'P-PICKUP-006',  
        routeId: 'kla_juba',  
        routeName: 'Kampala → Juba',  
        routeConfirmed: true,  
        pickupOtp: '112233',  
        otpGeneratedAt: DateTime.now(),  
        aggregateVersion: 1,  
      );  
  
      final key = await HiveService.propertyBox().add(property);  
      final saved = HiveService.propertyBox().get(key)!;  
  
      final ok = await PropertyService.confirmPickupWithOtp(  
        saved,  
        '112233',  
      );  
  
      final refreshed = HiveService.propertyBox().get(key)!;  
  
      expect(ok, isFalse);  
      expect(refreshed.status, PropertyStatus.inTransit);  
      expect(refreshed.pickedUpAt, isNull);  
    });  
  });  
}