import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

import '../models/user.dart';
import '../models/user_role.dart';
import 'hive_service.dart';
import 'phone_normalizer.dart';
import 'role_guard.dart';

class AuthService {
  //
  // 100,000 rounds makes brute-force ~100,000x more expensive than plain
  // SHA-256 while adding only ~15 ms on a low-end Android device at login.
  // A full PBKDF2/bcrypt/argon2 implementation is ideal for a future
  // upgrade (Session 10), but this requires zero new dependencies and is a
  // substantial improvement over the previous single-round SHA-256.
  //
  // The salt is a 16-byte hex string stored on the User model (field 10).
  // Format stored in passwordHash: "v2:<base64(hash)>"
  // Legacy hashes (no prefix) are detected and migrated on next login.

  static const int _hashRounds = 100000;
  static const String _hashVersion = 'v2';

  static String _generateSalt() {
    final rng = Random.secure();
    return List.generate(
      16,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Hash a password with a known salt (used at account creation and
  /// on login after migration).
  static String _hashWithSalt(String password, String salt) {
    List<int> bytes = utf8.encode('$salt:${password.trim()}');
    for (int i = 0; i < _hashRounds; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return '$_hashVersion:${base64.encode(bytes)}';
  }

  /// Legacy single-round unsalted hash — used only for migration detection.
  static String _legacyHash(String password) {
    final bytes = utf8.encode(password.trim());
    return sha256.convert(bytes).toString();
  }

  /// Public helper kept for any call sites that previously used
  /// hashPassword(). Now generates a salt internally and returns the
  /// salted hash. Prefer _hashWithSalt() internally where a salt is
  /// already available.
  ///
  /// NOTE: This overload cannot be used for verification because the salt
  /// is generated fresh each call. Use login() / adminResetPassword() for
  /// all verification and re-hash flows.
  static ({String hash, String salt}) hashPasswordWithSalt(String password) {
    final salt = _generateSalt();
    return (hash: _hashWithSalt(password, salt), salt: salt);
  }

  static String _generateUserId() {
    final rng = Random.secure();
    return List.generate(
      16,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  //  Public helpers

  static User? getUserById(String id) {
    final box = HiveService.userBox();
    return box.get(id);
  }

  //  Seed admin

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

    final phoneTaken = box.values.any(
      (u) =>
          PhoneNormalizer.digitsOnly(u.phone) ==
          PhoneNormalizer.digitsOnly(cleanPhone),
    );
    if (phoneTaken) return;

    final id = _generateUserId();
    final salt = _generateSalt();

    final admin = User(
      id: id,
      fullName: cleanName,
      phone: cleanPhone,
      passwordHash: _hashWithSalt(password, salt),
      passwordSalt: salt,
      role: UserRole.admin,
      stationName: null,
      createdAt: DateTime.now(),
      assignedRouteId: null,
      assignedRouteName: null,
      // Admin is created by a human with a known phone — treat as verified
      phoneVerified: true,
    );

    await box.put(id, admin);
  }

  //  Role helpers

  static bool _requiresStation(UserRole role) {
    return role == UserRole.staff || role == UserRole.deskCargoOfficer;
  }

  static bool _requiresAssignedRoute(UserRole role) {
    return role == UserRole.driver;
  }

  //  Register sender

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
      assignedRouteId: null,
      assignedRouteName: null,
      requireAdminForNonSender: false,
      allowAdminCreation: false,
      // S3: sender phone unverified until OTP flow (Session 8)
      phoneVerified: false,
    );
  }

  //  Admin create user

  static Future<User?> adminCreateUser({
    required String fullName,
    required String phone,
    required String password,
    required UserRole role,
    String? stationName,
    String? assignedRouteId,
    String? assignedRouteName,
  }) async {
    if (!RoleGuard.hasRoleVerified(UserRole.admin)) return null;
    if (role == UserRole.admin) return null;

    return register(
      fullName: fullName,
      phone: phone,
      password: password,
      role: role,
      stationName: stationName,
      assignedRouteId: assignedRouteId,
      assignedRouteName: assignedRouteName,
      requireAdminForNonSender: false,
      allowAdminCreation: false,
      // Admin has verified the phone out-of-band — mark verified
      phoneVerified: true,
    );
  }

  //  Core register

  static Future<User?> register({
    required String fullName,
    required String phone,
    required String password,
    required UserRole role,
    String? stationName,
    String? assignedRouteId,
    String? assignedRouteName,
    bool requireAdminForNonSender = false,
    bool allowAdminCreation = false,
    bool phoneVerified = false,
  }) async {
    final box = HiveService.userBox();

    final cleanName = fullName.trim();
    final cleanPhone = PhoneNormalizer.normalizeForStorage(phone);
    final cleanStation = stationName?.trim();
    final cleanAssignedRouteId = assignedRouteId?.trim();
    final cleanAssignedRouteName = assignedRouteName?.trim();

    if (cleanName.isEmpty) return null;
    if (cleanPhone.isEmpty) return null;

    if (role == UserRole.admin && !allowAdminCreation) return null;

    if (requireAdminForNonSender && role != UserRole.sender) {
      if (!RoleGuard.hasRoleVerified(UserRole.admin)) return null;
    }

    if (_requiresStation(role)) {
      if (cleanStation == null || cleanStation.isEmpty) return null;
    }

    if (_requiresAssignedRoute(role)) {
      if (cleanAssignedRouteId == null || cleanAssignedRouteId.isEmpty) {
        return null;
      }
      if (cleanAssignedRouteName == null || cleanAssignedRouteName.isEmpty) {
        return null;
      }
    }

    final exists = box.values.any(
      (u) =>
          PhoneNormalizer.digitsOnly(u.phone) ==
          PhoneNormalizer.digitsOnly(cleanPhone),
    );
    if (exists) return null;

    final id = _generateUserId();
    final salt = _generateSalt();

    final user = User(
      id: id,
      fullName: cleanName,
      phone: cleanPhone,
      passwordHash: _hashWithSalt(password, salt),
      passwordSalt: salt,
      role: role,
      stationName: _requiresStation(role) ? cleanStation : null,
      createdAt: DateTime.now(),
      assignedRouteId: _requiresAssignedRoute(role)
          ? cleanAssignedRouteId
          : null,
      assignedRouteName: _requiresAssignedRoute(role)
          ? cleanAssignedRouteName
          : null,
      phoneVerified: phoneVerified,
    );

    await box.put(id, user);
    return user;
  }

  //  Login — with legacy hash migration

  /// Verifies a password against the stored hash.
  /// Handles two cases:
  ///   • New accounts: stored hash starts with "v2:" — use salted path.
  ///   • Legacy accounts: stored hash has no prefix — use old SHA-256,
  ///     then silently migrate to salted hash on success.
  static Future<bool> _verifyAndMigrate(User user, String password) async {
    final stored = user.passwordHash;

    if (stored.startsWith('$_hashVersion:')) {
      // New salted hash — straightforward comparison
      final salt = user.passwordSalt ?? '';
      if (salt.isEmpty) return false;
      return _hashWithSalt(password, salt) == stored;
    }

    // Legacy unsalted SHA-256 — check then migrate
    if (_legacyHash(password) != stored) return false;

    // Correct password — migrate to salted hash in place
    final salt = _generateSalt();
    final newHash = _hashWithSalt(password, salt);

    final box = HiveService.userBox();
    final updated = User(
      id: user.id,
      fullName: user.fullName,
      phone: user.phone,
      passwordHash: newHash,
      passwordSalt: salt,
      role: user.role,
      stationName: user.stationName,
      createdAt: user.createdAt,
      photoPath: user.photoPath,
      assignedRouteId: user.assignedRouteId,
      assignedRouteName: user.assignedRouteName,
      phoneVerified: user.phoneVerified,
    );
    await box.put(user.id, updated);

    return true;
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

      if (!await _verifyAndMigrate(user, password)) return null;
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

      if (!await _verifyAndMigrate(user, password)) return null;
      return user;
    } catch (_) {
      return null;
    }
  }

  //  Admin password reset

  static Future<bool> adminResetPassword({
    required String userId,
    required String newPassword,
  }) async {
    if (!RoleGuard.hasRoleVerified(UserRole.admin)) return false;

    final box = HiveService.userBox();
    final user = box.get(userId);
    if (user == null) return false;

    final salt = _generateSalt();

    final updated = User(
      id: user.id,
      fullName: user.fullName,
      phone: user.phone,
      passwordHash: _hashWithSalt(newPassword, salt),
      passwordSalt: salt,
      role: user.role,
      stationName: user.stationName,
      createdAt: user.createdAt,
      photoPath: user.photoPath,
      assignedRouteId: user.assignedRouteId,
      assignedRouteName: user.assignedRouteName,
      phoneVerified: user.phoneVerified,
    );

    await box.put(userId, updated);
    return true;
  }

  //  Admin update station

  static Future<bool> adminUpdateUserStation({
    required String userId,
    required String? stationName,
  }) async {
    if (!RoleGuard.hasRoleVerified(UserRole.admin)) return false;

    final box = HiveService.userBox();
    final user = box.get(userId);
    if (user == null) return false;

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
      passwordSalt: user.passwordSalt,
      role: user.role,
      stationName: clean,
      createdAt: user.createdAt,
      photoPath: user.photoPath,
      assignedRouteId: user.assignedRouteId,
      assignedRouteName: user.assignedRouteName,
      phoneVerified: user.phoneVerified,
    );

    await box.put(userId, updated);
    return true;
  }

  //  Admin update driver route

  static Future<bool> adminUpdateDriverAssignedRoute({
    required String userId,
    required String? assignedRouteId,
    required String? assignedRouteName,
  }) async {
    if (!RoleGuard.hasRoleVerified(UserRole.admin)) return false;

    final box = HiveService.userBox();
    final user = box.get(userId);
    if (user == null) return false;

    if (user.role != UserRole.driver) return false;

    final cleanRouteId = assignedRouteId?.trim();
    final cleanRouteName = assignedRouteName?.trim();

    if (cleanRouteId == null || cleanRouteId.isEmpty) return false;
    if (cleanRouteName == null || cleanRouteName.isEmpty) return false;

    final updated = User(
      id: user.id,
      fullName: user.fullName,
      phone: user.phone,
      passwordHash: user.passwordHash,
      passwordSalt: user.passwordSalt,
      role: user.role,
      stationName: user.stationName,
      createdAt: user.createdAt,
      photoPath: user.photoPath,
      assignedRouteId: cleanRouteId,
      assignedRouteName: cleanRouteName,
      phoneVerified: user.phoneVerified,
    );

    await box.put(userId, updated);
    return true;
  }

  //  S3 groundwork — mark phone verified
  //  Called by the OTP verification screen in Session 8.

  static Future<void> markPhoneVerified(String userId) async {
    final box = HiveService.userBox();
    final user = box.get(userId);
    if (user == null) return;
    if (user.phoneVerified) return;

    final updated = User(
      id: user.id,
      fullName: user.fullName,
      phone: user.phone,
      passwordHash: user.passwordHash,
      passwordSalt: user.passwordSalt,
      role: user.role,
      stationName: user.stationName,
      createdAt: user.createdAt,
      photoPath: user.photoPath,
      assignedRouteId: user.assignedRouteId,
      assignedRouteName: user.assignedRouteName,
      phoneVerified: true,
    );

    await box.put(userId, updated);
  }
}
