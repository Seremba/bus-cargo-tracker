import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

import 'auth_service.dart';
import 'hive_service.dart';
import 'outbound_message_service.dart';
import 'phone_normalizer.dart';

class PhoneOtpService {
  PhoneOtpService._();

  static const int otpTtlSeconds = 600; // 10 minutes
  static const int maxAttempts = 3;

  static String _storageKey(String userId) => 'phone_otp:$userId';

  static String _generateOtp() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  static String _hashOtp(String userId, String otp) {
    final salted = '$userId:$otp';
    return sha256.convert(utf8.encode(salted)).toString();
  }

  static String _buildMessage(String otp, String phone) {
    return 'UNEX LOGISTICS\n'
        'Your verification code is: $otp\n'
        'Valid for ${otpTtlSeconds ~/ 60} minutes.\n'
        'Do not share this code.';
  }

  /// Generates a new OTP, stores it, and sends via AT SMS.
  /// Safe to call on both first send and resend.
  static Future<void> generateAndSend({
    required String userId,
    required String phone,
  }) async {
    final otp = _generateOtp();
    final hash = _hashOtp(userId, otp);
    final expiresAt = DateTime.now().add(Duration(seconds: otpTtlSeconds));

    final entry = jsonEncode({
      'hash': hash,
      'expiresAt': expiresAt.toIso8601String(),
      'attempts': 0,
    });

    final box = HiveService.appSettingsBox();
    await box.put(_storageKey(userId), entry);

    // Normalize phone for SMS delivery
    final normalizedPhone = PhoneNormalizer.normalizeForMessaging(phone);
    if (normalizedPhone.isEmpty) {
      throw StateError(
        'Cannot send OTP: phone number is not message-ready. raw="$phone"',
      );
    }

    await OutboundMessageService.queue(
      toPhone: normalizedPhone,
      channel: 'sms',
      body: _buildMessage(otp, normalizedPhone),
      propertyKey: userId, // userId as audit reference — no property involved
    );
  }

  /// Verifies the entered OTP against the stored hash.
  static Future<OtpVerifyResult> verifyOtp({
    required String userId,
    required String otp,
  }) async {
    final box = HiveService.appSettingsBox();
    final raw = box.get(_storageKey(userId)) as String?;

    if (raw == null || raw.trim().isEmpty) {
      return OtpVerifyResult.notFound;
    }

    Map<String, dynamic> entry;
    try {
      entry = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return OtpVerifyResult.notFound;
    }

    final storedHash = (entry['hash'] ?? '').toString();
    final expiresAtRaw = (entry['expiresAt'] ?? '').toString();
    final attempts = (entry['attempts'] as num?)?.toInt() ?? 0;

    // Check expiry
    final expiresAt = DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
      await _clearOtp(userId);
      return OtpVerifyResult.expired;
    }

    // Check attempts
    if (attempts >= maxAttempts) {
      return OtpVerifyResult.tooManyAttempts;
    }

    // Verify hash
    final inputHash = _hashOtp(userId, otp.trim());
    if (inputHash != storedHash) {
      // Increment attempts
      entry['attempts'] = attempts + 1;
      await box.put(_storageKey(userId), jsonEncode(entry));
      return OtpVerifyResult.wrongOtp;
    }

    // Success — clear OTP and mark phone verified
    await _clearOtp(userId);
    await AuthService.markPhoneVerified(userId);

    return OtpVerifyResult.success;
  }

  /// Checks whether a valid (non-expired) OTP exists for this user.
  static bool hasValidOtp(String userId) {
    final box = HiveService.appSettingsBox();
    final raw = box.get(_storageKey(userId)) as String?;
    if (raw == null) return false;

    try {
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final expiresAtRaw = (entry['expiresAt'] ?? '').toString();
      final expiresAt = DateTime.tryParse(expiresAtRaw);
      if (expiresAt == null) return false;
      return DateTime.now().isBefore(expiresAt);
    } catch (_) {
      return false;
    }
  }

  static Future<void> _clearOtp(String userId) async {
    final box = HiveService.appSettingsBox();
    await box.delete(_storageKey(userId));
  }
}

/// Result of an OTP verification attempt.
enum OtpVerifyResult { success, wrongOtp, expired, tooManyAttempts, notFound }
