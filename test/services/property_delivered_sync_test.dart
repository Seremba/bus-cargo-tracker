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
      'bebeto_property_delivered_sync_test_',
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

  group('PropertyService.applyPropertyDeliveredFromSync', () {
    test('promotes inTransit property to delivered', () async {
      final property = Property(
        receiverName: 'Receiver One',
        receiverPhone: '0700000000',
        description: 'Box',
        destination: 'Juba',
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.inTransit,
        createdByUserId: 'sender-1',
        propertyCode: 'P-DEL-SYNC-001',
        trackingCode: 'BC-DEL-SYNC-001',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        tripId: 'TRIP-DEL-SYNC-001',
        inTransitAt: DateTime.now().subtract(const Duration(hours: 2)),
        loadedAt: DateTime.now().subtract(const Duration(hours: 3)),
        aggregateVersion: 2,
      );

      final key = await HiveService.propertyBox().add(property);
      final propertyKey = key.toString();

      await HiveService.propertyItemBox().put(
        '$propertyKey#1',
        PropertyItem(
          itemKey: '$propertyKey#1',
          propertyKey: propertyKey,
          itemNo: 1,
          status: PropertyItemStatus.inTransit,
          tripId: 'TRIP-DEL-SYNC-001',
          labelCode: 'BC-DEL-SYNC-001|1',
        ),
      );
      await HiveService.propertyItemBox().put(
        '$propertyKey#2',
        PropertyItem(
          itemKey: '$propertyKey#2',
          propertyKey: propertyKey,
          itemNo: 2,
          status: PropertyItemStatus.inTransit,
          tripId: 'TRIP-DEL-SYNC-001',
          labelCode: 'BC-DEL-SYNC-001|2',
        ),
      );

      final event = SyncEvent(
        eventId: 'evt-delivered-1',
        type: SyncEventType.propertyDelivered,
        aggregateType: 'property',
        aggregateId: 'P-DEL-SYNC-001',
        actorUserId: 'remote-user',
        aggregateVersion: 3,
        payload: {
          'propertyCode': 'P-DEL-SYNC-001',
          'deliveredAt': DateTime.now().toIso8601String(),
          'aggregateVersion': 3,
        },
        createdAt: DateTime.now(),
        sourceDeviceId: 'remote-device',
      );

      await PropertyService.applyPropertyDeliveredFromSync(event);

      final refreshed = HiveService.propertyBox().get(key)!;
      final item1 = HiveService.propertyItemBox().get('$propertyKey#1')!;
      final item2 = HiveService.propertyItemBox().get('$propertyKey#2')!;

      expect(refreshed.status, PropertyStatus.delivered);
      expect(refreshed.deliveredAt, isNotNull);
      expect(refreshed.aggregateVersion, 3);
      expect(item1.status, PropertyItemStatus.delivered);
      expect(item2.status, PropertyItemStatus.delivered);
    });

    test('ignores stale delivered replay', () async {
      final property = Property(
        receiverName: 'Receiver Two',
        receiverPhone: '0700000001',
        description: 'Bag',
        destination: 'Juba',
        itemCount: 1,
        createdAt: DateTime.now(),
        status: PropertyStatus.delivered,
        createdByUserId: 'sender-2',
        propertyCode: 'P-DEL-SYNC-002',
        trackingCode: 'BC-DEL-SYNC-002',
        aggregateVersion: 5,
        deliveredAt: DateTime.now(),
      );

      final key = await HiveService.propertyBox().add(property);

      final event = SyncEvent(
        eventId: 'evt-delivered-2',
        type: SyncEventType.propertyDelivered,
        aggregateType: 'property',
        aggregateId: 'P-DEL-SYNC-002',
        actorUserId: 'remote-user',
        aggregateVersion: 4,
        payload: {
          'propertyCode': 'P-DEL-SYNC-002',
          'deliveredAt': DateTime.now().toIso8601String(),
          'aggregateVersion': 4,
        },
        createdAt: DateTime.now(),
        sourceDeviceId: 'remote-device',
      );

      await PropertyService.applyPropertyDeliveredFromSync(event);

      final refreshed = HiveService.propertyBox().get(key)!;
      expect(refreshed.status, PropertyStatus.delivered);
      expect(refreshed.aggregateVersion, 5);
    });

    test('ignores replay for missing property', () async {
      final event = SyncEvent(
        eventId: 'evt-delivered-3',
        type: SyncEventType.propertyDelivered,
        aggregateType: 'property',
        aggregateId: 'P-NOT-FOUND',
        actorUserId: 'remote-user',
        aggregateVersion: 1,
        payload: {
          'propertyCode': 'P-NOT-FOUND',
          'deliveredAt': DateTime.now().toIso8601String(),
          'aggregateVersion': 1,
        },
        createdAt: DateTime.now(),
        sourceDeviceId: 'remote-device',
      );

      await PropertyService.applyPropertyDeliveredFromSync(event);

      expect(HiveService.propertyBox().isEmpty, isTrue);
    });

    test('does not move pending property directly to delivered', () async {
      final property = Property(
        receiverName: 'Receiver Three',
        receiverPhone: '0700000002',
        description: 'Parcel',
        destination: 'Juba',
        itemCount: 1,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-3',
        propertyCode: 'P-DEL-SYNC-003',
        trackingCode: 'BC-DEL-SYNC-003',
        aggregateVersion: 1,
      );

      final key = await HiveService.propertyBox().add(property);

      final event = SyncEvent(
        eventId: 'evt-delivered-4',
        type: SyncEventType.propertyDelivered,
        aggregateType: 'property',
        aggregateId: 'P-DEL-SYNC-003',
        actorUserId: 'remote-user',
        aggregateVersion: 2,
        payload: {
          'propertyCode': 'P-DEL-SYNC-003',
          'deliveredAt': DateTime.now().toIso8601String(),
          'aggregateVersion': 2,
        },
        createdAt: DateTime.now(),
        sourceDeviceId: 'remote-device',
      );

      await PropertyService.applyPropertyDeliveredFromSync(event);

      final refreshed = HiveService.propertyBox().get(key)!;
      expect(refreshed.status, PropertyStatus.pending);
      expect(refreshed.deliveredAt, isNull);
      expect(refreshed.aggregateVersion, 2);
    });
  });
}
