import 'package:hive/hive.dart';
import 'checkpoint.dart';
import 'trip_status.dart';

part 'trip.g.dart';

@HiveType(typeId: 7)
class Trip extends HiveObject {
  @HiveField(0)
  final String tripId;

  @HiveField(1)
  final String routeName;

  @HiveField(2)
  final String driverUserId;

  @HiveField(3)
  final DateTime startedAt;

  @HiveField(4)
  DateTime? endedAt;

  @HiveField(5)
  TripStatus status;

  @HiveField(6)
  final List<Checkpoint> checkpoints;

  @HiveField(7)
  int lastCheckpointIndex;

  @HiveField(8)
  final String routeId;

  // -----------------------------
  // ✅ NEW fields (Hive-safe: appended)
  // -----------------------------

  /// Candidate checkpoint being "entered" (debounce/dwell).
  @HiveField(9)
  int? candidateCheckpointIndex;

  /// When we first detected inside radius for the candidate checkpoint.
  @HiveField(10)
  DateTime? candidateSince;

  /// Last accepted GPS sample (for outlier rejection).
  @HiveField(11)
  double? lastGpsLat;

  @HiveField(12)
  double? lastGpsLng;

  @HiveField(13)
  DateTime? lastGpsAt;

  Trip({
    required this.tripId,
    required this.routeName,
    required this.driverUserId,
    required this.startedAt,
    required this.status,
    required this.checkpoints,
    required this.routeId,
    this.endedAt,
    this.lastCheckpointIndex = -1,
    this.candidateCheckpointIndex,
    this.candidateSince,
    this.lastGpsLat,
    this.lastGpsLng,
    this.lastGpsAt,
  });
}