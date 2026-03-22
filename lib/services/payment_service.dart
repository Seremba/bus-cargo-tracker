import '../models/payment_record.dart';
import '../models/property.dart';
import '../models/sync_event.dart';
import 'audit_service.dart';
import 'hive_service.dart';
import 'notification_service.dart';
import 'session.dart';
import 'sync_service.dart';

class PaymentService {
  static String _id() => DateTime.now().millisecondsSinceEpoch.toString();

  static List<PaymentRecord> getPaymentsForProperty(String propertyKey) {
    final key = propertyKey.trim();
    if (key.isEmpty) return const <PaymentRecord>[];

    final payBox = HiveService.paymentBox();

    final list = payBox.values
        .where((x) => x.propertyKey.trim() == key)
        .cast<PaymentRecord>()
        .toList();

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  static bool hasValidPaymentForProperty(String propertyKey) {
    final payments = getPaymentsForProperty(propertyKey);
    if (payments.isEmpty) return false;

    final total = payments.fold<int>(0, (sum, x) => sum + x.amount);
    return total > 0;
  }

  static Future<PaymentRecord> recordPayment({
    required Property property,
    required int amount,
    String currency = 'UGX',
    required String method,
    String txnRef = '',
    required String station,
    String kind = 'payment', // payment / refund / adjustment
    String note = '',
  }) async {
    final pBox = HiveService.propertyBox();
    final payBox = HiveService.paymentBox();

    final fresh = pBox.get(property.key) ?? property;

    final cleanKind = kind.trim().toLowerCase();
    final cleanCurrency = currency.trim().isEmpty ? 'UGX' : currency.trim();
    final cleanMethod = method.trim();
    final cleanTxnRef = txnRef.trim();
    final cleanStation = station.trim();
    final cleanNote = note.trim();

    if (amount == 0) {
      throw ArgumentError('Amount cannot be 0');
    }
    if (cleanStation.isEmpty) {
      throw ArgumentError('Station is required');
    }

    if (cleanKind == 'payment' && amount < 0) {
      throw ArgumentError('Payment must be a positive amount');
    }
    if (cleanKind == 'refund' && amount > 0) {
      throw ArgumentError('Refund must be a negative amount');
    }
    if (cleanKind != 'payment' &&
        cleanKind != 'refund' &&
        cleanKind != 'adjustment') {
      throw ArgumentError('Invalid kind: $cleanKind');
    }

    final currentTotal = fresh.amountPaidTotal;
    int appliedAmount = amount;

    if (currentTotal + appliedAmount < 0) {
      appliedAmount = -currentTotal;
    }
    if (appliedAmount == 0) {
      throw StateError(
        'This operation would reduce total below 0. Nothing was applied.',
      );
    }

    final rec = PaymentRecord(
      paymentId: _id(),
      propertyKey: fresh.key.toString(),
      amount: appliedAmount,
      currency: cleanCurrency,
      method: cleanMethod,
      txnRef: cleanTxnRef,
      station: cleanStation,
      createdAt: DateTime.now(),
      recordedByUserId: Session.currentUserId ?? '',
      kind: cleanKind,
      note: cleanNote,
    );

    await payBox.add(rec);

    fresh.amountPaidTotal = currentTotal + appliedAmount;
    fresh.currency = cleanCurrency;
    fresh.lastPaidAt = rec.createdAt;
    fresh.lastPaymentMethod = cleanMethod;
    fresh.lastPaidByUserId = rec.recordedByUserId;
    fresh.lastPaidAtStation = cleanStation;
    fresh.lastTxnRef = cleanTxnRef;

    fresh.aggregateVersion += 1;

    await fresh.save();

    final Map<String, dynamic> syncPayload = {
      'paymentId': rec.paymentId,
      'propertyCode': fresh.propertyCode,
      'amount': rec.amount,
      'currency': rec.currency,
      'method': rec.method,
      'txnRef': rec.txnRef,
      'station': rec.station,
      'createdAt': rec.createdAt.toIso8601String(),
      'recordedByUserId': rec.recordedByUserId,
      'kind': rec.kind,
      'note': rec.note,
      'aggregateVersion': fresh.aggregateVersion,
    };

    final syncActor = rec.recordedByUserId.trim().isEmpty
        ? 'system'
        : rec.recordedByUserId;

    if (cleanKind == 'refund') {
      await SyncService.enqueuePaymentVoided(
        paymentId: rec.paymentId,
        actorUserId: syncActor,
        aggregateVersion: fresh.aggregateVersion,
        payload: syncPayload,
      );
    } else if (cleanKind == 'adjustment') {
      await SyncService.enqueuePaymentAdjusted(
        paymentId: rec.paymentId,
        actorUserId: syncActor,
        aggregateVersion: fresh.aggregateVersion,
        payload: syncPayload,
      );
    } else {
      await SyncService.enqueuePaymentRecorded(
        paymentId: rec.paymentId,
        actorUserId: syncActor,
        aggregateVersion: fresh.aggregateVersion,
        payload: syncPayload,
      );
    }

    await AuditService.log(
      action: 'PAYMENT_RECORDED',
      propertyKey: fresh.key.toString(),
      details:
          'Kind=$cleanKind Amount=$cleanCurrency ${appliedAmount.abs()} '
          'Method=$cleanMethod Station=$cleanStation TxnRef=$cleanTxnRef '
          'Note=$cleanNote',
    );

    final prettyKind = cleanKind == 'refund'
        ? 'Refund'
        : (cleanKind == 'adjustment' ? 'Adjustment' : 'Payment');

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: '$prettyKind recorded',
      message:
          '$prettyKind: $cleanCurrency ${appliedAmount.abs()} at '
          '$cleanStation via ${cleanMethod.isEmpty ? '—' : cleanMethod}.',
    );

    return rec;
  }

  static Future<void> applyPaymentRecordedFromSync(SyncEvent event) async {
    final payload = event.payload;

    final payBox = HiveService.paymentBox();
    final propertyBox = HiveService.propertyBox();

    final paymentId = (payload['paymentId'] ?? '').toString().trim();
    if (paymentId.isEmpty) {
      throw StateError('Payment sync event missing paymentId');
    }

    final propertyCode = (payload['propertyCode'] ?? '').toString().trim();
    if (propertyCode.isEmpty) {
      throw StateError('Payment sync event missing propertyCode');
    }

    final exists = payBox.values.any((p) => p.paymentId == paymentId);
    if (exists) return;

    Property? property;
    for (final p in propertyBox.values) {
      if (p.propertyCode.trim() == propertyCode) {
        property = p;
        break;
      }
    }

    if (property == null) {
      throw StateError(
        'Cannot apply payment sync event: property with code $propertyCode not found',
      );
    }

    final incomingVersion =
        (payload['aggregateVersion'] as num?)?.toInt() ??
        event.aggregateVersion;

    if (property.aggregateVersion >= incomingVersion) {
      return;
    }

    final rec = PaymentRecord(
      paymentId: paymentId,
      propertyKey: property.key.toString(),
      amount: (payload['amount'] as num).toInt(),
      currency: (payload['currency'] ?? 'UGX').toString(),
      method: (payload['method'] ?? '').toString(),
      txnRef: (payload['txnRef'] ?? '').toString(),
      station: (payload['station'] ?? '').toString(),
      createdAt: DateTime.parse((payload['createdAt'] ?? '').toString()),
      recordedByUserId: (payload['recordedByUserId'] ?? '').toString(),
      kind: (payload['kind'] ?? 'payment').toString(),
      note: (payload['note'] ?? '').toString(),
    );

    await payBox.add(rec);

    property.amountPaidTotal += rec.amount;
    property.currency = rec.currency;
    property.lastPaidAt = rec.createdAt;
    property.lastPaymentMethod = rec.method;
    property.lastPaidByUserId = rec.recordedByUserId;
    property.lastPaidAtStation = rec.station;
    property.lastTxnRef = rec.txnRef;
    property.aggregateVersion = incomingVersion;

    await property.save();
  }
}
