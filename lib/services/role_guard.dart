import '../models/user_role.dart';
import 'hive_service.dart';
import 'session.dart';

class RoleGuard {
  static bool hasRole(UserRole role) => Session.currentRole == role;

  static bool hasAny(Set<UserRole> roles) =>
      Session.currentRole != null && roles.contains(Session.currentRole);

  static void requireRole(UserRole role) {
    if (!hasRole(role)) {
      throw StateError('Not authorized: requires ${role.name}');
    }
  }

  static void requireAny(Set<UserRole> roles) {
    if (!hasAny(roles)) throw StateError('Not authorized');
  }

  static bool hasRoleVerified(UserRole role) {
    final userId = Session.currentUserId?.trim() ?? '';
    if (userId.isEmpty) return false;

    final user = HiveService.userBox().values
        .where((u) => u.id == userId)
        .firstOrNull;
    if (user == null) return false;
    return user.role == role;
  }

  static bool hasAnyVerified(Set<UserRole> roles) {
    final userId = Session.currentUserId?.trim() ?? '';
    if (userId.isEmpty) return false;

    final user = HiveService.userBox().values
        .where((u) => u.id == userId)
        .firstOrNull;
    if (user == null) return false;
    return roles.contains(user.role);
  }

  static void requireRoleVerified(UserRole role) {
    if (!hasRoleVerified(role)) {
      throw StateError('Not authorized: requires ${role.name}');
    }
  }

  static void requireAnyVerified(Set<UserRole> roles) {
    if (!hasAnyVerified(roles)) {
      throw StateError('Not authorized');
    }
  }
}
