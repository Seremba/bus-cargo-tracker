import 'package:hive/hive.dart';
import 'property_item_status.dart';

part 'property_item.g.dart';

@HiveType(typeId: 65) // ensure this is unused
class PropertyItem extends HiveObject {
  @HiveField(0)
  final String itemKey; // e.g. "propertyKey#3"

  @HiveField(1)
  final String propertyKey;

  @HiveField(2)
  final int itemNo; // 1..N

  @HiveField(3)
  PropertyItemStatus status;

  @HiveField(4)
  DateTime? loadedAt;

  @HiveField(5)
  DateTime? inTransitAt;

  @HiveField(6)
  DateTime? deliveredAt;

  @HiveField(7)
  DateTime? pickedUpAt;

  @HiveField(8)
  String tripId; // empty when not assigned

  @HiveField(9)
  final String labelCode; // per-item QR value

  @HiveField(10, defaultValue: '')
  String driverUserId; // driver this item is assigned to at loading time

  // (optional future fields: append only)

  PropertyItem({
    required this.itemKey,
    required this.propertyKey,
    required this.itemNo,
    required this.status,
    required this.labelCode,
    this.loadedAt,
    this.inTransitAt,
    this.deliveredAt,
    this.pickedUpAt,
    String? tripId,
    String? driverUserId,
  })  : tripId = (tripId ?? '').trim(),
        driverUserId = (driverUserId ?? '').trim();
}