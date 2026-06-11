import '../models/user_role.dart';

class Session {
  static String? currentUserId;
  static UserRole? currentRole;
  static String? currentUserFullName;
  static String? currentStationName;
  static String? currentAssignedRouteId;
  static String? currentAssignedRouteName;

  /// Partner company name e.g. "Shaft Ltd" — empty for regular users.
  static String currentPartnerName = '';

  /// Route IDs this partnerAdmin is restricted to — empty = no restriction.
  static List<String> scopedRouteIds = [];

  /// Whether current user is a partner admin with route restrictions.
  static bool get isPartnerAdmin =>
      currentRole == UserRole.partnerAdmin && scopedRouteIds.isNotEmpty;

  /// Returns true if the given routeId is accessible to the current user.
  static bool canAccessRoute(String routeId) {
    if (!isPartnerAdmin) return true;
    return scopedRouteIds.contains(routeId) ||
        scopedRouteIds.contains('${routeId}_rev');
  }

  static DateTime? lastActivityAt;

  static Duration timeoutForRole(UserRole? role) {
    switch (role) {
      case UserRole.admin:
      case UserRole.partnerAdmin:
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
    if (last == null) return true;
    return DateTime.now().isAfter(last.add(timeoutForRole(currentRole)));
  }

  static void clearMemory() {
    currentUserId = null;
    currentRole = null;
    currentUserFullName = null;
    currentStationName = null;
    currentAssignedRouteId = null;
    currentAssignedRouteName = null;
    currentPartnerName = '';
    scopedRouteIds = [];
    lastActivityAt = null;
  }
}