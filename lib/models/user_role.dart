import 'package:hive/hive.dart';

part 'user_role.g.dart';

@HiveType(typeId: 8)
enum UserRole {
  @HiveField(0)
  sender,

  @HiveField(1)
  staff,

  @HiveField(2)
  driver,

  @HiveField(3)
  admin,

  @HiveField(4)
  deskCargoOfficer,

  /// Partner company admin (e.g. Shaft Ltd) — scoped to specific routes only.
  @HiveField(5)
  partnerAdmin,
}