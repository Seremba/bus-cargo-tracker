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

  /// Returns true only if:
  ///   1. A user is logged in (Session.currentUserId is set), AND
  ///   2. That user exists in Hive, AND
  ///   3. Their stored role matches [role].
  static bool hasRoleVerified(UserRole role) {
    final userId = Session.currentUserId;
    if (userId == null || userId.trim().isEmpty) return false;

    final user = HiveService.userBox().get(userId);
    if (user == null) return false;

    return user.role == role;
  }

  /// Returns true only if the Hive-stored role is contained in [roles].
  static bool hasAnyVerified(Set<UserRole> roles) {
    final userId = Session.currentUserId;
    if (userId == null || userId.trim().isEmpty) return false;

    final user = HiveService.userBox().get(userId);
    if (user == null) return false;

    return roles.contains(user.role);
  }

  /// Throws [StateError] if the Hive-verified role does not match [role].
  static void requireRoleVerified(UserRole role) {
    if (!hasRoleVerified(role)) {
      throw StateError('Not authorized: requires ${role.name}');
    }
  }

  /// Throws [StateError] if the Hive-verified role is not in [roles].
  static void requireAnyVerified(Set<UserRole> roles) {
    if (!hasAnyVerified(roles)) {
      throw StateError('Not authorized');
    }
  }
}
