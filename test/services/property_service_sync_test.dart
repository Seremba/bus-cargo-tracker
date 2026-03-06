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
import 'package:bus_cargo_tracker/services/session.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_property_service_sync_test_',
    );

    Hive.init(tempDir.path);

    Hive.registerAdapter(PropertyStatusAdapter());
    Hive.registerAdapter(PropertyAdapter());
    Hive.registerAdapter(AuditEventAdapter());
    Hive.registerAdapter(SyncEventTypeAdapter());
    Hive.registerAdapter(SyncEventAdapter());

    await HiveService.openPropertyBox();
    await HiveService.openAuditBox();
    await HiveService.openSyncEventBox();

    Session.currentUserId = 'desk-1';
    Session.currentRole = null;
    Session.currentUserFullName = null;
    Session.currentStationName = null;
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

  test('registerProperty saves property and emits propertyCreated sync event',
      () async {
    final property = await PropertyService.registerProperty(
      receiverName: 'Jane Receiver',
      receiverPhone: '0700000001',
      description: 'Suitcase',
      destination: 'Juba',
      itemCount: 2,
      createdByUserId: 'desk-1',
      routeId: 'kampala-juba',
      routeName: 'Kampala → Juba',
    );

    expect(HiveService.propertyBox().length, 1);
    expect(HiveService.syncEventBox().length, 1);
    expect(HiveService.auditBox().length, 1);

    final event = HiveService.syncEventBox().values.first;

    expect(property.status, PropertyStatus.pending);
    expect(property.propertyCode, isNotEmpty);

    expect(event.type, SyncEventType.propertyCreated);
    expect(event.aggregateType, 'property');
    expect(event.aggregateId, property.key.toString());
    expect(event.actorUserId, 'desk-1');
    expect(event.pendingPush, isTrue);
    expect(event.pushed, isFalse);

    expect(event.payload['propertyKey'], property.key.toString());
    expect(event.payload['propertyCode'], property.propertyCode);
    expect(event.payload['receiverName'], 'Jane Receiver');
    expect(event.payload['receiverPhone'], '0700000001');
    expect(event.payload['description'], 'Suitcase');
    expect(event.payload['destination'], 'Juba');
    expect(event.payload['itemCount'], 2);
    expect(event.payload['routeId'], 'kampala-juba');
    expect(event.payload['routeName'], 'Kampala → Juba');
    expect(event.payload['status'], 'pending');
    expect(event.payload['createdByUserId'], 'desk-1');
    expect(event.payload['currency'], 'UGX');
  });

  test('registerProperty validation failure emits no sync event', () async {
    expect(
      () => PropertyService.registerProperty(
        receiverName: '',
        receiverPhone: '0700000001',
        description: 'Suitcase',
        destination: 'Juba',
        itemCount: 2,
        createdByUserId: 'desk-1',
        routeId: 'kampala-juba',
        routeName: 'Kampala → Juba',
      ),
      throwsArgumentError,
    );

    expect(HiveService.propertyBox().length, 0);
    expect(HiveService.syncEventBox().length, 0);
    expect(HiveService.auditBox().length, 0);
  });
}