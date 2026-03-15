import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/models/audit_event.dart';
import 'package:bus_cargo_tracker/models/notification_item.dart';
import 'package:bus_cargo_tracker/models/payment_record.dart';
import 'package:bus_cargo_tracker/models/property.dart';
import 'package:bus_cargo_tracker/models/property_item.dart';
import 'package:bus_cargo_tracker/models/property_item_status.dart';
import 'package:bus_cargo_tracker/models/property_status.dart';
import 'package:bus_cargo_tracker/models/sync_event.dart';
import 'package:bus_cargo_tracker/models/sync_event_type.dart';
import 'package:bus_cargo_tracker/models/user_role.dart';
import 'package:bus_cargo_tracker/services/hive_service.dart';
import 'package:bus_cargo_tracker/services/payment_service.dart';
import 'package:bus_cargo_tracker/services/property_service.dart';
import 'package:bus_cargo_tracker/services/session.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(PropertyStatusAdapter().typeId)) {
      Hive.registerAdapter(PropertyStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(PropertyAdapter().typeId)) {
      Hive.registerAdapter(PropertyAdapter());
    }
    if (!Hive.isAdapterRegistered(AuditEventAdapter().typeId)) {
      Hive.registerAdapter(AuditEventAdapter());
    }
    if (!Hive.isAdapterRegistered(PropertyItemAdapter().typeId)) {
      Hive.registerAdapter(PropertyItemAdapter());
    }
    if (!Hive.isAdapterRegistered(PropertyItemStatusAdapter().typeId)) {
      Hive.registerAdapter(PropertyItemStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(SyncEventTypeAdapter().typeId)) {
      Hive.registerAdapter(SyncEventTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(SyncEventAdapter().typeId)) {
      Hive.registerAdapter(SyncEventAdapter());
    }
    if (!Hive.isAdapterRegistered(PaymentRecordAdapter().typeId)) {
      Hive.registerAdapter(PaymentRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(NotificationItemAdapter().typeId)) {
      Hive.registerAdapter(NotificationItemAdapter());
    }
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_property_loading_test_',
    );

    Hive.init(tempDir.path);

    await HiveService.openPropertyBox();
    await HiveService.openPropertyItemBox();
    await HiveService.openPaymentBox();
    await HiveService.openSyncEventBox();
    await HiveService.openAppSettingsBox();
    await HiveService.openAuditBox();
    await HiveService.openNotificationBox();

    Session.currentUserId = 'desk-1';
    Session.currentRole = UserRole.deskCargoOfficer;
    Session.currentUserFullName = 'Desk Tester';
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

  group('PropertyService.markLoaded', () {
    test('returns false when property is unpaid', () async {
      final property = Property(
        receiverName: 'Receiver Zero',
        receiverPhone: '0700999999',
        description: 'Unpaid box',
        destination: 'Juba',
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-0',
        propertyCode: 'P-LOAD-000',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      final ok = await PropertyService.markLoaded(
        saved,
        station: 'Kampala',
      );

      final refreshed = HiveService.propertyBox().get(key)!;
      final items = HiveService.propertyItemBox().values
          .where((x) => x.propertyKey == refreshed.key.toString())
          .toList();

      expect(ok, isFalse);
      expect(refreshed.status, PropertyStatus.pending);
      expect(items, isEmpty);
    });

    test('marks all items loaded when itemNos is omitted', () async {
      final property = Property(
        receiverName: 'Receiver One',
        receiverPhone: '0700000000',
        description: 'Box',
        destination: 'Juba',
        itemCount: 3,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-1',
        propertyCode: 'P-LOAD-001',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      await PaymentService.recordPayment(
        property: saved,
        amount: 10000,
        method: 'cash',
        station: 'Kampala',
      );

      final ok = await PropertyService.markLoaded(
        saved,
        station: 'Kampala',
      );

      final refreshed = HiveService.propertyBox().get(key)!;
      final items = HiveService.propertyItemBox().values
          .where((x) => x.propertyKey == refreshed.key.toString())
          .toList()
        ..sort((a, b) => a.itemNo.compareTo(b.itemNo));

      expect(ok, isTrue);
      expect(refreshed.status, PropertyStatus.loaded);
      expect(refreshed.loadedAt, isNotNull);
      expect(refreshed.loadedAtStation, 'Kampala');
      expect(refreshed.loadedByUserId, 'desk-1');

      expect(items.length, 3);
      expect(
        items.every((x) => x.status == PropertyItemStatus.loaded),
        isTrue,
      );
      expect(items.every((x) => x.loadedAt != null), isTrue);
    });

    test('marks only selected items loaded for partial load', () async {
      final property = Property(
        receiverName: 'Receiver Two',
        receiverPhone: '0700000001',
        description: 'Parcel',
        destination: 'Kabale',
        itemCount: 5,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-2',
        propertyCode: 'P-LOAD-002',
        routeId: '',
        routeName: '',
        routeConfirmed: false,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      await PaymentService.recordPayment(
        property: saved,
        amount: 20000,
        method: 'cash',
        station: 'Kampala',
      );

      final ok = await PropertyService.markLoaded(
        saved,
        station: 'Kampala',
        itemNos: [1, 3, 5],
      );

      final refreshed = HiveService.propertyBox().get(key)!;
      final items = HiveService.propertyItemBox().values
          .where((x) => x.propertyKey == refreshed.key.toString())
          .toList()
        ..sort((a, b) => a.itemNo.compareTo(b.itemNo));

      expect(ok, isTrue);
      expect(refreshed.status, PropertyStatus.loaded);
      expect(refreshed.loadedAt, isNotNull);
      expect(refreshed.loadedAtStation, 'Kampala');
      expect(refreshed.loadedByUserId, 'desk-1');

      expect(items.length, 5);

      expect(items[0].itemNo, 1);
      expect(items[0].status, PropertyItemStatus.loaded);

      expect(items[1].itemNo, 2);
      expect(items[1].status, PropertyItemStatus.pending);

      expect(items[2].itemNo, 3);
      expect(items[2].status, PropertyItemStatus.loaded);

      expect(items[3].itemNo, 4);
      expect(items[3].status, PropertyItemStatus.pending);

      expect(items[4].itemNo, 5);
      expect(items[4].status, PropertyItemStatus.loaded);
    });

    test('does not load property if status is not pending or loaded', () async {
      final property = Property(
        receiverName: 'Receiver Three',
        receiverPhone: '0700000002',
        description: 'Bag',
        destination: 'Juba',
        itemCount: 2,
        createdAt: DateTime.now(),
        status: PropertyStatus.inTransit,
        createdByUserId: 'sender-3',
        propertyCode: 'P-LOAD-003',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      final ok = await PropertyService.markLoaded(
        saved,
        station: 'Kampala',
      );

      final refreshed = HiveService.propertyBox().get(key)!;
      final items = HiveService.propertyItemBox().values
          .where((x) => x.propertyKey == refreshed.key.toString())
          .toList();

      expect(ok, isFalse);
      expect(refreshed.status, PropertyStatus.inTransit);
      expect(refreshed.loadedAt, isNull);
      expect(refreshed.loadedAtStation, '');
      expect(refreshed.loadedByUserId, '');
      expect(items, isEmpty);
    });

    test('does not downgrade already loaded items when called again', () async {
      final property = Property(
        receiverName: 'Receiver Four',
        receiverPhone: '0700000003',
        description: 'Mixed goods',
        destination: 'Juba',
        itemCount: 4,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-4',
        propertyCode: 'P-LOAD-004',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      await PaymentService.recordPayment(
        property: saved,
        amount: 15000,
        method: 'cash',
        station: 'Kampala',
      );

      final first = await PropertyService.markLoaded(
        saved,
        station: 'Kampala',
        itemNos: [1, 2],
      );

      expect(first, isTrue);

      final mid = HiveService.propertyBox().get(key)!;

      final second = await PropertyService.markLoaded(
        mid,
        station: 'Kampala',
        itemNos: [2, 3],
      );

      expect(second, isTrue);

      final refreshed = HiveService.propertyBox().get(key)!;
      final items = HiveService.propertyItemBox().values
          .where((x) => x.propertyKey == refreshed.key.toString())
          .toList()
        ..sort((a, b) => a.itemNo.compareTo(b.itemNo));

      expect(refreshed.status, PropertyStatus.loaded);
      expect(items.length, 4);
      expect(items[0].status, PropertyItemStatus.loaded);
      expect(items[1].status, PropertyItemStatus.loaded);
      expect(items[2].status, PropertyItemStatus.loaded);
      expect(items[3].status, PropertyItemStatus.pending);
    });

    test('emits itemsLoadedPartial sync event', () async {
      final property = Property(
        receiverName: 'Receiver Five',
        receiverPhone: '0700000004',
        description: 'Goods',
        destination: 'Juba',
        itemCount: 3,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-5',
        propertyCode: 'P-LOAD-005',
        routeId: 'kla_juba',
        routeName: 'Kampala → Juba',
        routeConfirmed: true,
        aggregateVersion: 1,
      );

      final key = await HiveService.propertyBox().add(property);
      final saved = HiveService.propertyBox().get(key)!;

      await PaymentService.recordPayment(
        property: saved,
        amount: 12000,
        method: 'cash',
        station: 'Kampala',
      );

      final ok = await PropertyService.markLoaded(
        saved,
        station: 'Kampala',
        itemNos: [1, 2],
      );

      expect(ok, isTrue);

      final refreshed = HiveService.propertyBox().get(key)!;
      final events = HiveService.syncEventBox().values.toList();

      final partialEvents = events
          .where((e) => e.type == SyncEventType.itemsLoadedPartial)
          .toList();

      final itemLoadedEvents = events
          .where((e) => e.type == SyncEventType.propertyItemLoaded)
          .toList();

      expect(partialEvents.length, 1);
      expect(itemLoadedEvents.length, 2);

      final event = partialEvents.first;
      expect(event.type, SyncEventType.itemsLoadedPartial);
      expect(event.aggregateType, 'property');
      expect(event.aggregateId, refreshed.propertyCode);
      expect(event.payload['propertyCode'], refreshed.propertyCode);
      expect(event.payload['loadedAtStation'], 'Kampala');
      expect(event.payload['aggregateVersion'], refreshed.aggregateVersion);
      expect(event.payload['itemNos'], [1, 2]);
    });
  });
}
