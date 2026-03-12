import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/models/audit_event.dart';
import 'package:bus_cargo_tracker/models/notification_item.dart';
import 'package:bus_cargo_tracker/models/outbound_message.dart';
import 'package:bus_cargo_tracker/models/property.dart';
import 'package:bus_cargo_tracker/models/property_item.dart';
import 'package:bus_cargo_tracker/models/property_item_status.dart';
import 'package:bus_cargo_tracker/models/property_status.dart';
import 'package:bus_cargo_tracker/models/sync_event.dart';
import 'package:bus_cargo_tracker/models/sync_event_type.dart';
import 'package:bus_cargo_tracker/models/user_role.dart';
import 'package:bus_cargo_tracker/services/hive_service.dart';
import 'package:bus_cargo_tracker/services/property_service.dart';
import 'package:bus_cargo_tracker/services/session.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(PropertyStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(PropertyAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(PropertyItemStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(PropertyItemAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(NotificationItemAdapter());
    }
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(AuditEventAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(SyncEventTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(17)) {
      Hive.registerAdapter(SyncEventAdapter());
    }
    if (!Hive.isAdapterRegistered(19)) {
      Hive.registerAdapter(OutboundMessageAdapter());
    }
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_admin_override_sync_test_',
    );

    Hive.init(tempDir.path);

    await HiveService.openPropertyBox();
    await HiveService.openPropertyItemBox();
    await HiveService.openAuditBox();
    await HiveService.openNotificationBox();
    await HiveService.openSyncEventBox();
    await HiveService.openOutboundMessageBox();
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

  test('adminSetStatus emits adminOverrideApplied when resetting to pending', () async {
    final property = Property(
      receiverName: 'Receiver Admin',
      receiverPhone: '0700000010',
      description: 'Goods',
      destination: 'Juba',
      itemCount: 1,
      createdAt: DateTime.now(),
      status: PropertyStatus.delivered,
      createdByUserId: 'sender-admin',
      propertyCode: 'P-ADMIN-SYNC-001',
      trackingCode: 'BC-ADMIN-SYNC-001',
      tripId: 'TRIP-ADMIN-SYNC-001',
      deliveredAt: DateTime.now(),
      inTransitAt: DateTime.now().subtract(const Duration(hours: 2)),
      loadedAt: DateTime.now().subtract(const Duration(hours: 3)),
      aggregateVersion: 3,
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
        tripId: 'TRIP-ADMIN-SYNC-001',
        labelCode: 'BC-ADMIN-SYNC-001|1',
      ),
    );

    final saved = HiveService.propertyBox().get(key)!;

    await PropertyService.adminSetStatus(saved, PropertyStatus.pending);

    final events = HiveService.syncEventBox().values
        .where((e) => e.type == SyncEventType.adminOverrideApplied)
        .toList();

    expect(events.length, 1);
    expect(events.first.aggregateType, 'property');
    expect(events.first.aggregateId, 'P-ADMIN-SYNC-001');
    expect(events.first.payload['fromStatus'], 'delivered');
    expect(events.first.payload['toStatus'], 'pending');
    expect(events.first.payload['resetItems'], isTrue);
  });

  test('adminSetStatus emits adminOverrideApplied for delivered to pickedUp', () async {
    final now = DateTime.now();

    final property = Property(
      receiverName: 'Receiver Admin Two',
      receiverPhone: '0700000011',
      description: 'Box',
      destination: 'Juba',
      itemCount: 1,
      createdAt: now.subtract(const Duration(days: 1)),
      status: PropertyStatus.delivered,
      createdByUserId: 'sender-admin-2',
      propertyCode: 'P-ADMIN-SYNC-002',
      trackingCode: 'BC-ADMIN-SYNC-002',
      tripId: 'TRIP-ADMIN-SYNC-002',
      deliveredAt: now.subtract(const Duration(hours: 1)),
      inTransitAt: now.subtract(const Duration(hours: 3)),
      loadedAt: now.subtract(const Duration(hours: 4)),
      pickupOtp: '123456',
      otpGeneratedAt: now.subtract(const Duration(minutes: 5)),
      aggregateVersion: 4,
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
        tripId: 'TRIP-ADMIN-SYNC-002',
        labelCode: 'BC-ADMIN-SYNC-002|1',
        deliveredAt: now.subtract(const Duration(hours: 1)),
      ),
    );

    final saved = HiveService.propertyBox().get(key)!;

    await PropertyService.adminSetStatus(saved, PropertyStatus.pickedUp);

    final events = HiveService.syncEventBox().values
        .where((e) => e.type == SyncEventType.adminOverrideApplied)
        .toList();

    expect(events.length, 1);
    expect(events.first.aggregateType, 'property');
    expect(events.first.aggregateId, 'P-ADMIN-SYNC-002');
    expect(events.first.payload['fromStatus'], 'delivered');
    expect(events.first.payload['toStatus'], 'pickedUp');
    expect(events.first.payload['resetItems'], isFalse);
  });
}