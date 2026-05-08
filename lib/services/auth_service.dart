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

  // ── Phone suffix matching ──────────────────────────────────────────────────
  static String _phoneSuffix(String phone) {
    final digits = PhoneNormalizer.digitsOnly(phone);
    if (digits.length <= 9) return digits;
    return digits.substring(digits.length - 9);
  }

  static bool _phonesMatch(String phoneA, String phoneB) {
    final a = _phoneSuffix(phoneA);
    final b = _phoneSuffix(phoneB);
    if (a.isEmpty || b.isEmpty) return false;
    return a == b;
  }

  // ── Sync payload helper ────────────────────────────────────────────────────

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

    final phoneTaken = box.values.any((u) => _phonesMatch(u.phone, cleanPhone));
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

    try {
      await SyncService.enqueue(
        type: SyncEventType.userCreated,
        aggregateType: 'user',
        aggregateId: admin.id,
        actorUserId: admin.id,
        payload: _userSyncPayload(admin),
        aggregateVersion: 1,
      );
    } catch (_) {}
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
      // phoneVerified is false — user must complete OTP on first login
      // to set their own password before being marked verified.
      phoneVerified: false,
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

    // Exclude deleted users from the phone conflict check — a deleted user's
    // phone number can be re-registered under a new user ID.
    final exists = box.values
        .where((u) => !_isDeleted(u.id))
        .any((u) => _phonesMatch(u.phone, cleanPhone));
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

    try {
      await SyncService.enqueue(
        type: SyncEventType.userCreated,
        aggregateType: 'user',
        aggregateId: user.id,
        actorUserId: user.id,
        payload: _userSyncPayload(user),
        aggregateVersion: 1,
      );
    } catch (_) {}

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
    if (PhoneNormalizer.digitsOnly(phone).isEmpty) return null;

    try {
      final user = box.values.firstWhere(
        (u) => _phonesMatch(u.phone, phone) && u.role == role,
      );
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

    if (PhoneNormalizer.digitsOnly(phone).isEmpty) return null;

    final candidates = box.values
        .where((u) => _phonesMatch(u.phone, phone))
        .toList();

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      if (a.role == UserRole.admin) return -1;
      if (b.role == UserRole.admin) return 1;
      return 0;
    });

    for (final user in candidates) {
      if (await _verifyAndMigrate(user, password)) return user;
    }

    return null;
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

  // ── Mark phone verified ────────────────────────────────────────────────────

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

  // ── Apply user sync event ──────────────────────────────────────────────────

  static Future<void> applyUserSyncEvent(Map<String, dynamic> payload) async {
    final box = HiveService.userBox();

    final userId = (payload['userId'] ?? '').toString().trim();
    if (userId.isEmpty) return;

    // Don't resurrect deleted users — their old userCreated events
    // should be ignored after deletion.
    if (_isDeleted(userId)) return;

    final fullName = (payload['fullName'] ?? '').toString().trim();
    final phone = (payload['phone'] ?? '').toString().trim();
    final roleRaw = (payload['role'] ?? '').toString().trim();
    final stationName = (payload['stationName'] ?? '').toString().trim();
    final assignedRouteId = (payload['assignedRouteId'] ?? '').toString().trim();
    final assignedRouteName = (payload['assignedRouteName'] ?? '').toString().trim();
    final phoneVerified = (payload['phoneVerified'] as bool?) ?? false;
    final awaitingReassignment = (payload['awaitingReassignment'] as bool?) ?? false;
    final createdAtRaw = (payload['createdAt'] ?? '').toString().trim();

    if (fullName.isEmpty || phone.isEmpty || roleRaw.isEmpty) return;

    UserRole role;
    try {
      role = UserRole.values.byName(roleRaw);
    } catch (_) {
      return;
    }

    // ── Admin guard ────────────────────────────────────────────────────────
    if (role == UserRole.admin) {
      final existing = box.get(userId);
      if (existing == null) return;
      final hasRealPassword = existing.passwordHash.trim().isNotEmpty;
      if (!hasRealPassword) return;
      final updated = User(
        id: existing.id,
        fullName: fullName,
        phone: phone,
        passwordHash: existing.passwordHash,
        passwordSalt: existing.passwordSalt,
        role: existing.role,
        stationName: existing.stationName,
        createdAt: existing.createdAt,
        photoPath: existing.photoPath,
        assignedRouteId: existing.assignedRouteId,
        assignedRouteName: existing.assignedRouteName,
        phoneVerified: phoneVerified,
      );
      await box.put(userId, updated);
      return;
    }

    final existing = box.get(userId);

    if (existing != null) {
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
        awaitingReassignment: awaitingReassignment,
        routeHistory: existing.routeHistory,
      );
      await box.put(userId, updated);
      return;
    }

    final createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();

    final shell = User(
      id: userId,
      fullName: fullName,
      phone: phone,
      passwordHash: '',
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

  // ── Deleted user tombstone ─────────────────────────────────────────────────
  // Tracks user IDs that have been deleted so their old userCreated sync
  // events don't resurrect them when replayed on other devices.

  static const _deletedIdsKey = 'deletedUserIds';

  static Set<String> _deletedIds() {
    final box = HiveService.appSettingsBox();
    final raw = box.get(_deletedIdsKey);
    if (raw is List) return raw.cast<String>().toSet();
    return {};
  }

  static Future<void> _markDeleted(String userId) async {
    final box = HiveService.appSettingsBox();
    final ids = _deletedIds()..add(userId);
    await box.put(_deletedIdsKey, ids.toList());
  }

  /// Public — called when admin deletes a user locally so the tombstone
  /// is set immediately without waiting for the sync event to come back.
  static Future<void> markUserDeleted(String userId) => _markDeleted(userId);

  static bool _isDeleted(String userId) => _deletedIds().contains(userId);

  static Future<void> applyUserDeletedSyncEvent(
    Map<String, dynamic> payload,
  ) async {
    final userId = (payload['userId'] ?? '').toString().trim();
    if (userId.isEmpty) return;

    await _markDeleted(userId);

    final box = HiveService.userBox();
    final user = box.get(userId);
    if (user == null) return;

    if (user.role == UserRole.admin) return;

    await box.delete(userId);
  }
}