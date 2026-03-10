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
      'bebeto_property_picked_up_sync_test_',
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
    PropertyStatus status = PropertyStatus.delivered,
    DateTime? deliveredAt,
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
      deliveredAt: deliveredAt,
      inTransitAt: inTransitAt,
      loadedAt: loadedAt,
      pickupOtp: '123456',
      otpGeneratedAt: DateTime.parse('2026-03-10T11:30:00Z'),
      otpAttempts: 1,
    );
  }

  SyncEvent makePickedUpEvent({
    required String propertyCode,
    required int aggregateVersion,
    String pickedUpAt = '2026-03-10T13:00:00Z',
  }) {
    return SyncEvent(
      eventId: 'evt-pickedup-$propertyCode-$aggregateVersion',
      type: SyncEventType.propertyPickedUp,
      aggregateType: 'property',
      aggregateId: propertyCode,
      actorUserId: 'staff-remote',
      payload: {
        'propertyCode': propertyCode,
        'pickedUpAt': pickedUpAt,
        'aggregateVersion': aggregateVersion,
      },
      createdAt: DateTime.parse('2026-03-10T13:00:01Z'),
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

  group('PropertyService.applyPropertyPickedUpFromSync', () {
    test('promotes delivered property to pickedUp', () async {
      final property = await saveProperty(
        makeProperty(
          propertyCode: 'P-20260310-GGGG',
          aggregateVersion: 1,
          status: PropertyStatus.delivered,
          deliveredAt: DateTime.parse('2026-03-10T12:00:00Z'),
          inTransitAt: DateTime.parse('2026-03-10T10:00:00Z'),
          loadedAt: DateTime.parse('2026-03-10T10:00:00Z'),
        ),
      );

      final event = makePickedUpEvent(
        propertyCode: property.propertyCode,
        aggregateVersion: 2,
      );

      await PropertyService.applyPropertyPickedUpFromSync(event);

      final updated = reloadProperty(property.propertyCode);

      expect(updated.status, PropertyStatus.pickedUp);
      expect(updated.pickedUpAt, isNotNull);
      expect(updated.aggregateVersion, 2);
      expect(updated.staffPickupConfirmed, isTrue);
      expect(updated.receiverPickupConfirmed, isTrue);
      expect(updated.pickupOtp, isNull);
      expect(updated.otpGeneratedAt, isNull);
      expect(updated.otpAttempts, 0);
    });

    test('ignores stale pickedUp replay', () async {
      final property = await saveProperty(
        makeProperty(
          propertyCode: 'P-20260310-HHHH',
          aggregateVersion: 5,
          status: PropertyStatus.pickedUp,
        ),
      );

      final event = makePickedUpEvent(
        propertyCode: property.propertyCode,
        aggregateVersion: 4,
      );

      await PropertyService.applyPropertyPickedUpFromSync(event);

      final updated = reloadProperty(property.propertyCode);
      expect(updated.aggregateVersion, 5);
      expect(updated.status, PropertyStatus.pickedUp);
    });

    test('ignores replay for missing property', () async {
      final event = makePickedUpEvent(
        propertyCode: 'P-20260310-MISSING',
        aggregateVersion: 2,
      );

      await PropertyService.applyPropertyPickedUpFromSync(event);

      expect(HiveService.propertyBox().values, isEmpty);
    });

    test('does not move pending property directly to pickedUp', () async {
      final property = await saveProperty(
        makeProperty(
          propertyCode: 'P-20260310-IIII',
          aggregateVersion: 1,
          status: PropertyStatus.pending,
        ),
      );

      final event = makePickedUpEvent(
        propertyCode: property.propertyCode,
        aggregateVersion: 2,
      );

      await PropertyService.applyPropertyPickedUpFromSync(event);

      final updated = reloadProperty(property.propertyCode);

      expect(updated.status, PropertyStatus.pending);
      expect(updated.pickedUpAt, isNull);
      expect(updated.aggregateVersion, 2);
    });
  });
}