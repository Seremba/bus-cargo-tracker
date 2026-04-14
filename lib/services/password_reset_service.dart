import '../models/user.dart';
import 'audit_service.dart';
import 'auth_service.dart';
import 'hive_service.dart';
import 'phone_normalizer.dart';
import 'twilio_verify_service.dart';

/// Handles password reset and first-login password setup via Twilio Verify OTP.
///
/// OTP generation, delivery, expiry (10 min), and attempt-counting are all
/// managed by Twilio Verify. Only the verified/unverified flag and the new
/// password are stored locally.
class PasswordResetService {
  PasswordResetService._();

  // ── Policy ────────────────────────────────────────────────────────────────

  /// How long the verified flag is trusted before requiring a re-verify.
  /// Twilio Verify itself expires in 10 min — this is a belt-and-suspenders
  /// guard on the client side in case the user takes a long time on the
  /// set-password screen.
  static const Duration _verifiedSessionTtl = Duration(minutes: 15);

  static String _k(String phoneDigits) => 'PWDRESET:$phoneDigits';

  static String _digitsKey(String rawPhone) =>
      PhoneNormalizer.digitsOnly(rawPhone);

  // ── User lookup ───────────────────────────────────────────────────────────

  /// Finds a user by phone using last-9-digit suffix matching.
  static User? _findUserByPhoneDigits(String phoneDigits) {
    if (phoneDigits.length < 9) return null;
    final inputSuffix = phoneDigits.substring(phoneDigits.length - 9);

    final box = HiveService.userBox();
    for (final u in box.values) {
      if (u is! User) continue;
      final storedDigits = PhoneNormalizer.digitsOnly(u.phone);
      if (storedDigits.length < 9) continue;
      final storedSuffix = storedDigits.substring(storedDigits.length - 9);
      if (storedSuffix == inputSuffix) return u;
    }
    return null;
  }

  // ── Step 1: Request OTP ───────────────────────────────────────────────────

  /// Sends a 6-digit OTP to [rawPhone] via Twilio Verify.
  ///
  /// Validates the phone, looks up the user account, then delegates
  /// delivery entirely to Twilio. No OTP is stored locally.
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
      return const ResetResult(false, 'No account found for that phone number.');
    }

    final err = await TwilioVerifyService.sendOtp(msgPhone);
    if (err != null) {
      await AuditService.log(
        action: 'PWD_RESET_OTP_SEND_FAILED',
        propertyKey: _k(phoneDigits),
        details: 'Twilio Verify send failed: $err — phone=$msgPhone userId=${user.id}',
      );
      return ResetResult(false, 'Could not send OTP: $err');
    }

    // Store a minimal record: just tracks that a send was requested and
    // when, so setNewPassword can enforce the session TTL.
    final box = HiveService.passwordResetBox();
    await box.put(_k(phoneDigits), <String, dynamic>{
      'phoneDigits': phoneDigits,
      'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      'otpVerified': false,
      'verifiedAtMs': 0,
    });

    await AuditService.log(
      action: 'PWD_RESET_OTP_SENT',
      propertyKey: _k(phoneDigits),
      details: 'Twilio Verify OTP sent to=$msgPhone userId=${user.id}',
    );

    return const ResetResult(true, 'OTP sent. Check your SMS.');
  }

  // ── Step 2a: Verify OTP ───────────────────────────────────────────────────

  /// Checks the [otp] entered by the user against Twilio Verify.
  ///
  /// On success, marks the local reset record as verified so
  /// [setNewPassword] can proceed on the next screen.
  static Future<ResetResult> verifyOtpOnly({
    required String rawPhone,
    required String otp,
  }) async {
    final phoneDigits = _digitsKey(rawPhone);
    if (phoneDigits.isEmpty) {
      return const ResetResult(false, 'Phone number is required.');
    }

    final cleanOtp = otp.trim();
    if (cleanOtp.length < 4) {
      return const ResetResult(false, 'Enter the OTP.');
    }

    final user = _findUserByPhoneDigits(phoneDigits);
    if (user == null) {
      return const ResetResult(false, 'No account found for that phone number.');
    }

    final msgPhone = PhoneNormalizer.normalizeForMessaging(rawPhone);
    if (msgPhone.isEmpty) {
      return const ResetResult(false, 'Invalid phone number.');
    }

    final result = await TwilioVerifyService.checkOtp(
      phone: msgPhone,
      code: cleanOtp,
    );

    switch (result) {
      case VerifyCheckResult.approved:
        // Mark verified in local record with timestamp
        final box = HiveService.passwordResetBox();
        final key = _k(phoneDigits);
        final existing = box.get(key);
        final rec = existing != null
            ? Map<String, dynamic>.from(existing as Map)
            : <String, dynamic>{
                'phoneDigits': phoneDigits,
                'sentAtMs': 0,
              };
        rec['otpVerified'] = true;
        rec['verifiedAtMs'] = DateTime.now().millisecondsSinceEpoch;
        await box.put(key, rec);

        await AuditService.log(
          action: 'PWD_RESET_OTP_VERIFIED',
          propertyKey: key,
          details: 'OTP verified via Twilio Verify — userId=${user.id}',
        );
        return const ResetResult(true, 'OTP verified.');

      case VerifyCheckResult.pending:
        // Wrong code — Twilio tracks attempts and locks after 5 wrong tries.
        await AuditService.log(
          action: 'PWD_RESET_OTP_BAD',
          propertyKey: _k(phoneDigits),
          details: 'Wrong OTP entered — userId=${user.id}',
        );
        return const ResetResult(false, 'Incorrect OTP. Try again.');

      case VerifyCheckResult.notFound:
        // Expired (>10 min) or already used.
        return const ResetResult(false, 'OTP expired. Tap "Send OTP" again.');

      case VerifyCheckResult.error:
        return const ResetResult(false, 'Could not verify OTP. Check your connection and try again.');
    }
  }

  // ── Step 2b: Set new password ─────────────────────────────────────────────

  /// Sets [newPassword] for the account associated with [rawPhone].
  ///
  /// Must be called after a successful [verifyOtpOnly]. The verified flag
  /// in the local record must be present and within [_verifiedSessionTtl].
  static Future<ResetResult> setNewPassword({
    required String rawPhone,
    required String newPassword,
  }) async {
    final phoneDigits = _digitsKey(rawPhone);
    if (phoneDigits.isEmpty) {
      return const ResetResult(false, 'Phone number is required.');
    }

    final cleanPass = newPassword.trim();
    if (cleanPass.length < 6) {
      return const ResetResult(false, 'Password must be at least 6 characters.');
    }

    final user = _findUserByPhoneDigits(phoneDigits);
    if (user == null) {
      return const ResetResult(false, 'No account found for that phone number.');
    }

    final box = HiveService.passwordResetBox();
    final key = _k(phoneDigits);
    final rec = box.get(key);

    if (rec == null) {
      return const ResetResult(false, 'Session expired. Please start again.');
    }

    final recMap = Map<String, dynamic>.from(rec as Map);
    final isVerified = (recMap['otpVerified'] as bool?) ?? false;

    if (!isVerified) {
      return const ResetResult(false, 'OTP not verified. Please verify first.');
    }

    // Belt-and-suspenders: enforce client-side session TTL
    final verifiedAtMs = (recMap['verifiedAtMs'] as int?) ?? 0;
    if (verifiedAtMs > 0) {
      final verifiedAt = DateTime.fromMillisecondsSinceEpoch(verifiedAtMs);
      if (DateTime.now().isAfter(verifiedAt.add(_verifiedSessionTtl))) {
        await box.delete(key);
        return const ResetResult(false, 'Session expired. Please start again.');
      }
    }

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

    return const ResetResult(true, 'Password updated successfully.');
  }

  // ── Legacy compat ─────────────────────────────────────────────────────────

  /// Legacy method — kept for backwards compatibility.
  static Future<ResetResult> verifyOtpAndResetPassword({
    required String rawPhone,
    required String otp,
    required String newPassword,
  }) async {
    final verifyResult = await verifyOtpOnly(rawPhone: rawPhone, otp: otp);
    if (!verifyResult.ok) return verifyResult;
    return setNewPassword(rawPhone: rawPhone, newPassword: newPassword);
  }
}

class ResetResult {
  final bool ok;
  final String message;
  const ResetResult(this.ok, this.message);
}