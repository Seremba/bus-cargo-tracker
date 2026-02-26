import 'package:hive/hive.dart';

part 'property_item_status.g.dart';

@HiveType(typeId: 64) // ensure this is unused
enum PropertyItemStatus {
  @HiveField(0)
  pending,

  @HiveField(1)
  loaded,

  @HiveField(2)
  inTransit,

  @HiveField(3)
  delivered,

  @HiveField(4)
  pickedUp,
}