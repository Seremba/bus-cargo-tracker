import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/models/audit_event.dart';
import 'package:bus_cargo_tracker/models/property.dart';
import 'package:bus_cargo_tracker/models/property_item.dart';
import 'package:bus_cargo_tracker/models/property_item_status.dart';
import 'package:bus_cargo_tracker/models/property_status.dart';
import 'package:bus_cargo_tracker/models/sync_event.dart';
import 'package:bus_cargo_tracker/models/sync_event_type.dart';
import 'package:bus_cargo_tracker/services/hive_service.dart';
import 'package:bus_cargo_tracker/services/property_item_service.dart';
import 'package:bus_cargo_tracker/services/session.dart';
import 'package:bus_cargo_tracker/services/sync_service.dart';

void _registerAdapterIfNeeded<T>(TypeAdapter<T> adapter) {
  if (!Hive.isAdapterRegistered(adapter.typeId)) {
    Hive.registerAdapter<T>(adapter);
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_property_item_sync_test_',
    );

    Hive.init(tempDir.path);

    _registerAdapterIfNeeded(PropertyStatusAdapter());
    _registerAdapterIfNeeded(PropertyAdapter());
    _registerAdapterIfNeeded(PropertyItemStatusAdapter());
    _registerAdapterIfNeeded(PropertyItemAdapter());
    _registerAdapterIfNeeded(AuditEventAdapter());
    _registerAdapterIfNeeded(SyncEventTypeAdapter());
    _registerAdapterIfNeeded(SyncEventAdapter());

    await HiveService.openPropertyBox();
    await HiveService.openPropertyItemBox();
    await HiveService.openAuditBox();
    await HiveService.openSyncEventBox();
    await HiveService.openAppSettingsBox();

    Session.currentUserId = 'desk-1';
    Session.currentRole = null;
    Session.currentUserFullName = null;
    Session.currentStationName = null;
    Session.currentAssignedRouteId = null;
    Session.currentAssignedRouteName = null;
  });

  tearDown(() async {
    await Hive.close();

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('markSelectedItemsLoaded emits propertyItemLoaded per loaded item', () async {
    final property = Property(
      receiverName: 'John Receiver',
      receiverPhone: '0780000000',
      description: 'Bag',
      destination: 'Juba',
      itemCount: 3,
      createdAt: DateTime.now(),
      status: PropertyStatus.pending,
      createdByUserId: 'desk-1',
      propertyCode: 'P-ITEM-LOAD-1',
      aggregateVersion: 0,
    );

    final key = await HiveService.propertyBox().add(property);
    final propertyKey = key.toString();

    final svc = PropertyItemService(HiveService.propertyItemBox());

    await svc.ensureItemsForProperty(
      propertyKey: propertyKey,
      trackingCode: 'TRK-1',
      itemCount: 3,
    );

    final now = DateTime.now();
    await svc.markSelectedItemsLoaded(
      propertyKey: propertyKey,
      itemNos: const [1, 3],
      now: now,
    );

    final items = svc.getItemsForProperty(propertyKey);
    final events = HiveService.syncEventBox().values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    expect(items.length, 3);
    expect(items[0].status, PropertyItemStatus.loaded);
    expect(items[1].status, PropertyItemStatus.pending);
    expect(items[2].status, PropertyItemStatus.loaded);

    expect(events.length, 2);
    expect(events[0].type, SyncEventType.propertyItemLoaded);
    expect(events[1].type, SyncEventType.propertyItemLoaded);

    expect(events[0].aggregateType, 'propertyItem');
    expect(events[0].payload['propertyKey'], propertyKey);
    expect(events[0].payload['propertyCode'], 'P-ITEM-LOAD-1');
    expect(events[0].payload['status'], 'loaded');

    expect(events[1].aggregateType, 'propertyItem');
    expect(events[1].payload['propertyKey'], propertyKey);
    expect(events[1].payload['propertyCode'], 'P-ITEM-LOAD-1');
    expect(events[1].payload['status'], 'loaded');
  });

  test('onTripStartedMoveLoadedToInTransitForProperty emits propertyItemInTransit per moved item', () async {
    final property = Property(
      receiverName: 'Jane Receiver',
      receiverPhone: '0780000001',
      description: 'Box',
      destination: 'Nairobi',
      itemCount: 3,
      createdAt: DateTime.now(),
      status: PropertyStatus.pending,
      createdByUserId: 'desk-1',
      propertyCode: 'P-ITEM-TRANSIT-1',
      aggregateVersion: 0,
    );

    final key = await HiveService.propertyBox().add(property);
    final propertyKey = key.toString();

    final svc = PropertyItemService(HiveService.propertyItemBox());

    await svc.ensureItemsForProperty(
      propertyKey: propertyKey,
      trackingCode: 'TRK-2',
      itemCount: 3,
    );

    await svc.markSelectedItemsLoaded(
      propertyKey: propertyKey,
      itemNos: const [1, 2],
      now: DateTime.now(),
    );

    await HiveService.syncEventBox().clear();

    final now = DateTime.now();
    await svc.onTripStartedMoveLoadedToInTransitForProperty(
      propertyKey: propertyKey,
      tripId: 'TRIP-1',
      now: now,
    );

    final items = svc.getItemsForProperty(propertyKey);
    final events = HiveService.syncEventBox().values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    expect(items[0].status, PropertyItemStatus.inTransit);
    expect(items[0].tripId, 'TRIP-1');
    expect(items[1].status, PropertyItemStatus.inTransit);
    expect(items[1].tripId, 'TRIP-1');
    expect(items[2].status, PropertyItemStatus.pending);

    expect(events.length, 2);
    expect(events[0].type, SyncEventType.propertyItemInTransit);
    expect(events[1].type, SyncEventType.propertyItemInTransit);
    expect(events[0].payload['tripId'], 'TRIP-1');
    expect(events[1].payload['tripId'], 'TRIP-1');
  });

  test('applyEvent supports property item lifecycle events', () async {
    final property = Property(
      receiverName: 'Sync Receiver',
      receiverPhone: '0780000002',
      description: 'Parcel',
      destination: 'Kigali',
      itemCount: 1,
      createdAt: DateTime.now(),
      status: PropertyStatus.pending,
      createdByUserId: 'desk-1',
      propertyCode: 'P-ITEM-SYNC-1',
      aggregateVersion: 0,
    );

    final key = await HiveService.propertyBox().add(property);
    final propertyKey = key.toString();

    final item = PropertyItem(
      itemKey: '$propertyKey#1',
      propertyKey: propertyKey,
      itemNo: 1,
      status: PropertyItemStatus.pending,
      labelCode: 'TRK-3|1',
    );

    await HiveService.propertyItemBox().put(item.itemKey, item);

    final loadedEvent = SyncEvent(
      eventId: 'evt-item-loaded-1',
      type: SyncEventType.propertyItemLoaded,
      aggregateType: 'propertyItem',
      aggregateId: item.itemKey,
      actorUserId: 'remote-user',
      aggregateVersion: 1,
      payload: {
        'itemKey': item.itemKey,
        'propertyKey': propertyKey,
        'propertyCode': 'P-ITEM-SYNC-1',
        'itemNo': 1,
        'status': 'loaded',
        'tripId': '',
        'labelCode': 'TRK-3|1',
        'loadedAt': DateTime.now().toIso8601String(),
        'eventAt': DateTime.now().toIso8601String(),
      },
      createdAt: DateTime.now(),
      sourceDeviceId: 'remote-device',
    );

    final transitEvent = SyncEvent(
      eventId: 'evt-item-transit-1',
      type: SyncEventType.propertyItemInTransit,
      aggregateType: 'propertyItem',
      aggregateId: item.itemKey,
      actorUserId: 'remote-user',
      aggregateVersion: 1,
      payload: {
        'itemKey': item.itemKey,
        'propertyKey': propertyKey,
        'propertyCode': 'P-ITEM-SYNC-1',
        'itemNo': 1,
        'status': 'inTransit',
        'tripId': 'TRIP-REMOTE-1',
        'labelCode': 'TRK-3|1',
        'inTransitAt': DateTime.now().toIso8601String(),
        'eventAt': DateTime.now().toIso8601String(),
      },
      createdAt: DateTime.now(),
      sourceDeviceId: 'remote-device',
    );

    final deliveredEvent = SyncEvent(
      eventId: 'evt-item-delivered-1',
      type: SyncEventType.propertyItemDelivered,
      aggregateType: 'propertyItem',
      aggregateId: item.itemKey,
      actorUserId: 'remote-user',
      aggregateVersion: 1,
      payload: {
        'itemKey': item.itemKey,
        'propertyKey': propertyKey,
        'propertyCode': 'P-ITEM-SYNC-1',
        'itemNo': 1,
        'status': 'delivered',
        'tripId': 'TRIP-REMOTE-1',
        'labelCode': 'TRK-3|1',
        'deliveredAt': DateTime.now().toIso8601String(),
        'eventAt': DateTime.now().toIso8601String(),
      },
      createdAt: DateTime.now(),
      sourceDeviceId: 'remote-device',
    );

    final pickedUpEvent = SyncEvent(
      eventId: 'evt-item-pickedup-1',
      type: SyncEventType.propertyItemPickedUp,
      aggregateType: 'propertyItem',
      aggregateId: item.itemKey,
      actorUserId: 'remote-user',
      aggregateVersion: 1,
      payload: {
        'itemKey': item.itemKey,
        'propertyKey': propertyKey,
        'propertyCode': 'P-ITEM-SYNC-1',
        'itemNo': 1,
        'status': 'pickedUp',
        'tripId': 'TRIP-REMOTE-1',
        'labelCode': 'TRK-3|1',
        'pickedUpAt': DateTime.now().toIso8601String(),
        'eventAt': DateTime.now().toIso8601String(),
      },
      createdAt: DateTime.now(),
      sourceDeviceId: 'remote-device',
    );

    await HiveService.syncEventBox().put(loadedEvent.eventId, loadedEvent);
    await HiveService.syncEventBox().put(transitEvent.eventId, transitEvent);
    await HiveService.syncEventBox().put(deliveredEvent.eventId, deliveredEvent);
    await HiveService.syncEventBox().put(pickedUpEvent.eventId, pickedUpEvent);

    await SyncService.applyEvent(loadedEvent);
    await SyncService.applyEvent(transitEvent);
    await SyncService.applyEvent(deliveredEvent);
    await SyncService.applyEvent(pickedUpEvent);

    final refreshed = HiveService.propertyItemBox().get(item.itemKey)!;
    final savedLoaded = HiveService.syncEventBox().get(loadedEvent.eventId)!;
    final savedTransit = HiveService.syncEventBox().get(transitEvent.eventId)!;
    final savedDelivered =
        HiveService.syncEventBox().get(deliveredEvent.eventId)!;
    final savedPickedUp =
        HiveService.syncEventBox().get(pickedUpEvent.eventId)!;

    expect(refreshed.status, PropertyItemStatus.pickedUp);
    expect(refreshed.tripId, 'TRIP-REMOTE-1');
    expect(refreshed.loadedAt, isNotNull);
    expect(refreshed.inTransitAt, isNotNull);
    expect(refreshed.deliveredAt, isNotNull);
    expect(refreshed.pickedUpAt, isNotNull);

    expect(savedLoaded.appliedLocally, isTrue);
    expect(savedTransit.appliedLocally, isTrue);
    expect(savedDelivered.appliedLocally, isTrue);
    expect(savedPickedUp.appliedLocally, isTrue);
  });
}