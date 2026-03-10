import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/models/property.dart';
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
    _registerAdapterIfNeeded(SyncEventTypeAdapter());
    _registerAdapterIfNeeded(SyncEventAdapter());

    await HiveService.openPropertyBox();
    await HiveService.openSyncEventBox();
    await HiveService.openAppSettingsBox();
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
    PropertyStatus status = PropertyStatus.inTransit,
    DateTime? inTransitAt,
    DateTime? loadedAt,
  }) {
    return Property(
      receiverName: 'John Receiver',
      receiverPhone: '0780000000',
      description: 'Bag',
      destination: 'Juba',
      itemCount: 1,
      routeId: 'route-1',
      routeName: 'Kampala - Juba',
      createdAt: DateTime.parse('2026-03-10T08:00:00Z'),
      status: status,
      createdByUserId: 'sender-1',
      propertyCode: propertyCode,
      amountPaidTotal: 0,
      currency: 'UGX',
      aggregateVersion: aggregateVersion,
      inTransitAt: inTransitAt,
      loadedAt: loadedAt,
    );
  }

  SyncEvent makeDeliveredEvent({
    required String propertyCode,
    required int aggregateVersion,
    String deliveredAt = '2026-03-10T12:00:00Z',
  }) {
    return SyncEvent(
      eventId: 'evt-delivered-$propertyCode-$aggregateVersion',
      type: SyncEventType.propertyDelivered,
      aggregateType: 'property',
      aggregateId: propertyCode,
      actorUserId: 'staff-remote',
      payload: {
        'propertyCode': propertyCode,
        'deliveredAt': deliveredAt,
        'aggregateVersion': aggregateVersion,
      },
      createdAt: DateTime.parse('2026-03-10T12:00:01Z'),
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

  Property reloadProperty(String propertyCode) {
    return HiveService.propertyBox().values.firstWhere(
      (p) => p.propertyCode == propertyCode,
    );
  }

  group('PropertyService.applyPropertyDeliveredFromSync', () {
    test('promotes inTransit property to delivered', () async {
      final property = await saveProperty(
        makeProperty(
          propertyCode: 'P-20260310-DDDD',
          aggregateVersion: 1,
          status: PropertyStatus.inTransit,
          inTransitAt: DateTime.parse('2026-03-10T10:00:00Z'),
          loadedAt: DateTime.parse('2026-03-10T10:00:00Z'),
        ),
      );

      final event = makeDeliveredEvent(
        propertyCode: property.propertyCode,
        aggregateVersion: 2,
      );

      await PropertyService.applyPropertyDeliveredFromSync(event);

      final updated = reloadProperty(property.propertyCode);

      expect(updated.status, PropertyStatus.delivered);
      expect(updated.deliveredAt, isNotNull);
      expect(updated.aggregateVersion, 2);
    });

    test('ignores stale delivered replay', () async {
      final property = await saveProperty(
        makeProperty(
          propertyCode: 'P-20260310-EEEE',
          aggregateVersion: 5,
          status: PropertyStatus.delivered,
        ),
      );

      final event = makeDeliveredEvent(
        propertyCode: property.propertyCode,
        aggregateVersion: 4,
      );

      await PropertyService.applyPropertyDeliveredFromSync(event);

      final updated = reloadProperty(property.propertyCode);
      expect(updated.aggregateVersion, 5);
      expect(updated.status, PropertyStatus.delivered);
    });

    test('ignores replay for missing property', () async {
      final event = makeDeliveredEvent(
        propertyCode: 'P-20260310-MISSING',
        aggregateVersion: 2,
      );

      await PropertyService.applyPropertyDeliveredFromSync(event);

      expect(HiveService.propertyBox().values, isEmpty);
    });

    test('does not move pending property directly to delivered', () async {
      final property = await saveProperty(
        makeProperty(
          propertyCode: 'P-20260310-FFFF',
          aggregateVersion: 1,
          status: PropertyStatus.pending,
        ),
      );

      final event = makeDeliveredEvent(
        propertyCode: property.propertyCode,
        aggregateVersion: 2,
      );

      await PropertyService.applyPropertyDeliveredFromSync(event);

      final updated = reloadProperty(property.propertyCode);

      expect(updated.status, PropertyStatus.pending);
      expect(updated.deliveredAt, isNull);
      expect(updated.aggregateVersion, 2);
    });
  });
}
