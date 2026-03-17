import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/user.dart';
import 'audit_service.dart';
import 'auth_service.dart';
import 'hive_service.dart';
import 'outbound_message_service.dart';
import 'phone_normalizer.dart';

class PasswordResetService {
  PasswordResetService._();

  // ====== Policy ======
  static const Duration otpExpiry = Duration(minutes: 10);
  static const int maxAttempts = 5;
  static const Duration lockDuration = Duration(minutes: 15);
  static const Duration resendCooldown = Duration(seconds: 60);

  // ====== Device rate limiting (per device/app install) ======
  static const Duration deviceCooldown = Duration(seconds: 30);
  static const Duration deviceWindow = Duration(hours: 1);
  static const int deviceMaxInWindow = 8;

  static const String _deviceRateKey = 'PWDRESET_DEVICE_RATE';

  // ─── OTP hashing ─────────────────────────────────────────────────────────
  // Reset OTPs are short-lived (10 min), stored in a temporary record that
  // is deleted on success or expiry, and already protected by attempt
  // limiting. Plain SHA-256 is sufficient here — no salt needed.
  static String _hashOtp(String otp) {
    return sha256.convert(utf8.encode(otp.trim())).toString();
  }

  // ─────────────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _readDeviceRate() {
    final box = HiveService.appSettingsBox();
    final v = box.get(_deviceRateKey);
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{'windowStartMs': 0, 'count': 0, 'lastMs': 0};
  }

  static Future<void> _writeDeviceRate(Map<String, dynamic> v) async {
    final box = HiveService.appSettingsBox();
    await box.put(_deviceRateKey, v);
  }

  static String _k(String phoneDigits) => 'PWDRESET:$phoneDigits';

  static String _newOtp6() {
    final r = Random.secure();
    return (r.nextInt(900000) + 100000).toString();
  }

  static String _digitsKey(String rawPhone) =>
      PhoneNormalizer.digitsOnly(rawPhone);

  static User? _findUserByPhoneDigits(String phoneDigits) {
    final box = HiveService.userBox();
    for (final u in box.values) {
      if (u is! User) continue;
      final storedDigits = PhoneNormalizer.digitsOnly(u.phone);
      if (storedDigits == phoneDigits) return u;
    }
    return null;
  }

  /// Step 1: Request OTP (queues SMS) and stores reset record in Hive.
  static Future<ResetResult> requestOtp({required String rawPhone}) async {
    final phoneDigits = _digitsKey(rawPhone);
    if (phoneDigits.isEmpty) {
      return const ResetResult(false, 'Phone number is required.');
    }
    if (phoneDigits.length < 9 || phoneDigits.length > 15) {
      return const ResetResult(false, 'Enter a valid phone number.');
    }

    final msgPhone = PhoneNormalizer.normalizeForMessaging(rawPhone);
    if (msgPhone.isEmpty) {
      return const ResetResult(
        false,
        'Enter a message-ready phone (07.. or include country code).',
      );
    }

    final user = _findUserByPhoneDigits(phoneDigits);
    if (user == null) {
      return const ResetResult(
        false,
        'No account found for that phone number.',
      );
    }

    final box = HiveService.passwordResetBox();
    final key = _k(phoneDigits);
    final now = DateTime.now();

    // Device-level rate limiting
    final deviceRate = _readDeviceRate();

    final lastMs = (deviceRate['lastMs'] as int?) ?? 0;
    if (lastMs > 0) {
      final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
      if (now.isBefore(last.add(deviceCooldown))) {
        return const ResetResult(
          false,
          'Please wait a moment before requesting another OTP.',
        );
      }
    }

    final windowStartMs = (deviceRate['windowStartMs'] as int?) ?? 0;
    if (windowStartMs <= 0) {
      deviceRate['windowStartMs'] = now.millisecondsSinceEpoch;
      deviceRate['count'] = 0;
    } else {
      final ws = DateTime.fromMillisecondsSinceEpoch(windowStartMs);
      if (now.isAfter(ws.add(deviceWindow))) {
        deviceRate['windowStartMs'] = now.millisecondsSinceEpoch;
        deviceRate['count'] = 0;
      }
    }

    final currentCount = (deviceRate['count'] as int?) ?? 0;
    if (currentCount >= deviceMaxInWindow) {
      return const ResetResult(
        false,
        'Too many OTP requests. Please try again later.',
      );
    }

    final existing = box.get(key);
    if (existing is Map) {
      final lockedUntilMs = (existing['lockedUntilMs'] as int?) ?? 0;
      if (lockedUntilMs > 0 && now.millisecondsSinceEpoch < lockedUntilMs) {
        return const ResetResult(false, 'Too many attempts. Try again later.');
      }

      final lastSentAtMs = (existing['lastSentAtMs'] as int?) ?? 0;
      if (lastSentAtMs > 0) {
        final last = DateTime.fromMillisecondsSinceEpoch(lastSentAtMs);
        if (now.isBefore(last.add(resendCooldown))) {
          return const ResetResult(
            false,
            'Please wait a moment before requesting another OTP.',
          );
        }
      }
    }

    final otp = _newOtp6();

    await box.put(key, <String, dynamic>{
      'phoneDigits': phoneDigits,
      'otpHash': _hashOtp(otp),
      'createdAtMs': now.millisecondsSinceEpoch,
      'attempts': 0,
      'lockedUntilMs': 0,
      'lastSentAtMs': now.millisecondsSinceEpoch,
    });

    final body =
        '''
Bebeto Cargo

Your password reset OTP is: $otp

Do not share this code with anyone.
This code expires in ${otpExpiry.inMinutes} minutes.
''';

    await OutboundMessageService.queue(
      toPhone: msgPhone,
      channel: 'sms',
      body: body,
      propertyKey: key,
    );

    // Update device rate counters only after successful queue
    final dr = _readDeviceRate();
    final ws2 = (dr['windowStartMs'] as int?) ?? 0;
    if (ws2 <= 0) dr['windowStartMs'] = now.millisecondsSinceEpoch;
    dr['lastMs'] = now.millisecondsSinceEpoch;
    dr['count'] = ((dr['count'] as int?) ?? 0) + 1;
    await _writeDeviceRate(dr);

    await AuditService.log(
      action: 'PWD_RESET_OTP_QUEUED',
      propertyKey: key,
      details:
          'Queued password reset OTP to=$msgPhone (raw="$rawPhone") userId=${user.id}',
    );

    return const ResetResult(true, 'OTP sent. Check your SMS.');
  }

  /// Step 2: Verify OTP and set new password.
  static Future<ResetResult> verifyOtpAndResetPassword({
    required String rawPhone,
    required String otp,
    required String newPassword,
  }) async {
    final phoneDigits = _digitsKey(rawPhone);
    if (phoneDigits.isEmpty) {
      return const ResetResult(false, 'Phone number is required.');
    }

    final cleanOtp = otp.trim();
    if (cleanOtp.length < 4) return const ResetResult(false, 'Enter the OTP.');

    final cleanPass = newPassword.trim();
    if (cleanPass.length < 6) {
      return const ResetResult(
        false,
        'Password must be at least 6 characters.',
      );
    }

    final user = _findUserByPhoneDigits(phoneDigits);
    if (user == null) {
      return const ResetResult(
        false,
        'No account found for that phone number.',
      );
    }

    final box = HiveService.passwordResetBox();
    final key = _k(phoneDigits);
    final rec = box.get(key);

    if (rec is! Map) {
      return const ResetResult(
        false,
        'No reset request found. Tap "Send OTP" first.',
      );
    }

    final now = DateTime.now();
    final lockedUntilMs = (rec['lockedUntilMs'] as int?) ?? 0;
    if (lockedUntilMs > 0 && now.millisecondsSinceEpoch < lockedUntilMs) {
      return const ResetResult(false, 'Too many attempts. Try again later.');
    }

    final createdAtMs = (rec['createdAtMs'] as int?) ?? 0;
    if (createdAtMs <= 0) {
      return const ResetResult(
        false,
        'Reset record invalid. Tap "Send OTP" again.',
      );
    }

    final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
    if (now.isAfter(createdAt.add(otpExpiry))) {
      await box.delete(key);
      await AuditService.log(
        action: 'PWD_RESET_OTP_EXPIRED',
        propertyKey: key,
        details: 'OTP expired; record deleted.',
      );
      return const ResetResult(false, 'OTP expired. Tap "Send OTP" again.');
    }

    var attempts = (rec['attempts'] as int?) ?? 0;
    final expectedHash = (rec['otpHash'] as String?) ?? '';

    if (_hashOtp(cleanOtp) != expectedHash) {
      attempts += 1;

      final updated = Map<String, dynamic>.from(rec);
      updated['attempts'] = attempts;

      if (attempts >= maxAttempts) {
        updated['lockedUntilMs'] = now.add(lockDuration).millisecondsSinceEpoch;
      }

      await box.put(key, updated);

      await AuditService.log(
        action: 'PWD_RESET_OTP_BAD',
        propertyKey: key,
        details: 'Bad OTP attempt=$attempts userId=${user.id}',
      );

      if (attempts >= maxAttempts) {
        return const ResetResult(false, 'Too many attempts. Try again later.');
      }

      return const ResetResult(false, 'Incorrect OTP. Try again.');
    }

    // OTP ok — update password using the new salted hash path
    final (:hash, :salt) = AuthService.hashPasswordWithSalt(cleanPass);

    final updatedUser = User(
      id: user.id,
      fullName: user.fullName,
      phone: user.phone,
      passwordHash: hash,
      passwordSalt: salt,
      role: user.role,
      stationName: user.stationName,
      createdAt: user.createdAt,
      photoPath: user.photoPath,
      assignedRouteId: user.assignedRouteId,
      assignedRouteName: user.assignedRouteName,
      phoneVerified: user.phoneVerified,
    );

    await HiveService.userBox().put(user.id, updatedUser);
    await box.delete(key);

    await AuditService.log(
      action: 'PWD_RESET_SUCCESS',
      propertyKey: key,
      details: 'Password reset success userId=${user.id}',
    );

    return const ResetResult(true, 'Password updated. Please login.');
  }
}

class ResetResult {
  final bool ok;
  final String message;
  const ResetResult(this.ok, this.message);
}
