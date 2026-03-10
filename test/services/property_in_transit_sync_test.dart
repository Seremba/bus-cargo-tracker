import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/models/property.dart';
import 'package:bus_cargo_tracker/models/property_item.dart';
import 'package:bus_cargo_tracker/models/property_item_status.dart';
import 'package:bus_cargo_tracker/models/property_status.dart';
import 'package:bus_cargo_tracker/models/sync_event.dart';
import 'package:bus_cargo_tracker/models/sync_event_type.dart';
import 'package:bus_cargo_tracker/services/hive_service.dart';
import 'package:bus_cargo_tracker/services/property_item_service.dart';
import 'package:bus_cargo_tracker/services/property_service.dart';

void _registerAdapterIfNeeded<T>(TypeAdapter<T> adapter) {
  if (!Hive.isAdapterRegistered(adapter.typeId)) {
    Hive.registerAdapter<T>(adapter);
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_property_in_transit_test_',
    );

    Hive.init(tempDir.path);

    _registerAdapterIfNeeded(PropertyStatusAdapter());
    _registerAdapterIfNeeded(PropertyAdapter());
    _registerAdapterIfNeeded(SyncEventTypeAdapter());
    _registerAdapterIfNeeded(SyncEventAdapter());
    _registerAdapterIfNeeded(PropertyItemStatusAdapter());
    _registerAdapterIfNeeded(PropertyItemAdapter());

    await HiveService.openPropertyBox();
    await HiveService.openPropertyItemBox();
    await HiveService.openSyncEventBox();
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Property makeProperty({
    required String propertyCode,
    int aggregateVersion = 1,
    PropertyStatus status = PropertyStatus.pending,
  }) {
    return Property(
      receiverName: 'John Receiver',
      receiverPhone: '0780000000',
      description: 'Bag',
      destination: 'Juba',
      itemCount: 3,
      routeId: 'route-1',
      routeName: 'Kampala - Juba',
      createdAt: DateTime.parse('2026-03-10T08:00:00Z'),
      status: status,
      createdByUserId: 'sender-1',
      propertyCode: propertyCode,
      amountPaidTotal: 0,
      currency: 'UGX',
      aggregateVersion: aggregateVersion,
    );
  }

  SyncEvent makeInTransitEvent({
    required String propertyCode,
    required String tripId,
    required int aggregateVersion,
    String inTransitAt = '2026-03-10T10:00:00Z',
  }) {
    return SyncEvent(
      eventId: 'evt-intransit-$propertyCode-$aggregateVersion',
      type: SyncEventType.propertyInTransit,
      aggregateType: 'property',
      aggregateId: propertyCode,
      actorUserId: 'driver-remote',
      payload: {
        'propertyCode': propertyCode,
        'tripId': tripId,
        'routeId': 'route-1',
        'routeName': 'Kampala - Juba',
        'inTransitAt': inTransitAt,
        'loadedForTrip': 2,
        'remainingAtStation': 1,
        'total': 3,
        'aggregateVersion': aggregateVersion,
      },
      createdAt: DateTime.parse('2026-03-10T10:00:01Z'),
      sourceDeviceId: 'remote-device',
      aggregateVersion: aggregateVersion,
      pendingPush: false,
      pushed: true,
      appliedLocally: false,
    );
  }

  Future<Property> saveProperty(Property property) async {
    final key = await HiveService.propertyBox().add(property);
    return HiveService.propertyBox().get(key)!;
  }

  Future<void> seedItemsAsLoaded(Property property) async {
    final itemSvc = PropertyItemService(HiveService.propertyItemBox());

    await itemSvc.ensureItemsForProperty(
      propertyKey: property.key.toString(),
      trackingCode: property.trackingCode,
      itemCount: property.itemCount,
    );

    await itemSvc.markSelectedItemsLoaded(
      propertyKey: property.key.toString(),
      itemNos: const [1, 2],
      now: DateTime.parse('2026-03-10T09:00:00Z'),
    );
  }

  Property reloadProperty(String propertyCode) {
    return HiveService.propertyBox().values.firstWhere(
      (p) => p.propertyCode == propertyCode,
    );
  }

  List<PropertyItem> reloadItems(Property property) {
    final itemSvc = PropertyItemService(HiveService.propertyItemBox());
    return itemSvc.getItemsForProperty(property.key.toString());
  }

  group('PropertyService.applyPropertyInTransitFromSync', () {
    test('promotes loaded items to inTransit and updates property', () async {
      final property = await saveProperty(
        makeProperty(propertyCode: 'P-20260310-AAAA', aggregateVersion: 1),
      );

      await seedItemsAsLoaded(property);

      final event = makeInTransitEvent(
        propertyCode: property.propertyCode,
        tripId: 'trip-1',
        aggregateVersion: 2,
      );

      await PropertyService.applyPropertyInTransitFromSync(event);

      final updated = reloadProperty(property.propertyCode);
      final items = reloadItems(updated);

      expect(updated.status, PropertyStatus.inTransit);
      expect(updated.tripId, 'trip-1');
      expect(updated.aggregateVersion, 2);
      expect(updated.inTransitAt, isNotNull);

      expect(items[0].status, PropertyItemStatus.inTransit);
      expect(items[1].status, PropertyItemStatus.inTransit);
      expect(items[2].status, PropertyItemStatus.pending);

      expect(items[0].tripId, 'trip-1');
      expect(items[1].tripId, 'trip-1');
      expect(items[2].tripId.trim(), '');
    });

    test('ignores stale replay', () async {
      final property = await saveProperty(
        makeProperty(
          propertyCode: 'P-20260310-BBBB',
          aggregateVersion: 5,
          status: PropertyStatus.inTransit,
        ),
      );

      final event = makeInTransitEvent(
        propertyCode: property.propertyCode,
        tripId: 'trip-2',
        aggregateVersion: 4,
      );

      await PropertyService.applyPropertyInTransitFromSync(event);

      final updated = reloadProperty(property.propertyCode);
      expect(updated.aggregateVersion, 5);
    });

    test('ignores replay for missing property', () async {
      final event = makeInTransitEvent(
        propertyCode: 'P-20260310-MISSING',
        tripId: 'trip-3',
        aggregateVersion: 2,
      );

      await PropertyService.applyPropertyInTransitFromSync(event);

      expect(HiveService.propertyBox().values, isEmpty);
    });

    test('does not downgrade advanced items', () async {
      final property = await saveProperty(
        makeProperty(propertyCode: 'P-20260310-CCCC', aggregateVersion: 1),
      );

      final itemSvc = PropertyItemService(HiveService.propertyItemBox());

      await itemSvc.ensureItemsForProperty(
        propertyKey: property.key.toString(),
        trackingCode: property.trackingCode,
        itemCount: property.itemCount,
      );

      final items = itemSvc.getItemsForProperty(property.key.toString());

      items[0].status = PropertyItemStatus.delivered;
      items[0].tripId = 'trip-old';
      await items[0].save();

      items[1].status = PropertyItemStatus.loaded;
      items[1].loadedAt = DateTime.parse('2026-03-10T09:00:00Z');
      await items[1].save();

      final event = makeInTransitEvent(
        propertyCode: property.propertyCode,
        tripId: 'trip-9',
        aggregateVersion: 2,
      );

      await PropertyService.applyPropertyInTransitFromSync(event);

      final refreshed = itemSvc.getItemsForProperty(property.key.toString());

      expect(refreshed[0].status, PropertyItemStatus.delivered);
      expect(refreshed[0].tripId, 'trip-old');

      expect(refreshed[1].status, PropertyItemStatus.inTransit);
      expect(refreshed[1].tripId, 'trip-9');
    });
  });
}