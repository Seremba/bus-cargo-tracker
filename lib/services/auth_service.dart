import 'dart:convert';
import 'dart:math';
import 'package:bus_cargo_tracker/models/sync_event_type.dart';
import 'package:crypto/crypto.dart';

import '../models/user.dart';
import '../models/user_role.dart';
import 'hive_service.dart';
import 'phone_normalizer.dart';
import 'role_guard.dart';
import 'sync_service.dart';

class AuthService {
  //
  // 100,000 rounds makes brute-force ~100,000x more expensive than plain
  // SHA-256 while adding only ~15 ms on a low-end Android device at login.
  //
  // Salt is a 16-byte hex string stored on the User model (field 10).
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

  static String _hashWithSalt(String password, String salt) {
    List<int> bytes = utf8.encode('$salt:${password.trim()}');
    for (int i = 0; i < _hashRounds; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return '$_hashVersion:${base64.encode(bytes)}';
  }

  static String _legacyHash(String password) {
    final bytes = utf8.encode(password.trim());
    return sha256.convert(bytes).toString();
  }

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

  // ── Sync payload helper ────────────────────────────────────────────────────

  /// Builds the sync payload for a user. Intentionally excludes
  /// passwordHash and passwordSalt — credentials never leave the device.
  static Map<String, dynamic> _userSyncPayload(User user) {
    return {
      'userId': user.id,
      'fullName': user.fullName,
      'phone': user.phone,
      'role': user.role.name,
      'stationName': user.stationName ?? '',
      'assignedRouteId': user.assignedRouteId ?? '',
      'assignedRouteName': user.assignedRouteName ?? '',
      'phoneVerified': user.phoneVerified,
      'createdAt': user.createdAt.toIso8601String(),
    };
  }

  // ── Public helpers ─────────────────────────────────────────────────────────

  static User? getUserById(String id) {
    final box = HiveService.userBox();
    return box.get(id);
  }

  // ── Seed admin ─────────────────────────────────────────────────────────────

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
      phoneVerified: true,
    );

    await box.put(id, admin);

    // Phase 6: sync seeded admin so other devices know this user exists.
    // Credentials are never included in the payload.
    try {
      await SyncService.enqueue(
        type: SyncEventType.userCreated,
        aggregateType: 'user',
        aggregateId: admin.id,
        actorUserId: admin.id,
        payload: _userSyncPayload(admin),
        aggregateVersion: 1,
      );
    } catch (_) {
      // Local-first: user exists locally even if sync queueing fails.
    }
  }

  // ── Role helpers ───────────────────────────────────────────────────────────

  static bool _requiresStation(UserRole role) {
    return role == UserRole.staff || role == UserRole.deskCargoOfficer;
  }

  static bool _requiresAssignedRoute(UserRole role) {
    return role == UserRole.driver;
  }

  // ── Register sender ────────────────────────────────────────────────────────

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
      phoneVerified: false,
    );
  }

  // ── Admin create user ──────────────────────────────────────────────────────

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
      phoneVerified: true,
    );
  }

  // ── Core register ──────────────────────────────────────────────────────────

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

    // Phase 6: sync new user so other devices can authenticate them.
    // Credentials (passwordHash, passwordSalt) are never included.
    try {
      await SyncService.enqueue(
        type: SyncEventType.userCreated,
        aggregateType: 'user',
        aggregateId: user.id,
        actorUserId: user.id,
        payload: _userSyncPayload(user),
        aggregateVersion: 1,
      );
    } catch (_) {
      // Local-first: user exists locally even if sync queueing fails.
    }

    return user;
  }

  // ── Login — with legacy hash migration ────────────────────────────────────

  static Future<bool> _verifyAndMigrate(User user, String password) async {
    final stored = user.passwordHash;

    if (stored.startsWith('$_hashVersion:')) {
      final salt = user.passwordSalt ?? '';
      if (salt.isEmpty) return false;
      return _hashWithSalt(password, salt) == stored;
    }

    if (_legacyHash(password) != stored) return false;

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

  // ── Admin password reset ───────────────────────────────────────────────────

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

    // Phase 6: sync the profile update (credentials excluded).
    // Password hash is intentionally not included — each device keeps
    // its own credentials. This event only updates profile metadata.
    try {
      await SyncService.enqueue(
        type: SyncEventType.userUpdated,
        aggregateType: 'user',
        aggregateId: updated.id,
        actorUserId: updated.id,
        payload: _userSyncPayload(updated),
        aggregateVersion: 2,
      );
    } catch (_) {}

    return true;
  }

  // ── Admin update station ───────────────────────────────────────────────────

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

    // Phase 6: sync station update so other devices reflect the new assignment.
    try {
      await SyncService.enqueue(
        type: SyncEventType.userUpdated,
        aggregateType: 'user',
        aggregateId: updated.id,
        actorUserId: updated.id,
        payload: _userSyncPayload(updated),
        aggregateVersion: 2,
      );
    } catch (_) {}

    return true;
  }

  // ── Admin update driver route ──────────────────────────────────────────────

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

    // Phase 6: sync route assignment so driver's new route is visible
    // on all devices immediately.
    try {
      await SyncService.enqueue(
        type: SyncEventType.userUpdated,
        aggregateType: 'user',
        aggregateId: updated.id,
        actorUserId: updated.id,
        payload: _userSyncPayload(updated),
        aggregateVersion: 2,
      );
    } catch (_) {}

    return true;
  }

  // ── S3 groundwork — mark phone verified ───────────────────────────────────

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

    // Phase 6: sync phone verification status.
    try {
      await SyncService.enqueue(
        type: SyncEventType.userUpdated,
        aggregateType: 'user',
        aggregateId: updated.id,
        actorUserId: updated.id,
        payload: _userSyncPayload(updated),
        aggregateVersion: 2,
      );
    } catch (_) {}
  }

 
  static Future<void> applyUserSyncEvent(
    Map<String, dynamic> payload,
  ) async {
    final box = HiveService.userBox();

    final userId = (payload['userId'] ?? '').toString().trim();
    if (userId.isEmpty) return;

    final fullName = (payload['fullName'] ?? '').toString().trim();
    final phone = (payload['phone'] ?? '').toString().trim();
    final roleRaw = (payload['role'] ?? '').toString().trim();
    final stationName = (payload['stationName'] ?? '').toString().trim();
    final assignedRouteId =
        (payload['assignedRouteId'] ?? '').toString().trim();
    final assignedRouteName =
        (payload['assignedRouteName'] ?? '').toString().trim();
    final phoneVerified = (payload['phoneVerified'] as bool?) ?? false;
    final createdAtRaw = (payload['createdAt'] ?? '').toString().trim();

    if (fullName.isEmpty || phone.isEmpty || roleRaw.isEmpty) return;

    UserRole role;
    try {
      role = UserRole.values.byName(roleRaw);
    } catch (_) {
      return;
    }

    final existing = box.get(userId);

    if (existing != null) {
      // User exists locally — never overwrite a real password with a shell.
      // A real password hash always starts with 'v2:' (salted) or is a
      // 64-char hex string (legacy unsalted). An empty hash = shell only.
      final hasRealPassword = existing.passwordHash.trim().isNotEmpty;

      if (hasRealPassword) {
        // Only update non-credential profile metadata.
        // Credentials stay exactly as set locally — never touched by sync.
        final updated = User(
          id: existing.id,
          fullName: fullName,
          phone: phone,
          passwordHash: existing.passwordHash, // never overwrite
          passwordSalt: existing.passwordSalt, // never overwrite
          role: role,
          stationName: stationName.isEmpty ? existing.stationName : stationName,
          createdAt: existing.createdAt,
          photoPath: existing.photoPath,
          assignedRouteId: assignedRouteId.isEmpty
              ? existing.assignedRouteId
              : assignedRouteId,
          assignedRouteName: assignedRouteName.isEmpty
              ? existing.assignedRouteName
              : assignedRouteName,
          phoneVerified: phoneVerified,
        );
        await box.put(userId, updated);
      } else {
        // Shell exists (empty password) — safe to update everything
        // since there are no real credentials to protect.
        final updated = User(
          id: existing.id,
          fullName: fullName,
          phone: phone,
          passwordHash: existing.passwordHash,
          passwordSalt: existing.passwordSalt,
          role: role,
          stationName: stationName.isEmpty ? existing.stationName : stationName,
          createdAt: existing.createdAt,
          photoPath: existing.photoPath,
          assignedRouteId: assignedRouteId.isEmpty
              ? existing.assignedRouteId
              : assignedRouteId,
          assignedRouteName: assignedRouteName.isEmpty
              ? existing.assignedRouteName
              : assignedRouteName,
          phoneVerified: phoneVerified,
        );
        await box.put(userId, updated);
      }
      return;
    }

    // New user from remote — create a shell with no password.
    // They cannot log in until admin resets their password locally,
    // but they are visible in user lists and role guards recognise their role.
    final createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();

    final shell = User(
      id: userId,
      fullName: fullName,
      phone: phone,
      passwordHash: '', // no credentials until set locally
      passwordSalt: null,
      role: role,
      stationName: stationName.isEmpty ? null : stationName,
      createdAt: createdAt,
      assignedRouteId: assignedRouteId.isEmpty ? null : assignedRouteId,
      assignedRouteName: assignedRouteName.isEmpty ? null : assignedRouteName,
      phoneVerified: phoneVerified,
    );

    await box.put(userId, shell);
  }
}