// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_role.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserRoleAdapter extends TypeAdapter<UserRole> {
  @override
  final int typeId = 8;

  @override
  UserRole read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return UserRole.sender;
      case 1:
        return UserRole.staff;
      case 2:
        return UserRole.driver;
      case 3:
        return UserRole.admin;
      case 4:
        return UserRole.deskCargoOfficer;
      default:
        return UserRole.sender;
    }
  }

  @override
  void write(BinaryWriter writer, UserRole obj) {
    switch (obj) {
      case UserRole.sender:
        writer.writeByte(0);
        break;
      case UserRole.staff:
        writer.writeByte(1);
        break;
      case UserRole.driver:
        writer.writeByte(2);
        break;
      case UserRole.admin:
        writer.writeByte(3);
        break;
      case UserRole.deskCargoOfficer:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserRoleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
