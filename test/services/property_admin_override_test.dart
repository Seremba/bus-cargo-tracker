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
      'bebeto_property_admin_override_test_',
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

  test('admin reset to pending also resets item states', () async {
    final property = Property(
      receiverName: 'Receiver Admin',
      receiverPhone: '0700000010',
      description: 'Goods',
      destination: 'Juba',
      itemCount: 2,
      createdAt: DateTime.now(),
      status: PropertyStatus.delivered,
      createdByUserId: 'sender-admin',
      propertyCode: 'P-ADMIN-001',
      trackingCode: 'BC-ADMIN-001',
      tripId: 'TRIP-ADMIN-001',
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
        tripId: 'TRIP-ADMIN-001',
        labelCode: 'BC-ADMIN-001|1',
      ),
    );

    await HiveService.propertyItemBox().put(
      '$propertyKey#2',
      PropertyItem(
        itemKey: '$propertyKey#2',
        propertyKey: propertyKey,
        itemNo: 2,
        status: PropertyItemStatus.delivered,
        tripId: 'TRIP-ADMIN-001',
        labelCode: 'BC-ADMIN-001|2',
      ),
    );

    final saved = HiveService.propertyBox().get(key)!;

    await PropertyService.adminSetStatus(saved, PropertyStatus.pending);

    final refreshed = HiveService.propertyBox().get(key)!;
    final items = HiveService.propertyItemBox().values
        .where((x) => x.propertyKey == propertyKey)
        .toList()
      ..sort((a, b) => a.itemNo.compareTo(b.itemNo));

    expect(refreshed.status, PropertyStatus.pending);
    expect(refreshed.tripId, isNull);
    expect(refreshed.deliveredAt, isNull);
    expect(refreshed.inTransitAt, isNull);
    expect(refreshed.loadedAt, isNull);

    expect(items[0].status, PropertyItemStatus.pending);
    expect(items[1].status, PropertyItemStatus.pending);
    expect(items[0].tripId, '');
    expect(items[1].tripId, '');
  });
}