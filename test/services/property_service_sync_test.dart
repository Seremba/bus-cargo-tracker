import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/models/audit_event.dart';
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
      'bebeto_property_service_sync_test_',
    );

    Hive.init(tempDir.path);

    _registerAdapterIfNeeded(PropertyStatusAdapter());
    _registerAdapterIfNeeded(PropertyAdapter());
    _registerAdapterIfNeeded(AuditEventAdapter());
    _registerAdapterIfNeeded(SyncEventTypeAdapter());
    _registerAdapterIfNeeded(SyncEventAdapter());

    await HiveService.openPropertyBox();
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

  test(
    'registerProperty saves property and emits propertyCreated sync event',
    () async {
      final saved = await PropertyService.registerProperty(
        receiverName: 'John Receiver',
        receiverPhone: '0780000000',
        description: 'Bag',
        destination: 'Juba',
        itemCount: 3,
        createdByUserId: 'desk-1',
        routeId: 'route-1',
        routeName: 'Kampala - Juba',
      );

      final properties = HiveService.propertyBox().values.toList();
      final events = HiveService.syncEventBox().values.toList();

      expect(properties.length, 1);
      expect(HiveService.auditBox().length, 1);

      expect(saved.propertyCode.trim().isNotEmpty, true);
      expect(saved.aggregateVersion, 1);
      expect(saved.status, PropertyStatus.pending);

      expect(events.length, 1);
      expect(events.first.type, SyncEventType.propertyCreated);
      expect(events.first.aggregateType, 'property');
      expect(events.first.aggregateId, saved.propertyCode.trim());
      expect(events.first.aggregateVersion, 1);
      expect(events.first.actorUserId, 'desk-1');

      expect(events.first.payload['propertyCode'], saved.propertyCode);
      expect(events.first.payload['receiverName'], 'John Receiver');
      expect(events.first.payload['receiverPhone'], '0780000000');
      expect(events.first.payload['description'], 'Bag');
      expect(events.first.payload['destination'], 'Juba');
      expect(events.first.payload['itemCount'], 3);
      expect(events.first.payload['routeId'], 'route-1');
      expect(events.first.payload['routeName'], 'Kampala - Juba');
      expect(events.first.payload['status'], 'pending');
      expect(events.first.payload['createdByUserId'], 'desk-1');
      expect(events.first.payload['aggregateVersion'], 1);
    },
  );

  test('registerProperty validation failure emits no sync event', () async {
    await expectLater(
      () => PropertyService.registerProperty(
        receiverName: '',
        receiverPhone: '0780000000',
        description: 'Bag',
        destination: 'Juba',
        itemCount: 3,
        createdByUserId: 'desk-1',
        routeId: 'route-1',
        routeName: 'Kampala - Juba',
      ),
      throwsArgumentError,
    );

    expect(HiveService.propertyBox().values, isEmpty);
    expect(HiveService.auditBox().values, isEmpty);
    expect(HiveService.syncEventBox().values, isEmpty);
  });
}
