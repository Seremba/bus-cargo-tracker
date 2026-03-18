import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/data/routes.dart';
import 'package:bus_cargo_tracker/data/routes_helpers.dart';
import 'package:bus_cargo_tracker/models/audit_event.dart';
import 'package:bus_cargo_tracker/models/checkpoint.dart';
import 'package:bus_cargo_tracker/models/notification_item.dart';
import 'package:bus_cargo_tracker/models/payment_record.dart';
import 'package:bus_cargo_tracker/models/property.dart';
import 'package:bus_cargo_tracker/models/property_item.dart';
import 'package:bus_cargo_tracker/models/property_item_status.dart';
import 'package:bus_cargo_tracker/models/property_status.dart';
import 'package:bus_cargo_tracker/models/sync_event.dart';
import 'package:bus_cargo_tracker/models/sync_event_type.dart';
import 'package:bus_cargo_tracker/models/trip.dart';
import 'package:bus_cargo_tracker/models/trip_status.dart';
import 'package:bus_cargo_tracker/models/user.dart';
import 'package:bus_cargo_tracker/models/user_role.dart';
import 'package:bus_cargo_tracker/services/hive_service.dart';
import 'package:bus_cargo_tracker/services/property_service.dart';
import 'package:bus_cargo_tracker/services/session.dart';

AppRoute _validTestRoute() {
  for (final route in routes) {
    final cps = validatedCheckpoints(route);
    if (cps.isNotEmpty) return route;
  }
  throw StateError('No valid route with checkpoints found for test');
}

Future<Property> _seedLoadedProperty({
  required String receiverName,
  required String receiverPhone,
  required String propertyCode,
  required String createdByUserId,
  required AppRoute route,
  required int itemCount,
  required List<int> loadedItemNos,
}) async {
  final property = Property(
    receiverName: receiverName,
    receiverPhone: receiverPhone,
    description: 'Cargo',
    destination: route.checkpoints.last.name,
    itemCount: itemCount,
    createdAt: DateTime.now(),
    status: PropertyStatus.loaded,
    createdByUserId: createdByUserId,
    propertyCode: propertyCode,
    routeId: route.id,
    routeName: route.name,
    routeConfirmed: true,
    loadedAt: DateTime.now(),
    loadedAtStation: 'Kampala',
    loadedByUserId: 'desk-1',
  );

  final key = await HiveService.propertyBox().add(property);
  final saved = HiveService.propertyBox().get(key)!;
  final propertyKey = saved.key.toString();

  for (int i = 1; i <= itemCount; i++) {
    final isLoaded = loadedItemNos.contains(i);

    await HiveService.propertyItemBox().put(
      '$propertyKey#$i',
      PropertyItem(
        itemKey: '$propertyKey#$i',
        propertyKey: propertyKey,
        itemNo: i,
        status: isLoaded
            ? PropertyItemStatus.loaded
            : PropertyItemStatus.pending,
        tripId: '',
        labelCode: '${saved.trackingCode}|$i',
        loadedAt: isLoaded ? DateTime.now() : null,
      ),
    );
  }

  return HiveService.propertyBox().get(key)!;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_property_in_transit_test_',
    );

    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(CheckpointAdapter().typeId)) {
      Hive.registerAdapter(CheckpointAdapter());
    }
    if (!Hive.isAdapterRegistered(PropertyStatusAdapter().typeId)) {
      Hive.registerAdapter(PropertyStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(PropertyAdapter().typeId)) {
      Hive.registerAdapter(PropertyAdapter());
    }
    if (!Hive.isAdapterRegistered(TripStatusAdapter().typeId)) {
      Hive.registerAdapter(TripStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(TripAdapter().typeId)) {
      Hive.registerAdapter(TripAdapter());
    }
    if (!Hive.isAdapterRegistered(NotificationItemAdapter().typeId)) {
      Hive.registerAdapter(NotificationItemAdapter());
    }
    if (!Hive.isAdapterRegistered(AuditEventAdapter().typeId)) {
      Hive.registerAdapter(AuditEventAdapter());
    }
    if (!Hive.isAdapterRegistered(SyncEventTypeAdapter().typeId)) {
      Hive.registerAdapter(SyncEventTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(SyncEventAdapter().typeId)) {
      Hive.registerAdapter(SyncEventAdapter());
    }
    if (!Hive.isAdapterRegistered(PropertyItemStatusAdapter().typeId)) {
      Hive.registerAdapter(PropertyItemStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(PropertyItemAdapter().typeId)) {
      Hive.registerAdapter(PropertyItemAdapter());
    }
    if (!Hive.isAdapterRegistered(PaymentRecordAdapter().typeId)) {
      Hive.registerAdapter(PaymentRecordAdapter());
    }
    // S7: UserAdapter needed for hasAnyVerified
    if (!Hive.isAdapterRegistered(UserAdapter().typeId)) {
      Hive.registerAdapter(UserAdapter());
    }
    if (!Hive.isAdapterRegistered(UserRoleAdapter().typeId)) {
      Hive.registerAdapter(UserRoleAdapter());
    }

    await HiveService.openPropertyBox();
    await HiveService.openPropertyItemBox();
    await HiveService.openPaymentBox();
    await HiveService.openTripBox();
    await HiveService.openSyncEventBox();
    await HiveService.openAppSettingsBox();
    await HiveService.openAuditBox();
    await HiveService.openNotificationBox();
    // S7: open user box so hasAnyVerified can look up the actor
    await HiveService.openUserBox();

    final route = _validTestRoute();

    // S7: insert a driver user into Hive so hasAnyVerified passes
    const actorId = 'driver-1';
    final actor = User(
      id: actorId,
      fullName: 'Driver Tester',
      phone: '0700000099',
      passwordHash: 'test-hash',
      role: UserRole.driver,
      createdAt: DateTime.now(),
    );
    await HiveService.userBox().put(actorId, actor);

    Session.currentUserId = actorId;
    Session.currentRole = UserRole.driver;
    Session.currentUserFullName = 'Driver Tester';
    Session.currentStationName = 'Kampala';
    Session.currentAssignedRouteId = route.id;
    Session.currentAssignedRouteName = route.name;
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

  group('PropertyService.markInTransit', () {
    test('moves loaded items to inTransit and assigns trip', () async {
      final route = _validTestRoute();

      final saved = await _seedLoadedProperty(
        receiverName: 'Receiver One',
        receiverPhone: '0700000000',
        propertyCode: 'P-TRANSIT-001',
        createdByUserId: 'sender-1',
        route: route,
        itemCount: 3,
        loadedItemNos: [1, 2],
      );

      await PropertyService.markInTransit(saved);

      final refreshed = HiveService.propertyBox().get(saved.key)!;
      final items =
          HiveService.propertyItemBox().values
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
      expect(trips.first.routeId, route.id);
      expect(trips.first.routeName, route.name);
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

    test('does nothing when property is not pending or loaded', () async {
      final route = _validTestRoute();

      final property = Property(
        receiverName: 'Receiver Two',
        receiverPhone: '0700000001',
        description: 'Bag',
        destination: route.checkpoints.last.name,
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.inTransit,
        createdByUserId: 'sender-2',
        propertyCode: 'P-TRANSIT-002',
        routeId: route.id,
        routeName: route.name,
        routeConfirmed: true,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      await PropertyService.markInTransit(saved);

      final refreshed = HiveService.propertyBox().get(key)!;

      expect(refreshed.status, PropertyStatus.inTransit);
      expect(refreshed.tripId, isNull);
      expect(HiveService.tripBox().isEmpty, isTrue);
    });

    test('does nothing when no items are loaded', () async {
      final route = _validTestRoute();

      final property = Property(
        receiverName: 'Receiver Three',
        receiverPhone: '0700000002',
        description: 'Parcel',
        destination: route.checkpoints.last.name,
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-3',
        propertyCode: 'P-TRANSIT-003',
        routeId: route.id,
        routeName: route.name,
        routeConfirmed: true,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;
      final propertyKey = saved.key.toString();

      await HiveService.propertyItemBox().put(
        '$propertyKey#1',
        PropertyItem(
          itemKey: '$propertyKey#1',
          propertyKey: propertyKey,
          itemNo: 1,
          status: PropertyItemStatus.pending,
          tripId: '',
          labelCode: '${saved.trackingCode}|1',
        ),
      );

      await HiveService.propertyItemBox().put(
        '$propertyKey#2',
        PropertyItem(
          itemKey: '$propertyKey#2',
          propertyKey: propertyKey,
          itemNo: 2,
          status: PropertyItemStatus.pending,
          tripId: '',
          labelCode: '${saved.trackingCode}|2',
        ),
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
      expect(
        items.every((x) => x.status == PropertyItemStatus.pending),
        isTrue,
      );

      expect(HiveService.tripBox().isEmpty, isTrue);
      expect(
        HiveService.syncEventBox().values
            .where((e) => e.type == SyncEventType.propertyInTransit)
            .isEmpty,
        isTrue,
      );
    });

    test('reuses existing active trip on same route', () async {
      final route = _validTestRoute();

      final firstSaved = await _seedLoadedProperty(
        receiverName: 'Receiver Four',
        receiverPhone: '0700000003',
        propertyCode: 'P-TRANSIT-004',
        createdByUserId: 'sender-4',
        route: route,
        itemCount: 2,
        loadedItemNos: [1, 2],
      );

      final secondSaved = await _seedLoadedProperty(
        receiverName: 'Receiver Five',
        receiverPhone: '0700000004',
        propertyCode: 'P-TRANSIT-005',
        createdByUserId: 'sender-5',
        route: route,
        itemCount: 2,
        loadedItemNos: [1],
      );

      await PropertyService.markInTransit(firstSaved);
      final firstRefreshed = HiveService.propertyBox().get(firstSaved.key)!;
      final existingTripId = firstRefreshed.tripId;

      await PropertyService.markInTransit(secondSaved);
      final secondRefreshed = HiveService.propertyBox().get(secondSaved.key)!;

      expect(existingTripId, isNotNull);
      expect(existingTripId, isNotEmpty);
      expect(secondRefreshed.tripId, existingTripId);
      expect(HiveService.tripBox().values.length, 1);
    });

    test('emits propertyInTransit sync event with trip data', () async {
      final route = _validTestRoute();

      final saved = await _seedLoadedProperty(
        receiverName: 'Receiver Six',
        receiverPhone: '0700000005',
        propertyCode: 'P-TRANSIT-006',
        createdByUserId: 'sender-6',
        route: route,
        itemCount: 2,
        loadedItemNos: [1],
      );

      await PropertyService.markInTransit(saved);

      final refreshed = HiveService.propertyBox().get(saved.key)!;
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