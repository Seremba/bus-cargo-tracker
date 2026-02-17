import 'package:hive/hive.dart';
import 'user_role.dart';

part 'user.g.dart';

@HiveType(typeId: 9)
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
  String? stationName; // for staff/driver later

  @HiveField(6)
  final DateTime createdAt;
  @HiveField(7)
  String? photoPath;

  User({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.passwordHash,
    required this.role,
    this.stationName,
    required this.createdAt,
    this.photoPath,
  });
}
