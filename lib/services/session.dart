import '../models/user_role.dart';

class Session {
  static String? currentUserId;
  static UserRole? currentRole;
  static String? currentUserFullName;
  static String? currentStationName;
  static String? currentAssignedRouteId;
  static String? currentAssignedRouteName;

  static DateTime? lastActivityAt;

  /// Role-aware inactivity timeouts.
  static Duration timeoutForRole(UserRole? role) {
    switch (role) {
      case UserRole.admin:
      case UserRole.staff:
      case UserRole.deskCargoOfficer:
        return const Duration(minutes: 15);
      case UserRole.driver:
        return const Duration(minutes: 60);
      case UserRole.sender:
      case null:
        return const Duration(hours: 24);
    }
  }

  static void touch() {
    if (currentUserId != null) {
      lastActivityAt = DateTime.now();
    }
  }

  static bool get isExpired {
    if (currentUserId == null) return false;
    final last = lastActivityAt;
    if (last == null) return true; // session exists but was never touched
    return DateTime.now().isAfter(last.add(timeoutForRole(currentRole)));
  }

  static void clearMemory() {
    currentUserId = null;
    currentRole = null;
    currentUserFullName = null;
    currentStationName = null;
    currentAssignedRouteId = null;
    currentAssignedRouteName = null;
    lastActivityAt = null;
  }
}
