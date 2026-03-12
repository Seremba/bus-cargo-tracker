import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/models/audit_event.dart';
import 'package:bus_cargo_tracker/models/sync_event.dart';
import 'package:bus_cargo_tracker/models/sync_event_type.dart';
import 'package:bus_cargo_tracker/models/user_role.dart';
import 'package:bus_cargo_tracker/services/audit_service.dart';
import 'package:bus_cargo_tracker/services/hive_service.dart';
import 'package:bus_cargo_tracker/services/session.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(AuditEventAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(SyncEventTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(17)) {
      Hive.registerAdapter(SyncEventAdapter());
    }
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_exception_logged_sync_test_',
    );

    Hive.init(tempDir.path);

    await HiveService.openAuditBox();
    await HiveService.openSyncEventBox();
    await HiveService.openAppSettingsBox();

    Session.currentUserId = 'admin-1';
    Session.currentRole = UserRole.admin;
    Session.currentUserFullName = 'Admin Tester';
    Session.currentStationName = 'Kampala';
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

  test('AuditService.log emits exceptionLogged sync event for failure-like actions', () async {
    await AuditService.log(
      action: 'trip_ensure_failed',
      propertyKey: 'prop-123',
      details: 'ensureActiveTrip failed: route mismatch',
    );

    final auditEvents = HiveService.auditBox().values.toList();
    final syncEvents = HiveService.syncEventBox().values
        .where((e) => e.type == SyncEventType.exceptionLogged)
        .toList();

    expect(auditEvents.length, 1);
    expect(syncEvents.length, 1);

    final sync = syncEvents.first;
    expect(sync.aggregateType, 'property');
    expect(sync.aggregateId, 'prop-123');
    expect(sync.actorUserId, 'admin-1');
    expect(sync.payload['action'], 'trip_ensure_failed');
    expect(sync.payload['propertyKey'], 'prop-123');
    expect(sync.payload['details'], 'ensureActiveTrip failed: route mismatch');
  });

  test('AuditService.log does not emit exceptionLogged for normal actions', () async {
    await AuditService.log(
      action: 'PROPERTY_REGISTERED',
      propertyKey: 'prop-456',
      details: 'Property created normally',
    );

    final auditEvents = HiveService.auditBox().values.toList();
    final syncEvents = HiveService.syncEventBox().values
        .where((e) => e.type == SyncEventType.exceptionLogged)
        .toList();

    expect(auditEvents.length, 1);
    expect(syncEvents, isEmpty);
  });
}