import '../models/user.dart';
import 'audit_service.dart';
import 'hive_service.dart';
import 'session.dart';

class SessionService {
  static const _kUserId = 'current_user_id';
  static const _kLastActivityMs = 'session_last_activity_ms';

  static Future<void> _persistActivity() async {
    final box = HiveService.appSettingsBox();
    final ts = Session.lastActivityAt;
    if (ts != null) {
      await box.put(_kLastActivityMs, ts.millisecondsSinceEpoch);
    }
  }

  static DateTime? _loadPersistedActivity() {
    final box = HiveService.appSettingsBox();
    final v = box.get(_kLastActivityMs);
    if (v is int && v > 0) {
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    return null;
  }

  //  Public API

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

    // S5: record login time as first activity
    Session.touch();
    await _persistActivity();
  }

  /// Called on app startup. Restores session if the saved user still exists
  /// AND the inactivity timeout has not been exceeded.
  /// Returns null (and clears) if the session is stale or the user is gone.
  static Future<User?> restore() async {
    final userId = getSavedUserId();
    if (userId == null) return null;

    final user = HiveService.userBox().get(userId);
    if (user == null) {
      await clear();
      return null;
    }

    // S5: restore activity timestamp from storage before checking expiry
    final persisted = _loadPersistedActivity();
    Session.lastActivityAt = persisted;

    // Populate role so timeoutForRole() works correctly during the check
    Session.currentRole = user.role;

    if (Session.isExpired) {
      await AuditService.log(
        action: 'SESSION_EXPIRED_ON_RESTORE',
        propertyKey: userId,
        details:
            'Session expired on app restore for userId=$userId '
            'role=${user.role.name}. Last activity: $persisted',
      );
      await clear();
      return null;
    }

    // Session is still valid — fully populate and refresh timestamp
    Session.currentUserId = user.id;
    Session.currentUserFullName = user.fullName;
    Session.currentStationName = user.stationName;
    Session.currentAssignedRouteId = user.assignedRouteId;
    Session.currentAssignedRouteName = user.assignedRouteName;

    Session.touch();
    await _persistActivity();

    return user;
  }

  /// Call this from the app's navigation observer or key interaction points
  /// to keep the session alive while the user is active.
  static Future<void> touch() async {
    Session.touch();
    await _persistActivity();
  }

  /// Fully clears session — both in-memory and persisted state.
  static Future<void> clear() async {
    final box = HiveService.appSettingsBox();
    await box.delete(_kUserId);
    await box.delete(_kLastActivityMs);
    Session.clearMemory();
  }
}
