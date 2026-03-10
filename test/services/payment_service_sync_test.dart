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

void _registerAdapterIfNeeded<T>(TypeAdapter<T> adapter) {
  if (!Hive.isAdapterRegistered(adapter.typeId)) {
    Hive.registerAdapter<T>(adapter);
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_payment_service_sync_test_',
    );

    Hive.init(tempDir.path);

    _registerAdapterIfNeeded(PropertyStatusAdapter());
    _registerAdapterIfNeeded(PropertyAdapter());
    _registerAdapterIfNeeded(PaymentRecordAdapter());
    _registerAdapterIfNeeded(AuditEventAdapter());
    _registerAdapterIfNeeded(NotificationItemAdapter());
    _registerAdapterIfNeeded(SyncEventTypeAdapter());
    _registerAdapterIfNeeded(SyncEventAdapter());

    await HiveService.openPropertyBox();
    await HiveService.openPaymentBox();
    await HiveService.openAuditBox();
    await HiveService.openNotificationBox();
    await HiveService.openSyncEventBox();
    await HiveService.openAppSettingsBox();

    Session.currentUserId = 'cashier-1';
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

  test(
    'recordPayment saves payment and emits paymentRecorded sync event',
    () async {
      final property = Property(
        receiverName: 'John Receiver',
        receiverPhone: '0700000000',
        description: 'Bag',
        destination: 'Gulu',
        itemCount: 1,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: 'sender-1',
        propertyCode: 'P-TEST-0001',
      );

      final key = await HiveService.propertyBox().add(property);
      final savedProperty = HiveService.propertyBox().get(key)!;

      final rec = await PaymentService.recordPayment(
        property: savedProperty,
        amount: 5000,
        method: 'cash',
        station: 'Kampala',
      );

      final refreshedProperty = HiveService.propertyBox().get(key)!;
      final syncEvent = HiveService.syncEventBox().values.first;

      expect(HiveService.paymentBox().length, 1);
      expect(HiveService.auditBox().length, 1);
      expect(HiveService.notificationBox().length, 1);
      expect(HiveService.syncEventBox().length, 1);

      expect(rec.amount, 5000);
      expect(refreshedProperty.amountPaidTotal, 5000);
      expect(refreshedProperty.lastPaymentMethod, 'cash');
      expect(refreshedProperty.lastPaidAtStation, 'Kampala');

      expect(syncEvent.type, SyncEventType.paymentRecorded);
      expect(syncEvent.aggregateType, 'payment');
      expect(syncEvent.aggregateId, rec.paymentId);
      expect(syncEvent.actorUserId, 'cashier-1');
      expect(syncEvent.pendingPush, isTrue);
      expect(syncEvent.pushed, isFalse);

      expect(syncEvent.payload['paymentId'], rec.paymentId);
      expect(syncEvent.payload['propertyCode'], savedProperty.propertyCode);
      expect(syncEvent.payload['amount'], 5000);
      expect(syncEvent.payload['currency'], 'UGX');
      expect(syncEvent.payload['method'], 'cash');
      expect(syncEvent.payload['station'], 'Kampala');
      expect(syncEvent.payload['kind'], 'payment');
    },
  );

  test('recordPayment validation failure emits no sync event', () async {
    final property = Property(
      receiverName: 'John Receiver',
      receiverPhone: '0700000000',
      description: 'Bag',
      destination: 'Gulu',
      itemCount: 1,
      createdAt: DateTime.now(),
      status: PropertyStatus.pending,
      createdByUserId: 'sender-1',
      propertyCode: 'P-TEST-0002',
    );

    final key = await HiveService.propertyBox().add(property);
    final savedProperty = HiveService.propertyBox().get(key)!;

    expect(
      () => PaymentService.recordPayment(
        property: savedProperty,
        amount: 0,
        method: 'cash',
        station: 'Kampala',
      ),
      throwsArgumentError,
    );

    expect(HiveService.paymentBox().length, 0);
    expect(HiveService.auditBox().length, 0);
    expect(HiveService.notificationBox().length, 0);
    expect(HiveService.syncEventBox().length, 0);

    final refreshedProperty = HiveService.propertyBox().get(key)!;
    expect(refreshedProperty.amountPaidTotal, 0);
  });
}
