import 'package:hive/hive.dart';
import 'property_status.dart';

part 'property.g.dart';

@HiveType(typeId: 5)
class Property extends HiveObject {
  @HiveField(0)
  final String receiverName;

  @HiveField(1)
  final String receiverPhone;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final String destination;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  PropertyStatus status;

  @HiveField(6)
  DateTime? inTransitAt;

  @HiveField(7)
  DateTime? deliveredAt;

  @HiveField(8)
  bool staffPickupConfirmed;

  @HiveField(9)
  bool receiverPickupConfirmed;

  @HiveField(10)
  DateTime? pickedUpAt;

  @HiveField(11)
  String? pickupOtp;

  @HiveField(12)
  final String createdByUserId;

  @HiveField(13)
  String? tripId;

  @HiveField(14)
  DateTime? otpGeneratedAt;

  @HiveField(15)
  int otpAttempts;

  @HiveField(16)
  DateTime? otpLockedUntil;

  @HiveField(17, defaultValue: 1)
  final int itemCount;

  @HiveField(18, defaultValue: '')
  String routeId;

  @HiveField(19, defaultValue: '')
  String routeName;

  @HiveField(20)
  DateTime? qrIssuedAt;

  @HiveField(21, defaultValue: '')
  String qrNonce;

  @HiveField(22)
  DateTime? qrConsumedAt;

  /// Stable human-friendly code used for Property QR.
  /// Example: P-20260213-8F3K
  @HiveField(23, defaultValue: '')
  String propertyCode;

  @HiveField(24, defaultValue: 0)
  int amountPaidTotal;

  @HiveField(25, defaultValue: 'UGX')
  String currency;

  @HiveField(26)
  DateTime? lastPaidAt;

  @HiveField(27, defaultValue: '')
  String lastPaymentMethod;

  @HiveField(28, defaultValue: '')
  String lastPaidByUserId;

  @HiveField(29, defaultValue: '')
  String lastPaidAtStation;

  @HiveField(30, defaultValue: '')
  String lastTxnRef;

  @HiveField(31)
  DateTime? loadedAt;

  @HiveField(32, defaultValue: '')
  String loadedAtStation;

  @HiveField(33, defaultValue: '')
  String loadedByUserId;

  /// Example: BC-482193-XK
  @HiveField(34, defaultValue: '')
  String trackingCode;

  @HiveField(35, defaultValue: false)
  bool notifyReceiver;

  @HiveField(36)
  DateTime? receiverNotifyEnabledAt;

  @HiveField(37, defaultValue: '')
  String receiverNotifyEnabledByUserId;

  @HiveField(38)
  DateTime? lastReceiverNotifiedAt;

  // NEW (append-only): receiver notification channel
  // values: "whatsapp" | "sms"
  @HiveField(39, defaultValue: 'whatsapp')
  String receiverNotifyChannel;

  Property({
    required this.receiverName,
    required this.receiverPhone,
    required this.description,
    required this.destination,
    this.itemCount = 1,
    required this.createdAt,
    required this.status,
    required this.createdByUserId,
    this.pickupOtp,
    this.inTransitAt,
    this.deliveredAt,
    this.staffPickupConfirmed = false,
    this.receiverPickupConfirmed = false,
    this.pickedUpAt,
    this.tripId,
    this.otpGeneratedAt,
    this.otpAttempts = 0,
    this.otpLockedUntil,
    String? routeId,
    String? routeName,
    this.qrIssuedAt,
    this.qrNonce = '',
    this.qrConsumedAt,
    String? propertyCode,
    this.amountPaidTotal = 0,
    String? currency,
    this.lastPaidAt,
    String? lastPaymentMethod,
    String? lastPaidByUserId,
    String? lastPaidAtStation,
    String? lastTxnRef,
    this.loadedAt,
    String? loadedAtStation,
    String? loadedByUserId,
    String? trackingCode,
    this.notifyReceiver = false,
    this.receiverNotifyEnabledAt,
    String? receiverNotifyEnabledByUserId,
    this.lastReceiverNotifiedAt,

    String? receiverNotifyChannel,
  })  : loadedAtStation = (loadedAtStation ?? '').trim(),
        loadedByUserId = (loadedByUserId ?? '').trim(),
        routeId = routeId ?? '',
        routeName = routeName ?? '',
        propertyCode = (propertyCode ?? '').trim(),
        trackingCode = (trackingCode ?? '').trim(),
        receiverNotifyEnabledByUserId = (receiverNotifyEnabledByUserId ?? '').trim(),
        currency = (currency == null || currency.trim().isEmpty) ? 'UGX' : currency.trim(),
        lastPaymentMethod = (lastPaymentMethod ?? '').trim(),
        lastPaidByUserId = (lastPaidByUserId ?? '').trim(),
        lastPaidAtStation = (lastPaidAtStation ?? '').trim(),
        lastTxnRef = (lastTxnRef ?? '').trim(),
        // default A: WhatsApp
        receiverNotifyChannel = ((receiverNotifyChannel ?? '').trim().toLowerCase() == 'sms')
            ? 'sms'
            : 'whatsapp';
}