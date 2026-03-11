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
    if (!Hive.isAdapterRegistered(15)) {  
      Hive.registerAdapter(AuditEventAdapter());  
    }  
    if (!Hive.isAdapterRegistered(65)) {  
      Hive.registerAdapter(PropertyItemAdapter());  
    }  
    if (!Hive.isAdapterRegistered(66)) {  
      Hive.registerAdapter(PropertyItemStatusAdapter());  
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
      'bebeto_property_loading_test_',  
    );  
  
    Hive.init(tempDir.path);  
  
    await HiveService.openPropertyBox();  
    await HiveService.openPropertyItemBox();  
    await HiveService.openSyncEventBox();  
    await HiveService.openAppSettingsBox();  
    await HiveService.openAuditBox();  
  
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
  
    await Hive.close();  
    if (await tempDir.exists()) {  
      await tempDir.delete(recursive: true);  
    }  
  });  
  
  group('PropertyService.markLoaded', () {  
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
      expect(refreshed.status, PropertyStatus.pending);  
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
      expect(refreshed.status, PropertyStatus.pending);  
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
  
    test('does not load property if status is not pending', () async {  
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
  
      final items = HiveService.propertyItemBox().values  
          .where((x) => x.propertyKey == mid.key.toString())  
          .toList()  
        ..sort((a, b) => a.itemNo.compareTo(b.itemNo));  
  
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
  
      final ok = await PropertyService.markLoaded(  
        saved,  
        station: 'Kampala',  
        itemNos: [1, 2],  
      );  
  
      expect(ok, isTrue);  
  
      final refreshed = HiveService.propertyBox().get(key)!;  
      final events = HiveService.syncEventBox().values.toList();  
  
      expect(events.length, 1);  
  
      final event = events.first;  
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