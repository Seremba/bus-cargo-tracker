import 'package:hive/hive.dart';

part 'payment_record.g.dart';

@HiveType(typeId: 12)
class PaymentRecord extends HiveObject {
  @HiveField(0)
  final String paymentId;

  @HiveField(1)
  final String propertyKey;

  @HiveField(2)
  final int amount;

  @HiveField(3, defaultValue: 'UGX')
  final String currency;

  @HiveField(4, defaultValue: '')
  final String method;

  @HiveField(5, defaultValue: '')
  final String txnRef;

  @HiveField(6, defaultValue: '')
  final String station;

  @HiveField(7)
  final DateTime createdAt;

  @HiveField(8, defaultValue: '')
  final String recordedByUserId;

  @HiveField(9, defaultValue: 'payment')
  final String kind; // payment / refund / adjustment

  @HiveField(10, defaultValue: '')
  final String note;

  PaymentRecord({
    required this.paymentId,
    required this.propertyKey,
    required this.amount,
    this.currency = 'UGX',
    this.method = '',
    this.txnRef = '',
    this.station = '',
    required this.createdAt,
    this.recordedByUserId = '',
    this.kind = 'payment',
    this.note = '',
  });
}
