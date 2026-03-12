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
      'bebeto_property_picked_up_sync_test_',
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
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PropertyService.applyPropertyPickedUpFromSync', () {
    test('promotes delivered property to pickedUp', () async {
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
        propertyCode: 'P-PICK-SYNC-001',
        trackingCode: 'BC-PICK-SYNC-001',
        tripId: 'TRIP-PICK-SYNC-001',
        inTransitAt: now.subtract(const Duration(hours: 5)),
        deliveredAt: now.subtract(const Duration(hours: 1)),
        loadedAt: now.subtract(const Duration(hours: 6)),
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
          tripId: 'TRIP-PICK-SYNC-001',
          labelCode: 'BC-PICK-SYNC-001|1',
          deliveredAt: now.subtract(const Duration(hours: 1)),
        ),
      );

      final event = SyncEvent(
        eventId: 'evt-pickedup-1',
        type: SyncEventType.propertyPickedUp,
        aggregateType: 'property',
        aggregateId: 'P-PICK-SYNC-001',
        actorUserId: 'remote-user',
        aggregateVersion: 6,
        payload: {
          'propertyCode': 'P-PICK-SYNC-001',
          'pickedUpAt': now.toIso8601String(),
          'aggregateVersion': 6,
        },
        createdAt: now,
        sourceDeviceId: 'remote-device',
      );

      await PropertyService.applyPropertyPickedUpFromSync(event);

      final refreshed = HiveService.propertyBox().get(key)!;
      final item = HiveService.propertyItemBox().get('$propertyKey#1')!;

      expect(refreshed.status, PropertyStatus.pickedUp);
      expect(refreshed.pickedUpAt, isNotNull);
      expect(refreshed.staffPickupConfirmed, isTrue);
      expect(refreshed.receiverPickupConfirmed, isTrue);
      expect(refreshed.aggregateVersion, 6);
      expect(item.status, PropertyItemStatus.pickedUp);
      expect(item.pickedUpAt, isNotNull);
    });

    test('ignores stale pickedUp replay', () async {
      final property = Property(
        receiverName: 'Receiver Two',
        receiverPhone: '0700000001',
        description: 'Bag',
        destination: 'Juba',
        itemCount: 1,
        createdAt: DateTime.now(),
        status: PropertyStatus.pickedUp,
        createdByUserId: 'sender-2',
        propertyCode: 'P-PICK-SYNC-002',
        trackingCode: 'BC-PICK-SYNC-002',
        aggregateVersion: 7,
        pickedUpAt: DateTime.now(),
      );

      final key = await HiveService.propertyBox().add(property);

      final event = SyncEvent(
        eventId: 'evt-pickedup-2',
        type: SyncEventType.propertyPickedUp,
        aggregateType: 'property',
        aggregateId: 'P-PICK-SYNC-002',
        actorUserId: 'remote-user',
        aggregateVersion: 6,
        payload: {
          'propertyCode': 'P-PICK-SYNC-002',
          'pickedUpAt': DateTime.now().toIso8601String(),
          'aggregateVersion': 6,
        },
        createdAt: DateTime.now(),
        sourceDeviceId: 'remote-device',
      );

      await PropertyService.applyPropertyPickedUpFromSync(event);

      final refreshed = HiveService.propertyBox().get(key)!;
      expect(refreshed.status, PropertyStatus.pickedUp);
      expect(refreshed.aggregateVersion, 7);
    });

    test('ignores replay for missing property', () async {
      final event = SyncEvent(
        eventId: 'evt-pickedup-3',
        type: SyncEventType.propertyPickedUp,
        aggregateType: 'property',
        aggregateId: 'P-NOT-FOUND',
        actorUserId: 'remote-user',
        aggregateVersion: 1,
        payload: {
          'propertyCode': 'P-NOT-FOUND',
          'pickedUpAt': DateTime.now().toIso8601String(),
          'aggregateVersion': 1,
        },
        createdAt: DateTime.now(),
        sourceDeviceId: 'remote-device',
      );

      await PropertyService.applyPropertyPickedUpFromSync(event);

      expect(HiveService.propertyBox().isEmpty, isTrue);
    });

    test('does not move pending property directly to pickedUp', () async {
      final property = Property(
        receiverName: 'Receiver Three',
        receiverPhone: '0700000002',
        description: 'Parcel',
        destination: 'Juba',
        itemCount: 1,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-3',
        propertyCode: 'P-PICK-SYNC-003',
        trackingCode: 'BC-PICK-SYNC-003',
        aggregateVersion: 1,
      );

      final key = await HiveService.propertyBox().add(property);

      final event = SyncEvent(
        eventId: 'evt-pickedup-4',
        type: SyncEventType.propertyPickedUp,
        aggregateType: 'property',
        aggregateId: 'P-PICK-SYNC-003',
        actorUserId: 'remote-user',
        aggregateVersion: 2,
        payload: {
          'propertyCode': 'P-PICK-SYNC-003',
          'pickedUpAt': DateTime.now().toIso8601String(),
          'aggregateVersion': 2,
        },
        createdAt: DateTime.now(),
        sourceDeviceId: 'remote-device',
      );

      await PropertyService.applyPropertyPickedUpFromSync(event);

      final refreshed = HiveService.propertyBox().get(key)!;
      expect(refreshed.status, PropertyStatus.pending);
      expect(refreshed.pickedUpAt, isNull);
      expect(refreshed.aggregateVersion, 2);
    });
  });
}
