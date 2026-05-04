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
import 'package:bus_cargo_tracker/models/user.dart';
import 'package:bus_cargo_tracker/models/user_role.dart';
import 'package:bus_cargo_tracker/services/hive_service.dart';
import 'package:bus_cargo_tracker/services/payment_service.dart';
import 'package:bus_cargo_tracker/services/session.dart';
import 'package:bus_cargo_tracker/services/session_service.dart';
import 'package:bus_cargo_tracker/services/sync_service.dart';

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

    _registerAdapterIfNeeded(UserRoleAdapter());
    _registerAdapterIfNeeded(UserAdapter());
    _registerAdapterIfNeeded(PropertyStatusAdapter());
    _registerAdapterIfNeeded(PropertyAdapter());
    _registerAdapterIfNeeded(PaymentRecordAdapter());
    _registerAdapterIfNeeded(NotificationItemAdapter());
    _registerAdapterIfNeeded(AuditEventAdapter());
    _registerAdapterIfNeeded(SyncEventTypeAdapter());
    _registerAdapterIfNeeded(SyncEventAdapter());

    await HiveService.openUserBox();
    await HiveService.openPropertyBox();
    await HiveService.openPaymentBox();
    await HiveService.openNotificationBox();
    await HiveService.openAuditBox();
    await HiveService.openSyncEventBox();
    await HiveService.openAppSettingsBox();

    Session.currentUserId = null;
    Session.currentRole = null;
    Session.currentUserFullName = null;
    Session.currentStationName = null;
    Session.currentAssignedRouteId = null;
    Session.currentAssignedRouteName = null;
  });

  tearDown(() async {
    await SessionService.clear();
    await Hive.close();

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('recordPayment saves payment and emits paymentRecorded sync event', () async {
    final user = User(
      id: 'u1',
      fullName: 'Desk User',
      phone: '0700000000',
      passwordHash: 'test-hash',
      role: UserRole.deskCargoOfficer,
      stationName: 'Kampala',
      createdAt: DateTime.now(),
    );

    await HiveService.userBox().put(user.id, user);
    await SessionService.saveUser(user);

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
      aggregateVersion: 0,
    );

    final key = await HiveService.propertyBox().add(property);
    final savedProperty = HiveService.propertyBox().get(key)!;

    final payment = await PaymentService.recordPayment(
      property: savedProperty,
      amount: 10000,
      method: 'cash',
      station: 'Kampala',
    );

    final refreshedProperty = HiveService.propertyBox().get(key)!;
    final payments = HiveService.paymentBox().values.toList();
    final syncEvents = HiveService.syncEventBox().values.toList();
    final notifications = HiveService.notificationBox().values.toList();

    expect(payment.kind, 'payment');
    expect(payments.length, 1);
    expect(syncEvents.length, 1);
    // Two notifications: one for the sender, one for the admin inbox
    expect(notifications.length, 2);

    final syncEvent = syncEvents.first;
    expect(syncEvent.type, SyncEventType.paymentRecorded);
    expect(syncEvent.aggregateType, 'payment');
    expect(syncEvent.aggregateId, payment.paymentId);
    expect(syncEvent.aggregateVersion, 1);
    expect(syncEvent.payload['paymentId'], payment.paymentId);
    expect(syncEvent.payload['propertyCode'], 'P-TEST-0001');
    expect(syncEvent.payload['amount'], 10000);
    expect(syncEvent.payload['kind'], 'payment');
    expect(syncEvent.payload['aggregateVersion'], 1);

    expect(refreshedProperty.amountPaidTotal, 10000);
    expect(refreshedProperty.aggregateVersion, 1);
  });

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
      aggregateVersion: 0,
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

    expect(HiveService.paymentBox().values.length, 0);
    expect(HiveService.syncEventBox().values.length, 0);

    final refreshedProperty = HiveService.propertyBox().get(key)!;
    expect(refreshedProperty.amountPaidTotal, 0);
    expect(refreshedProperty.aggregateVersion, 0);
  });

  test('recordPayment with refund emits paymentVoided sync event', () async {
    final property = Property(
      receiverName: 'John Receiver',
      receiverPhone: '0700000000',
      description: 'Bag',
      destination: 'Gulu',
      itemCount: 1,
      createdAt: DateTime.now(),
      status: PropertyStatus.pending,
      createdByUserId: 'sender-1',
      propertyCode: 'P-TEST-REFUND-1',
      aggregateVersion: 0,
    );

    final key = await HiveService.propertyBox().add(property);
    final savedProperty = HiveService.propertyBox().get(key)!;

    await PaymentService.recordPayment(
      property: savedProperty,
      amount: 10000,
      method: 'cash',
      station: 'Kampala',
    );

    final refreshedAfterPayment = HiveService.propertyBox().get(key)!;

    final refund = await PaymentService.recordPayment(
      property: refreshedAfterPayment,
      amount: -3000,
      method: 'cash',
      station: 'Kampala',
      kind: 'refund',
      note: 'Customer overpaid',
    );

    final refreshedProperty = HiveService.propertyBox().get(key)!;
    final syncEvents = HiveService.syncEventBox().values.toList();

    expect(refund.kind, 'refund');
    expect(refund.amount, -3000);
    expect(refreshedProperty.amountPaidTotal, 7000);
    expect(refreshedProperty.aggregateVersion, 2);

    final refundEvent = syncEvents.firstWhere(
      (e) => e.payload['paymentId'] == refund.paymentId,
    );

    // Phase 3: paymentRefunded renamed to paymentVoided
    expect(refundEvent.type, SyncEventType.paymentVoided);
    expect(refundEvent.aggregateType, 'payment');
    expect(refundEvent.aggregateId, refund.paymentId);
    expect(refundEvent.aggregateVersion, 2);
    expect(refundEvent.payload['paymentId'], refund.paymentId);
    expect(refundEvent.payload['propertyCode'], 'P-TEST-REFUND-1');
    expect(refundEvent.payload['amount'], -3000);
    expect(refundEvent.payload['kind'], 'refund');
    expect(refundEvent.payload['note'], 'Customer overpaid');
    expect(refundEvent.payload['aggregateVersion'], 2);
  });

  test('recordPayment with adjustment emits paymentAdjusted sync event', () async {
    final property = Property(
      receiverName: 'Jane Receiver',
      receiverPhone: '0700000001',
      description: 'Box',
      destination: 'Juba',
      itemCount: 1,
      createdAt: DateTime.now(),
      status: PropertyStatus.pending,
      createdByUserId: 'sender-2',
      propertyCode: 'P-TEST-ADJUST-1',
      aggregateVersion: 0,
    );

    final key = await HiveService.propertyBox().add(property);
    final savedProperty = HiveService.propertyBox().get(key)!;

    await PaymentService.recordPayment(
      property: savedProperty,
      amount: 5000,
      method: 'cash',
      station: 'Kampala',
    );

    final refreshedAfterPayment = HiveService.propertyBox().get(key)!;

    final adjustment = await PaymentService.recordPayment(
      property: refreshedAfterPayment,
      amount: 1500,
      method: 'cash',
      station: 'Kampala',
      kind: 'adjustment',
      note: 'Packing surcharge',
    );

    final refreshedProperty = HiveService.propertyBox().get(key)!;
    final syncEvents = HiveService.syncEventBox().values.toList();

    expect(adjustment.kind, 'adjustment');
    expect(adjustment.amount, 1500);
    expect(refreshedProperty.amountPaidTotal, 6500);
    expect(refreshedProperty.aggregateVersion, 2);

    final adjustmentEvent = syncEvents.firstWhere(
      (e) => e.payload['paymentId'] == adjustment.paymentId,
    );

    expect(adjustmentEvent.type, SyncEventType.paymentAdjusted);
    expect(adjustmentEvent.aggregateType, 'payment');
    expect(adjustmentEvent.aggregateId, adjustment.paymentId);
    expect(adjustmentEvent.aggregateVersion, 2);
    expect(adjustmentEvent.payload['paymentId'], adjustment.paymentId);
    expect(adjustmentEvent.payload['propertyCode'], 'P-TEST-ADJUST-1');
    expect(adjustmentEvent.payload['amount'], 1500);
    expect(adjustmentEvent.payload['kind'], 'adjustment');
    expect(adjustmentEvent.payload['note'], 'Packing surcharge');
    expect(adjustmentEvent.payload['aggregateVersion'], 2);
  });

  test('applyEvent supports paymentVoided and paymentAdjusted', () async {
    final property = Property(
      receiverName: 'Sync Receiver',
      receiverPhone: '0700000002',
      description: 'Parcel',
      destination: 'Nairobi',
      itemCount: 1,
      createdAt: DateTime.now(),
      status: PropertyStatus.pending,
      createdByUserId: 'sender-3',
      propertyCode: 'P-TEST-SYNC-1',
      aggregateVersion: 0,
    );

    await HiveService.propertyBox().add(property);

    // Phase 3: paymentRefunded renamed to paymentVoided
    final refundEvent = SyncEvent(
      eventId: 'evt-refund-1',
      type: SyncEventType.paymentVoided,
      aggregateType: 'payment',
      aggregateId: 'pay-refund-1',
      actorUserId: 'remote-user',
      aggregateVersion: 1,
      payload: {
        'paymentId': 'pay-refund-1',
        'propertyCode': 'P-TEST-SYNC-1',
        'amount': -2000,
        'currency': 'UGX',
        'method': 'cash',
        'txnRef': '',
        'station': 'Kampala',
        'createdAt': DateTime.now().toIso8601String(),
        'recordedByUserId': 'remote-user',
        'kind': 'refund',
        'note': 'remote refund',
        'aggregateVersion': 1,
      },
      createdAt: DateTime.now(),
      sourceDeviceId: 'remote-device',
    );

    final adjustmentEvent = SyncEvent(
      eventId: 'evt-adjust-1',
      type: SyncEventType.paymentAdjusted,
      aggregateType: 'payment',
      aggregateId: 'pay-adjust-1',
      actorUserId: 'remote-user',
      aggregateVersion: 2,
      payload: {
        'paymentId': 'pay-adjust-1',
        'propertyCode': 'P-TEST-SYNC-1',
        'amount': 500,
        'currency': 'UGX',
        'method': 'cash',
        'txnRef': '',
        'station': 'Kampala',
        'createdAt': DateTime.now().toIso8601String(),
        'recordedByUserId': 'remote-user',
        'kind': 'adjustment',
        'note': 'remote adjustment',
        'aggregateVersion': 2,
      },
      createdAt: DateTime.now(),
      sourceDeviceId: 'remote-device',
    );

    await HiveService.syncEventBox().put(refundEvent.eventId, refundEvent);
    await HiveService.syncEventBox().put(
      adjustmentEvent.eventId,
      adjustmentEvent,
    );

    await SyncService.applyEvent(refundEvent);
    await SyncService.applyEvent(adjustmentEvent);

    final payments = HiveService.paymentBox().values.toList();
    final refreshedProperty = HiveService.propertyBox().values.first;
    final savedRefundEvent = HiveService.syncEventBox().get(refundEvent.eventId)!;
    final savedAdjustmentEvent = HiveService.syncEventBox().get(
      adjustmentEvent.eventId,
    )!;

    expect(payments.length, 2);
    expect(payments.any((p) => p.kind == 'refund' && p.amount == -2000), isTrue);
    expect(
      payments.any((p) => p.kind == 'adjustment' && p.amount == 500),
      isTrue,
    );
    expect(refreshedProperty.amountPaidTotal, -1500);
    expect(refreshedProperty.aggregateVersion, 2);
    expect(savedRefundEvent.appliedLocally, isTrue);
    expect(savedAdjustmentEvent.appliedLocally, isTrue);
  });
}