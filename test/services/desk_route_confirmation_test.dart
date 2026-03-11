import 'dart:io';  
  
import 'package:flutter_test/flutter_test.dart';  
import 'package:hive/hive.dart';  
  
import 'package:bus_cargo_tracker/models/audit_event.dart';  
import 'package:bus_cargo_tracker/models/notification_item.dart';  
import 'package:bus_cargo_tracker/models/payment_record.dart';  
import 'package:bus_cargo_tracker/models/property.dart';  
import 'package:bus_cargo_tracker/models/property_status.dart';  
import 'package:bus_cargo_tracker/models/sync_event.dart';  
import 'package:bus_cargo_tracker/models/sync_event_type.dart';  
import 'package:bus_cargo_tracker/services/hive_service.dart';  
import 'package:bus_cargo_tracker/services/payment_service.dart';  
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
    if (!Hive.isAdapterRegistered(1)) {  
      Hive.registerAdapter(PaymentRecordAdapter());  
    }  
    if (!Hive.isAdapterRegistered(15)) {  
      Hive.registerAdapter(AuditEventAdapter());  
    }  
    if (!Hive.isAdapterRegistered(14)) {  
      Hive.registerAdapter(NotificationItemAdapter());  
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
      'bebeto_desk_route_confirmation_test_',  
    );  
  
    Hive.init(tempDir.path);  
  
    await HiveService.openPropertyBox();  
    await HiveService.openPaymentBox();  
    await HiveService.openAuditBox();  
    await HiveService.openNotificationBox();  
    await HiveService.openSyncEventBox();  
    await HiveService.openAppSettingsBox();  
  
    Session.currentUserId = 'desk-1';  
    Session.currentRole = null;  
    Session.currentUserFullName = null;  
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
  
  group('desk route confirmation flow', () {  
    test('ambiguous property can be route-confirmed before payment', () async {  
      final property = Property(  
        receiverName: 'Receiver One',  
        receiverPhone: '0700000000',  
        description: 'Box',  
        destination: 'Kabale',  
        itemCount: 1,  
        createdAt: DateTime.now(),  
        status: PropertyStatus.pending,  
        createdByUserId: 'sender-1',  
        propertyCode: 'P-TEST-KABALE-001',  
        routeId: '',  
        routeName: '',  
        routeConfirmed: false,  
      );  
  
      final key = await HiveService.propertyBox().add(property);  
      final saved = HiveService.propertyBox().get(key)!;  
  
      expect(saved.routeConfirmed, isFalse);  
      expect(saved.routeId, '');  
      expect(saved.routeName, '');  
  
      // Simulate current desk-screen confirmation step  
      saved.routeId = 'kla_goma';  
      saved.routeName = 'Kampala → Goma';  
      saved.routeConfirmed = true;  
      await saved.save();  
  
      final confirmed = HiveService.propertyBox().get(key)!;  
  
      expect(confirmed.routeConfirmed, isTrue);  
      expect(confirmed.routeId, 'kla_goma');  
      expect(confirmed.routeName, 'Kampala → Goma');  
  
      final rec = await PaymentService.recordPayment(  
        property: confirmed,  
        amount: 15000,  
        currency: 'UGX',  
        method: 'cash',  
        station: 'Kampala',  
        kind: 'payment',  
      );  
  
      final refreshed = HiveService.propertyBox().get(key)!;  
  
      expect(rec.amount, 15000);  
      expect(refreshed.amountPaidTotal, 15000);  
      expect(refreshed.routeConfirmed, isTrue);  
      expect(refreshed.routeId, 'kla_goma');  
      expect(refreshed.routeName, 'Kampala → Goma');  
    });  
  
    test('already confirmed property can be paid directly', () async {  
      final property = Property(  
        receiverName: 'Receiver Two',  
        receiverPhone: '0700000001',  
        description: 'Bag',  
        destination: 'Juba',  
        itemCount: 2,  
        createdAt: DateTime.now(),  
        status: PropertyStatus.pending,  
        createdByUserId: 'sender-2',  
        propertyCode: 'P-TEST-JUBA-001',  
        routeId: 'kla_juba',  
        routeName: 'Kampala → Juba',  
        routeConfirmed: true,  
      );  
  
      final key = await HiveService.propertyBox().add(property);  
      final saved = HiveService.propertyBox().get(key)!;  
  
      final rec = await PaymentService.recordPayment(  
        property: saved,  
        amount: 22000,  
        currency: 'UGX',  
        method: 'momo',  
        station: 'Kampala',  
        kind: 'payment',  
      );  
  
      final refreshed = HiveService.propertyBox().get(key)!;  
  
      expect(rec.amount, 22000);  
      expect(refreshed.amountPaidTotal, 22000);  
      expect(refreshed.routeConfirmed, isTrue);  
      expect(refreshed.routeId, 'kla_juba');  
      expect(refreshed.routeName, 'Kampala → Juba');  
    });  
  
    test('route confirmation persists before later operations', () async {  
      final property = Property(  
        receiverName: 'Receiver Three',  
        receiverPhone: '0700000002',  
        description: 'Parcel',  
        destination: 'Kabale',  
        itemCount: 1,  
        createdAt: DateTime.now(),  
        status: PropertyStatus.pending,  
        createdByUserId: 'sender-3',  
        propertyCode: 'P-TEST-KABALE-002',  
        routeId: '',  
        routeName: '',  
        routeConfirmed: false,  
      );  
  
      final key = await HiveService.propertyBox().add(property);  
      final fresh = HiveService.propertyBox().get(key)!;  
  
      fresh.routeId = 'kla_kigali_katuna';  
      fresh.routeName = 'Kampala → Kigali (via Katuna)';  
      fresh.routeConfirmed = true;  
      await fresh.save();  
  
      final reloaded = HiveService.propertyBox().get(key)!;  
  
      expect(reloaded.routeConfirmed, isTrue);  
      expect(reloaded.routeId, 'kla_kigali_katuna');  
      expect(reloaded.routeName, 'Kampala → Kigali (via Katuna)');  
      expect(reloaded.status, PropertyStatus.pending);  
    });  
  });  
}