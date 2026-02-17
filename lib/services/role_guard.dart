import '../models/user_role.dart';
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
}
