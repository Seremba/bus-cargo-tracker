import 'package:hive/hive.dart';

part 'user_role.g.dart';

@HiveType(typeId: 8) // pick a UNIQUE typeId not used by other adapters
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
}


