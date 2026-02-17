import 'package:hive/hive.dart';

part 'trip_status.g.dart';

@HiveType(typeId: 6)
enum TripStatus {
  @HiveField(0)
  active,

  @HiveField(1)
  ended,

  @HiveField(2)
  cancelled,
}


