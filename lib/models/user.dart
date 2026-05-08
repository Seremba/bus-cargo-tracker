import 'package:hive/hive.dart';
import 'user_role.dart';

part 'user.g.dart';

@HiveType(typeId: 10)
class User extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String fullName;

  @HiveField(2)
  final String phone;

  @HiveField(3)
  final String passwordHash;

  @HiveField(4)
  final UserRole role;

  @HiveField(5)
  String? stationName;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  String? photoPath;

  @HiveField(8)
  String? assignedRouteId;

  @HiveField(9)
  String? assignedRouteName;

  @HiveField(10)
  String? passwordSalt;

  @HiveField(11, defaultValue: false)
  bool phoneVerified;

  /// Set to true when the driver's trip ends — signals admin to reassign.
  @HiveField(12, defaultValue: false)
  bool awaitingReassignment;

  /// Chronological log of every route this driver has been assigned to.
  /// Each entry: {'routeId', 'routeName', 'assignedAt', 'endedAt'?}
  @HiveField(13, defaultValue: [])
  List<Map> routeHistory;

  User({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.passwordHash,
    required this.role,
    this.stationName,
    required this.createdAt,
    this.photoPath,
    this.assignedRouteId,
    this.assignedRouteName,
    this.passwordSalt,
    this.phoneVerified = false,
    this.awaitingReassignment = false,
    List<Map>? routeHistory,
  }) : routeHistory = routeHistory ?? [];
}