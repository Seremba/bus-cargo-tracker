import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/models/audit_event.dart';
import 'package:bus_cargo_tracker/models/notification_item.dart';
import 'package:bus_cargo_tracker/models/outbound_message.dart';
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
    if (!Hive.isAdapterRegistered(19)) {
      Hive.registerAdapter(OutboundMessageAdapter());
    }
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_property_delivered_test_',
    );

    Hive.init(tempDir.path);

    await HiveService.openPropertyBox();
    await HiveService.openAuditBox();
    await HiveService.openNotificationBox();
    await HiveService.openSyncEventBox();
    await HiveService.openOutboundMessageBox();
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

  group('PropertyService.markDelivered', () {
    test('marks inTransit property as delivered and generates pickup OTP', () async {
      final property = Property(
        receiverName: 'Receiver One',
        receiverPhone: '0700000000',
        description: 'Box',
        destination: 'Juba',
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.inTransit,
        createdByUserId: 'sender-1',
        propertyCode: 'P-DELIVERED-001',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        inTransitAt: DateTime.now().subtract(const Duration(hours: 2)),
        loadedAt: DateTime.now().subtract(const Duration(hours: 3)),
        loadedAtStation: 'Kampala',
        loadedByUserId: 'desk-1',
        aggregateVersion: 2,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      await PropertyService.markDelivered(saved);

      final refreshed = HiveService.propertyBox().get(key)!;

      expect(refreshed.status, PropertyStatus.delivered);
      expect(refreshed.deliveredAt, isNotNull);
      expect(refreshed.pickupOtp, isNotNull);
      expect(refreshed.pickupOtp!.trim().length, 6);
      expect(refreshed.otpGeneratedAt, isNotNull);
      expect(refreshed.otpAttempts, 0);
      expect(refreshed.otpLockedUntil, isNull);
      expect(refreshed.aggregateVersion, 3);
    });

    test('does nothing if property is not inTransit', () async {
      final property = Property(
        receiverName: 'Receiver Two',
        receiverPhone: '0700000001',
        description: 'Bag',
        destination: 'Juba',
        itemCount: 1,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-2',
        propertyCode: 'P-DELIVERED-002',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        aggregateVersion: 1,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      await PropertyService.markDelivered(saved);

      final refreshed = HiveService.propertyBox().get(key)!;

      expect(refreshed.status, PropertyStatus.pending);
      expect(refreshed.deliveredAt, isNull);
      expect(refreshed.pickupOtp, isNull);
      expect(refreshed.aggregateVersion, 1);
      expect(HiveService.syncEventBox().isEmpty, isTrue);
    });

    test('repairs missing loaded milestone during delivery', () async {
      final inTransitAt = DateTime.now().subtract(const Duration(hours: 1));

      final property = Property(
        receiverName: 'Receiver Three',
        receiverPhone: '0700000002',
        description: 'Parcel',
        destination: 'Juba',
        itemCount: 1,
        createdAt: DateTime.now(),
        status: PropertyStatus.inTransit,
        createdByUserId: 'sender-3',
        propertyCode: 'P-DELIVERED-003',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        inTransitAt: inTransitAt,
        loadedAt: null,
        loadedAtStation: '',
        loadedByUserId: '',
        aggregateVersion: 4,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      await PropertyService.markDelivered(saved);

      final refreshed = HiveService.propertyBox().get(key)!;

      expect(refreshed.status, PropertyStatus.delivered);
      expect(refreshed.loadedAt, isNotNull);
      expect(refreshed.loadedByUserId.trim().isNotEmpty, isTrue);
    });

    test('emits propertyDelivered sync event', () async {
      final property = Property(
        receiverName: 'Receiver Four',
        receiverPhone: '0700000003',
        description: 'Goods',
        destination: 'Juba',
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.inTransit,
        createdByUserId: 'sender-4',
        propertyCode: 'P-DELIVERED-004',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        inTransitAt: DateTime.now().subtract(const Duration(hours: 2)),
        loadedAt: DateTime.now().subtract(const Duration(hours: 3)),
        loadedAtStation: 'Kampala',
        loadedByUserId: 'desk-2',
        aggregateVersion: 7,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      await PropertyService.markDelivered(saved);

      final refreshed = HiveService.propertyBox().get(key)!;
      final events = HiveService.syncEventBox().values.toList();

      final deliveredEvents = events
          .where((e) => e.type == SyncEventType.propertyDelivered)
          .toList();

      expect(deliveredEvents.length, 1);

      final event = deliveredEvents.first;
      expect(event.aggregateType, 'property');
      expect(event.aggregateId, refreshed.propertyCode);
      expect(event.payload['propertyCode'], refreshed.propertyCode);
      expect(event.payload['aggregateVersion'], refreshed.aggregateVersion);
      expect(event.payload['deliveredAt'], isNotNull);
    });

    test('queues SMS OTP when receiver notifications are enabled for sms', () async {
      final property = Property(
        receiverName: 'Receiver Five',
        receiverPhone: '0700000004',
        description: 'Cargo',
        destination: 'Juba',
        itemCount: 1,
        createdAt: DateTime.now(),
        status: PropertyStatus.inTransit,
        createdByUserId: 'sender-5',
        propertyCode: 'P-DELIVERED-005',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        inTransitAt: DateTime.now().subtract(const Duration(hours: 2)),
        loadedAt: DateTime.now().subtract(const Duration(hours: 3)),
        loadedAtStation: 'Kampala',
        loadedByUserId: 'desk-3',
        notifyReceiver: true,
        receiverNotifyChannel: 'sms',
        trackingCode: 'BC-TRACK-001',
        aggregateVersion: 2,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      await PropertyService.markDelivered(saved);

      final refreshed = HiveService.propertyBox().get(key)!;
      final outbound = HiveService.outboundMessageBox().values.toList();

      expect(refreshed.status, PropertyStatus.delivered);
      expect(refreshed.pickupOtp, isNotNull);
      expect(outbound.isNotEmpty, isTrue);

      final sms = outbound.first;
      expect(sms.channel.toLowerCase(), 'sms');
      expect(sms.body.contains(refreshed.pickupOtp!), isTrue);
    });
  });
}