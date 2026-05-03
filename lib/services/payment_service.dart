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

  /// Finds the Property associated with a PaymentRecord.
  ///
  /// PaymentRecord.propertyKey is the Hive integer key from the originating
  /// device and is NOT reliable across devices. This method first tries the
  /// integer key (fast, works for locally-recorded payments), then falls back
  /// to a full scan matching by the string key representation.
  static Property? findPropertyForPayment(PaymentRecord x) {
    final propBox = HiveService.propertyBox();
    final key = int.tryParse(x.propertyKey);
    if (key != null) {
      final p = propBox.get(key);
      if (p != null) return p;
    }
    // Cross-device fallback: scan by string key match
    for (final p in propBox.values) {
      if (p.key.toString() == x.propertyKey) return p;
    }
    return null;
  }

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

    final propertyCode = fresh.propertyCode.trim().isEmpty
        ? fresh.key.toString()
        : fresh.propertyCode.trim();
    final description = fresh.description.trim().isEmpty
        ? 'cargo'
        : fresh.description.trim();
    final stationLabel =
        cleanStation.isEmpty ? 'the desk' : cleanStation;
    final methodLabel =
        cleanMethod.isEmpty ? '—' : cleanMethod;

    // Notify sender — enriched receipt with property and cargo details
    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: '$prettyKind received — $propertyCode',
      message:
          '$prettyKind of $cleanCurrency ${appliedAmount.abs()} '
          'recorded for your shipment of $description '
          '(${fresh.itemCount} item${fresh.itemCount == 1 ? '' : 's'}) '
          'to ${fresh.receiverName} in ${fresh.destination}.\n'
          'Station: $stationLabel  •  Method: $methodLabel'
          '${cleanTxnRef.isEmpty ? '' : '  •  Ref: $cleanTxnRef'}',
    );

    // Notify admin inbox
    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: '$prettyKind recorded — $propertyCode',
      message:
          '$cleanCurrency ${appliedAmount.abs()} recorded at $stationLabel '
          'for $description → ${fresh.receiverName} (${fresh.destination}).\n'
          'Method: $methodLabel'
          '${cleanTxnRef.isEmpty ? '' : '  •  Ref: $cleanTxnRef'}',
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

    // If the property hasn't arrived on this device yet, skip gracefully.
    // The event stays appliedLocally=false and will be retried on the next
    // sync cycle once the propertyCreated event has been applied.
    if (property == null) return;

    final incomingVersion =
        (payload['aggregateVersion'] as num?)?.toInt() ??
        event.aggregateVersion;

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

    // Always write the PaymentRecord — it is idempotent (duplicate check above).
    await payBox.add(rec);

    // Only update property aggregate fields when this event advances the
    // version. If a later event (e.g. status change) already moved the version
    // past this payment we still keep the PaymentRecord written above but
    // leave the property fields untouched to avoid overwriting newer state.
    if (incomingVersion > property.aggregateVersion) {
      property.amountPaidTotal += rec.amount;
      property.currency = rec.currency;
      property.lastPaidAt = rec.createdAt;
      property.lastPaymentMethod = rec.method;
      property.lastPaidByUserId = rec.recordedByUserId;
      property.lastPaidAtStation = rec.station;
      property.lastTxnRef = rec.txnRef;
      property.aggregateVersion = incomingVersion;
      await property.save();
    } else {
      // Version already ahead — still credit the amount so totals stay correct.
      property.amountPaidTotal += rec.amount;
      await property.save();
    }

    // Notify admin inbox on the device receiving this sync event
    final prettyKind = rec.kind == 'refund'
        ? 'Refund'
        : (rec.kind == 'adjustment' ? 'Adjustment' : 'Payment');
    final code = property.propertyCode.trim().isEmpty
        ? property.key.toString()
        : property.propertyCode.trim();
    final stationLabel =
        rec.station.trim().isEmpty ? 'the desk' : rec.station.trim();
    final methodLabel =
        rec.method.trim().isEmpty ? '—' : rec.method.trim();
    final description = property.description.trim().isEmpty
        ? 'cargo'
        : property.description.trim();

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: '$prettyKind recorded — $code',
      message:
          '${rec.currency} ${rec.amount} recorded at $stationLabel '
          'for $description → ${property.receiverName} (${property.destination}).\n'
          'Method: $methodLabel'
          '${rec.txnRef.trim().isEmpty ? '' : '  •  Ref: ${rec.txnRef.trim()}'}',
    );
  }
}