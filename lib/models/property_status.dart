import 'package:hive/hive.dart';

part 'property_status.g.dart';

@HiveType(typeId: 6)
enum PropertyStatus {
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

  
  @HiveField(5)
  rejected,
}