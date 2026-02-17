import 'package:hive/hive.dart';

part 'checkpoint.g.dart';

@HiveType(typeId: 2)
class Checkpoint {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final double lat;

  @HiveField(2)
  final double lng;

  @HiveField(3)
  final double radiusMeters;

  @HiveField(4)
  DateTime? reachedAt;

  Checkpoint({
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    this.reachedAt,
  });
}
