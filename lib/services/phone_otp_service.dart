import 'twilio_verify_service.dart';
import 'auth_service.dart';

/// Handles phone verification OTP for newly registered sender accounts.
///
/// OTP generation, delivery, expiry, and attempt-counting are all managed
/// by Twilio Verify. No OTP is stored locally in Hive.
class PhoneOtpService {
  PhoneOtpService._();

  /// Exposed so OtpVerificationScreen can show a countdown timer.
  /// Twilio Verify OTPs expire after 10 minutes by default.
  static const int otpTtlSeconds = 600;

  /// Sends a verification OTP to [phone] via Twilio Verify.
  ///
  /// Safe to call on both first send and resend — Twilio cancels
  /// any previous pending verification for the same number automatically.
  ///
  /// Throws [StateError] if the phone cannot be normalised to E.164.
  static Future<void> generateAndSend({
    required String userId,
    required String phone,
  }) async {
    final err = await TwilioVerifyService.sendOtp(phone);
    if (err != null) {
      throw StateError('PhoneOtpService: Verify send failed — $err');
    }
  }

  /// Verifies the OTP entered by the user.
  ///
  /// On success, marks the user's phone as verified in Hive and returns
  /// [OtpVerifyResult.success].
  static Future<OtpVerifyResult> verifyOtp({
    required String userId,
    required String phone,
    required String otp,
  }) async {
    final result = await TwilioVerifyService.checkOtp(
      phone: phone,
      code: otp.trim(),
    );

    switch (result) {
      case VerifyCheckResult.approved:
        await AuthService.markPhoneVerified(userId);
        return OtpVerifyResult.success;

      case VerifyCheckResult.pending:
        // Wrong code — Twilio tracks attempt count server-side.
        // After too many wrong attempts Twilio returns 'pending' until
        // the verification expires; we surface this as wrongOtp.
        return OtpVerifyResult.wrongOtp;

      case VerifyCheckResult.notFound:
        // Expired (>10 min) or already used.
        return OtpVerifyResult.expired;

      case VerifyCheckResult.error:
        // Network / server failure — treat as notFound so the UI
        // prompts the user to resend.
        return OtpVerifyResult.notFound;
    }
  }

  /// Always returns true — Twilio Verify manages expiry server-side.
  /// Kept for UI compatibility (OtpVerificationScreen checks this before
  /// showing the resend button).
  static bool hasValidOtp(String userId) => true;
}

/// Result of an OTP verification attempt.
enum OtpVerifyResult { success, wrongOtp, expired, tooManyAttempts, notFound }