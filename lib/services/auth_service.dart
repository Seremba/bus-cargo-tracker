import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../models/user.dart';
import '../models/user_role.dart';
import 'hive_service.dart';
import 'session.dart';
import 'role_guard.dart';

class AuthService {
  static String hashPassword(String password) {
    final bytes = utf8.encode(password.trim());
    return sha256.convert(bytes).toString();
  }

  /// Seed an admin account if there is no admin in the users box.
  static Future<void> seedAdminIfMissing({
    required String phone,
    required String password,
    required String fullName,
  }) async {
    final box = HiveService.userBox();

    final hasAdmin = box.values.any((u) => u.role == UserRole.admin);
    if (hasAdmin) return;

    final cleanPhone = phone.trim();
    final cleanName = fullName.trim();

    final phoneTaken = box.values.any((u) => u.phone == cleanPhone);
    if (phoneTaken) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final admin = User(
      id: id,
      fullName: cleanName,
      phone: cleanPhone,
      passwordHash: hashPassword(password),
      role: UserRole.admin,
      stationName: null,
      createdAt: DateTime.now(),
    );

    await box.put(id, admin);
  }

  static bool _requiresStation(UserRole role) {
    return role == UserRole.staff || role == UserRole.deskCargoOfficer;
  }

  static Future<User?> register({
    required String fullName,
    required String phone,
    required String password,
    required UserRole role,
    String? stationName,
  }) async {
    final box = HiveService.userBox();

    final cleanPhone = phone.trim();
    final cleanName = fullName.trim();
    final cleanStation = stationName?.trim();

    // Station rule: required for staff + deskCargoOfficer only
    if (_requiresStation(role)) {
      if (cleanStation == null || cleanStation.isEmpty) return null;
    } else {
      stationName = null;
    }

    // Only admin can create non-sender accounts
    if (role != UserRole.sender && Session.currentRole != UserRole.admin) {
      return null;
    }

    // Block creating admin via this method (admin created only via seed or other secure flow)
    if (role == UserRole.admin) {
      return null;
    }

    final exists = box.values.any((u) => u.phone == cleanPhone);
    if (exists) return null;

    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final user = User(
      id: id,
      fullName: cleanName,
      phone: cleanPhone,
      passwordHash: hashPassword(password),
      role: role,
      stationName: _requiresStation(role) ? cleanStation : null,
      createdAt: DateTime.now(),
    );

    await box.put(id, user);
    return user;
  }

  static Future<User?> login({
    required String phone,
    required String password,
    required UserRole role,
  }) async {
    final box = HiveService.userBox();
    final cleanPhone = phone.trim();

    try {
      final user = box.values.firstWhere(
        (u) => u.phone == cleanPhone && u.role == role,
      );

      final hash = hashPassword(password);
      if (user.passwordHash != hash) return null;

      return user;
    } catch (_) {
      return null;
    }
  }

  static Future<User?> loginByPhonePassword({
    required String phone,
    required String password,
  }) async {
    final box = HiveService.userBox();
    final cleanPhone = phone.trim();

    try {
      final user = box.values.firstWhere((u) => u.phone == cleanPhone);

      final hash = hashPassword(password);
      if (user.passwordHash != hash) return null;

      return user;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> adminResetPassword({
    required String userId,
    required String newPassword,
  }) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return false;

    final box = HiveService.userBox();
    final user = box.get(userId);
    if (user == null) return false;

    final updated = User(
      id: user.id,
      fullName: user.fullName,
      phone: user.phone,
      passwordHash: hashPassword(newPassword),
      role: user.role,
      stationName: user.stationName,
      createdAt: user.createdAt,
    );

    await box.put(userId, updated);
    return true;
  }

  static Future<bool> adminUpdateUserStation({
    required String userId,
    required String? stationName,
  }) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return false;

    final box = HiveService.userBox();
    final user = box.get(userId);
    if (user == null) return false;

    // Allow station for staff + desk cargo officer only
    if (user.role != UserRole.staff && user.role != UserRole.deskCargoOfficer) {
      return false;
    }

    final clean = stationName?.trim();
    if (clean == null || clean.isEmpty) return false;

    final updated = User(
      id: user.id,
      fullName: user.fullName,
      phone: user.phone,
      passwordHash: user.passwordHash,
      role: user.role,
      stationName: clean,
      createdAt: user.createdAt,
    );

    await box.put(userId, updated);
    return true;
  }
}
