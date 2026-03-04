import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../models/user.dart';
import '../models/user_role.dart';
import 'hive_service.dart';
import 'phone_normalizer.dart';
import 'role_guard.dart';

class AuthService {
  static String hashPassword(String password) {
    final bytes = utf8.encode(password.trim());
    return sha256.convert(bytes).toString();
  }

  static User? getUserById(String id) {
    final box = HiveService.userBox();
    return box.get(id);
  }

  static Future<void> seedAdminIfMissing({
    required String phone,
    required String password,
    required String fullName,
  }) async {
    final box = HiveService.userBox();

    final hasAdmin = box.values.any((u) => u.role == UserRole.admin);
    if (hasAdmin) return;

    final cleanName = fullName.trim();
    final cleanPhone = PhoneNormalizer.normalizeForStorage(phone);

    if (cleanName.isEmpty) return;
    if (cleanPhone.isEmpty) return;

    // Prevent duplicate by digits-only identity
    final phoneTaken = box.values.any(
      (u) =>
          PhoneNormalizer.digitsOnly(u.phone) ==
          PhoneNormalizer.digitsOnly(cleanPhone),
    );
    if (phoneTaken) return;

    final id = DateTime.now().microsecondsSinceEpoch.toString();

    final admin = User(
      id: id,
      fullName: cleanName,
      phone: cleanPhone, // ✅ store digits-only as typed (no forced 256)
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

  static Future<User?> registerSender({
    required String fullName,
    required String phone,
    required String password,
  }) async {
    return register(
      fullName: fullName,
      phone: phone,
      password: password,
      role: UserRole.sender,
      stationName: null,
      requireAdminForNonSender: false,
      allowAdminCreation: false,
    );
  }

  static Future<User?> adminCreateUser({
    required String fullName,
    required String phone,
    required String password,
    required UserRole role,
    String? stationName,
  }) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return null;

    // block creating admin from UI
    if (role == UserRole.admin) return null;

    return register(
      fullName: fullName,
      phone: phone,
      password: password,
      role: role,
      stationName: stationName,
      requireAdminForNonSender: false,
      allowAdminCreation: false,
    );
  }

  static Future<User?> register({
    required String fullName,
    required String phone,
    required String password,
    required UserRole role,
    String? stationName,
    bool requireAdminForNonSender = false,

    /// Never allow creating admin through regular registration.
    bool allowAdminCreation = false,
  }) async {
    final box = HiveService.userBox();

    final cleanName = fullName.trim();
    final cleanPhone = PhoneNormalizer.normalizeForStorage(phone);
    final cleanStation = stationName?.trim();

    if (cleanName.isEmpty) return null;
    if (cleanPhone.isEmpty) return null;

    // Block creating admin via this method by default
    if (role == UserRole.admin && !allowAdminCreation) return null;

    // Optional backward-compat guard (prefer adminCreateUser)
    if (requireAdminForNonSender && role != UserRole.sender) {
      if (!RoleGuard.hasRole(UserRole.admin)) return null;
    }

    // Station rule: required for staff + deskCargoOfficer only
    if (_requiresStation(role)) {
      if (cleanStation == null || cleanStation.isEmpty) return null;
    }

    // Prevent duplicates by digits-only identity
    final exists = box.values.any(
      (u) =>
          PhoneNormalizer.digitsOnly(u.phone) ==
          PhoneNormalizer.digitsOnly(cleanPhone),
    );
    if (exists) return null;

    final id = DateTime.now().microsecondsSinceEpoch.toString();

    final user = User(
      id: id,
      fullName: cleanName,
      phone: cleanPhone, // ✅ digits-only stored
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

    final inputDigits = PhoneNormalizer.digitsOnly(phone);
    if (inputDigits.isEmpty) return null;

    try {
      final user = box.values.firstWhere((u) {
        final storedDigits = PhoneNormalizer.digitsOnly(u.phone);
        return storedDigits == inputDigits && u.role == role;
      });

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

    final inputDigits = PhoneNormalizer.digitsOnly(phone);
    if (inputDigits.isEmpty) return null;

    try {
      final user = box.values.firstWhere((u) {
        final storedDigits = PhoneNormalizer.digitsOnly(u.phone);
        return storedDigits == inputDigits;
      });

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
