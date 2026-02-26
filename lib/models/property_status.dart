import 'package:hive/hive.dart';

part 'property_status.g.dart';

@HiveType(typeId: 4) // 👈 UNIQUE typeId
enum PropertyStatus {
  @HiveField(0)
  pending,
  @HiveField(1)

  @HiveField(1)
  inTransit,

  @HiveField(2)
  delivered,

  @HiveField(3)
  pickedUp,
}
