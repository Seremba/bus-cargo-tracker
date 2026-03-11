import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/models/audit_event.dart';
import 'package:bus_cargo_tracker/models/checkpoint.dart';
import 'package:bus_cargo_tracker/models/notification_item.dart';
import 'package:bus_cargo_tracker/models/property.dart';
import 'package:bus_cargo_tracker/models/property_item.dart';
import 'package:bus_cargo_tracker/models/property_item_status.dart';
import 'package:bus_cargo_tracker/models/property_status.dart';
import 'package:bus_cargo_tracker/models/sync_event.dart';
import 'package:bus_cargo_tracker/models/sync_event_type.dart';
import 'package:bus_cargo_tracker/models/trip.dart';
import 'package:bus_cargo_tracker/models/trip_status.dart';
import 'package:bus_cargo_tracker/models/user_role.dart';
import 'package:bus_cargo_tracker/services/hive_service.dart';
import 'package:bus_cargo_tracker/services/property_service.dart';
import 'package:bus_cargo_tracker/services/property_item_service.dart';
import 'package:bus_cargo_tracker/services/session.dart';
import 'package:bus_cargo_tracker/services/trip_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(CheckpointAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(PropertyStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(PropertyAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(TripAdapter());
    }
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(TripStatusAdapter());
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
    if (!Hive.isAdapterRegistered(65)) {
      Hive.registerAdapter(PropertyItemAdapter());
    }
    if (!Hive.isAdapterRegistered(66)) {
      Hive.registerAdapter(PropertyItemStatusAdapter());
    }
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_property_in_transit_test_',
    );

    Hive.init(tempDir.path);

    await HiveService.openPropertyBox();
    await HiveService.openPropertyItemBox();
    await HiveService.openTripBox();
    await HiveService.openSyncEventBox();
    await HiveService.openAppSettingsBox();
    await HiveService.openAuditBox();
    await HiveService.openNotificationBox();

    Session.currentUserId = 'driver-1';
    Session.currentRole = UserRole.driver;
    Session.currentUserFullName = 'Driver Tester';
    Session.currentStationName = 'Kampala';
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

  group('PropertyService.markInTransit', () {
    test('moves loaded items to inTransit and assigns trip', () async {
      final property = Property(
        receiverName: 'Receiver One',
        receiverPhone: '0700000000',
        description: 'Box',
        destination: 'Juba',
        itemCount: 3,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-1',
        propertyCode: 'P-TRANSIT-001',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      final itemSvc = PropertyItemService(HiveService.propertyItemBox());
      await itemSvc.ensureItemsForProperty(
        propertyKey: saved.key.toString(),
        trackingCode: saved.trackingCode,
        itemCount: saved.itemCount,
      );
      await itemSvc.markSelectedItemsLoaded(
        propertyKey: saved.key.toString(),
        itemNos: [1, 2],
        now: DateTime.now(),
      );

      await PropertyService.markInTransit(saved);

      final refreshed = HiveService.propertyBox().get(key)!;
      final items = HiveService.propertyItemBox().values
          .where((x) => x.propertyKey == refreshed.key.toString())
          .toList()
        ..sort((a, b) => a.itemNo.compareTo(b.itemNo));

      final trips = HiveService.tripBox().values.toList();
      final syncEvents = HiveService.syncEventBox().values.toList();

      expect(refreshed.status, PropertyStatus.inTransit);
      expect(refreshed.inTransitAt, isNotNull);
      expect(refreshed.tripId, isNotNull);
      expect(refreshed.tripId!.trim(), isNotEmpty);

      expect(trips.length, 1);
      expect(trips.first.routeId, 'kla_juba');
      expect(trips.first.routeName, 'Kampala → Juba');
      expect(trips.first.driverUserId, 'driver-1');
      expect(trips.first.status, TripStatus.active);

      expect(items.length, 3);
      expect(items[0].status, PropertyItemStatus.inTransit);
      expect(items[1].status, PropertyItemStatus.inTransit);
      expect(items[2].status, PropertyItemStatus.pending);

      expect(items[0].tripId, refreshed.tripId);
      expect(items[1].tripId, refreshed.tripId);
      expect(items[2].tripId, '');

      expect(
        syncEvents.any((e) => e.type == SyncEventType.tripStarted),
        isTrue,
      );
      expect(
        syncEvents.any((e) => e.type == SyncEventType.propertyInTransit),
        isTrue,
      );
    });

    test('does nothing when property is not pending', () async {
      final property = Property(
        receiverName: 'Receiver Two',
        receiverPhone: '0700000001',
        description: 'Bag',
        destination: 'Juba',
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.inTransit,
        createdByUserId: 'sender-2',
        propertyCode: 'P-TRANSIT-002',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      await PropertyService.markInTransit(saved);

      final refreshed = HiveService.propertyBox().get(key)!;

      expect(refreshed.status, PropertyStatus.inTransit);
      expect(refreshed.tripId, isNull);
      expect(HiveService.tripBox().isEmpty, isTrue);
      expect(HiveService.syncEventBox().isEmpty, isTrue);
    });

    test('does nothing when no items are loaded', () async {
      final property = Property(
        receiverName: 'Receiver Three',
        receiverPhone: '0700000002',
        description: 'Parcel',
        destination: 'Juba',
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-3',
        propertyCode: 'P-TRANSIT-003',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      final itemSvc = PropertyItemService(HiveService.propertyItemBox());
      await itemSvc.ensureItemsForProperty(
        propertyKey: saved.key.toString(),
        trackingCode: saved.trackingCode,
        itemCount: saved.itemCount,
      );

      await PropertyService.markInTransit(saved);

      final refreshed = HiveService.propertyBox().get(key)!;
      final items = HiveService.propertyItemBox().values
          .where((x) => x.propertyKey == refreshed.key.toString())
          .toList();

      expect(refreshed.status, PropertyStatus.pending);
      expect(refreshed.inTransitAt, isNull);
      expect(refreshed.tripId, isNull);

      expect(items.length, 2);
      expect(items.every((x) => x.status == PropertyItemStatus.pending), isTrue);

      expect(HiveService.tripBox().isEmpty, isTrue);
      expect(
        HiveService.syncEventBox().values
            .where((e) => e.type == SyncEventType.propertyInTransit)
            .isEmpty,
        isTrue,
      );
    });

    test('reuses existing active trip on same route', () async {
      final firstProperty = Property(
        receiverName: 'Receiver Four',
        receiverPhone: '0700000003',
        description: 'Goods',
        destination: 'Juba',
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-4',
        propertyCode: 'P-TRANSIT-004',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
      );

      final secondProperty = Property(
        receiverName: 'Receiver Five',
        receiverPhone: '0700000004',
        description: 'More goods',
        destination: 'Juba',
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-5',
        propertyCode: 'P-TRANSIT-005',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
      );

      final firstKey = await HiveService.propertyBox().add(firstProperty);
      final secondKey = await HiveService.propertyBox().add(secondProperty);

      final firstSaved = HiveService.propertyBox().get(firstKey)!;
      final secondSaved = HiveService.propertyBox().get(secondKey)!;

      final itemSvc = PropertyItemService(HiveService.propertyItemBox());

      await itemSvc.ensureItemsForProperty(
        propertyKey: firstSaved.key.toString(),
        trackingCode: firstSaved.trackingCode,
        itemCount: firstSaved.itemCount,
      );
      await itemSvc.markSelectedItemsLoaded(
        propertyKey: firstSaved.key.toString(),
        itemNos: [1, 2],
        now: DateTime.now(),
      );

      await itemSvc.ensureItemsForProperty(
        propertyKey: secondSaved.key.toString(),
        trackingCode: secondSaved.trackingCode,
        itemCount: secondSaved.itemCount,
      );
      await itemSvc.markSelectedItemsLoaded(
        propertyKey: secondSaved.key.toString(),
        itemNos: [1],
        now: DateTime.now(),
      );

      await PropertyService.markInTransit(firstSaved);
      final firstRefreshed = HiveService.propertyBox().get(firstKey)!;
      final existingTripId = firstRefreshed.tripId;

      await PropertyService.markInTransit(secondSaved);
      final secondRefreshed = HiveService.propertyBox().get(secondKey)!;

      expect(existingTripId, isNotNull);
      expect(existingTripId, isNotEmpty);
      expect(secondRefreshed.tripId, existingTripId);
      expect(HiveService.tripBox().values.length, 1);
    });

    test('emits propertyInTransit sync event with trip data', () async {
      final property = Property(
        receiverName: 'Receiver Six',
        receiverPhone: '0700000005',
        description: 'Cargo',
        destination: 'Juba',
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-6',
        propertyCode: 'P-TRANSIT-006',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        aggregateVersion: 1,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      final itemSvc = PropertyItemService(HiveService.propertyItemBox());
      await itemSvc.ensureItemsForProperty(
        propertyKey: saved.key.toString(),
        trackingCode: saved.trackingCode,
        itemCount: saved.itemCount,
      );
      await itemSvc.markSelectedItemsLoaded(
        propertyKey: saved.key.toString(),
        itemNos: [1],
        now: DateTime.now(),
      );

      await PropertyService.markInTransit(saved);

      final refreshed = HiveService.propertyBox().get(key)!;
      final events = HiveService.syncEventBox().values.toList();

      final inTransitEvents = events
          .where((e) => e.type == SyncEventType.propertyInTransit)
          .toList();

      expect(inTransitEvents.length, 1);

      final event = inTransitEvents.first;
      expect(event.aggregateType, 'property');
      expect(event.aggregateId, refreshed.propertyCode);
      expect(event.payload['propertyCode'], refreshed.propertyCode);
      expect(event.payload['tripId'], refreshed.tripId);
      expect(event.payload['routeId'], refreshed.routeId);
      expect(event.payload['routeName'], refreshed.routeName);
      expect(event.payload['aggregateVersion'], refreshed.aggregateVersion);
    });
  });
}