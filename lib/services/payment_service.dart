import '../models/payment_record.dart';
import '../models/property.dart';
import 'audit_service.dart';
import 'hive_service.dart';
import 'notification_service.dart';
import 'session.dart';

class PaymentService {
  static String _id() => DateTime.now().millisecondsSinceEpoch.toString();

  static Future<PaymentRecord> recordPayment({
    required Property property,
    required int amount, // can be negative for refund/adjustment
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

    // Prevent total from going below 0 (clamp negative ops)
    final currentTotal = fresh.amountPaidTotal;
    int appliedAmount = amount;

    if (currentTotal + appliedAmount < 0) {
      appliedAmount = -currentTotal; // clamp to zero
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

    // Update property totals
    fresh.amountPaidTotal = currentTotal + appliedAmount;
    fresh.currency = cleanCurrency;
    fresh.lastPaidAt = rec.createdAt;
    fresh.lastPaymentMethod = cleanMethod;
    fresh.lastPaidByUserId = rec.recordedByUserId;
    fresh.lastPaidAtStation = cleanStation;
    fresh.lastTxnRef = cleanTxnRef;

    await fresh.save();

    await AuditService.log(
      action: 'PAYMENT_RECORDED',
      propertyKey: fresh.key.toString(),
      details:
          'Kind=$cleanKind Amount=$cleanCurrency ${appliedAmount.abs()} Method=$cleanMethod Station=$cleanStation TxnRef=$cleanTxnRef Note=$cleanNote',
    );

    final prettyKind = cleanKind == 'refund'
        ? 'Refund'
        : (cleanKind == 'adjustment' ? 'Adjustment' : 'Payment');

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: '$prettyKind recorded',
      message:
          '$prettyKind: $cleanCurrency ${appliedAmount.abs()} at $cleanStation via ${cleanMethod.isEmpty ? '—' : cleanMethod}.',
    );

    return rec;
  }
}
