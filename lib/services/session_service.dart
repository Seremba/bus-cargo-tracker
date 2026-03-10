import '../models/user.dart';
import 'hive_service.dart';
import 'session.dart';

class SessionService {
  static const _kUserId = 'current_user_id';

  static String? getSavedUserId() {
    final box = HiveService.appSettingsBox();
    final v = box.get(_kUserId);
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  static Future<void> saveUser(User user) async {
    final box = HiveService.appSettingsBox();
    await box.put(_kUserId, user.id);

    Session.currentUserId = user.id;
    Session.currentUserFullName = user.fullName;
    Session.currentRole = user.role;
    Session.currentStationName = user.stationName;
    Session.currentAssignedRouteId = user.assignedRouteId;
    Session.currentAssignedRouteName = user.assignedRouteName;
  }

  static Future<User?> restore() async {
    final userId = getSavedUserId();
    if (userId == null) return null;

    final user = HiveService.userBox().get(userId);
    if (user == null) {
      await clear();
      return null;
    }

    Session.currentUserId = user.id;
    Session.currentUserFullName = user.fullName;
    Session.currentRole = user.role;
    Session.currentStationName = user.stationName;
    Session.currentAssignedRouteId = user.assignedRouteId;
    Session.currentAssignedRouteName = user.assignedRouteName;

    return user;
  }

  static Future<void> clear() async {
    final box = HiveService.appSettingsBox();
    await box.delete(_kUserId);

    Session.currentUserId = null;
    Session.currentUserFullName = null;
    Session.currentRole = null;
    Session.currentStationName = null;
    Session.currentAssignedRouteId = null;
    Session.currentAssignedRouteName = null;
  }
}
