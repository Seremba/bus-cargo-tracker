import 'dart:convert';
import 'package:http/http.dart' as http;
import 'phone_normalizer.dart';

/// Routes all Twilio Verify OTP operations through the Cloudflare Worker.
/// Credentials (TWILIO_VERIFY_SID, TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
/// never leave the Worker — the Flutter app only sends the phone + code.
class TwilioVerifyService {
  TwilioVerifyService._();

  static const String _workerBase =
      'https://bus-cargo-sync.pserembae.workers.dev';

  static const String _syncApiKey =
      String.fromEnvironment('SYNC_API_KEY', defaultValue: '');

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Api-Key': _syncApiKey,
      };

  // ── Send OTP ──────────────────────────────────────────────────────────────

  /// Sends a 6-digit OTP to [phone] via Twilio Verify.
  ///
  /// [phone] may be any supported format — it is normalised to E.164 here.
  /// Returns null on success, or an error string on failure.
  static Future<String?> sendOtp(String phone) async {
    final e164 = _toE164(phone);
    if (e164 == null) {
      return 'Invalid phone number: $phone';
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_workerBase/verify/start'),
            headers: _headers,
            body: jsonEncode({'to': e164}),
          )
          .timeout(const Duration(seconds: 20));

      final json = _parseJson(response.body);

      if (response.statusCode == 200) {
        final status = (json['status'] ?? '').toString();
        if (status == 'pending') return null; // success
        return 'Unexpected Verify status: $status';
      }

      final errCode = (json['code'] ?? '').toString();
      final errMsg = (json['error'] ?? 'Unknown error').toString();
      final twilioMsg = (json['twilioMessage'] ?? '').toString();
      final detail = twilioMsg.isNotEmpty ? ' — $twilioMsg' : '';
      return '[$errCode] $errMsg$detail';
    } catch (e) {
      return 'Verify send failed: $e';
    }
  }

  // ── Check OTP ─────────────────────────────────────────────────────────────

  /// Checks the [code] entered by the user for [phone].
  ///
  /// Returns [VerifyCheckResult.approved] on success,
  /// [VerifyCheckResult.pending] on wrong code,
  /// [VerifyCheckResult.notFound] if expired or already used,
  /// [VerifyCheckResult.error] on network/server failure.
  static Future<VerifyCheckResult> checkOtp({
    required String phone,
    required String code,
  }) async {
    final e164 = _toE164(phone);
    if (e164 == null) return VerifyCheckResult.error;

    try {
      final response = await http
          .post(
            Uri.parse('$_workerBase/verify/check'),
            headers: _headers,
            body: jsonEncode({'to': e164, 'code': code.trim()}),
          )
          .timeout(const Duration(seconds: 20));

      final json = _parseJson(response.body);

      if (response.statusCode == 200) {
        final status = (json['status'] ?? '').toString();
        switch (status) {
          case 'approved':
            return VerifyCheckResult.approved;
          case 'pending':
            return VerifyCheckResult.pending; // wrong code
          case 'not_found':
            return VerifyCheckResult.notFound;
          default:
            return VerifyCheckResult.error;
        }
      }

      return VerifyCheckResult.error;
    } catch (e) {
      return VerifyCheckResult.error;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Map<String, dynamic> _parseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Converts any supported format to E.164.
  /// Mirrors TwilioService._toE164 — kept local to avoid coupling.
  static String? _toE164(String raw) {
    // First try PhoneNormalizer (handles UG/KE/SS/RW/CD formats)
    final normalized = PhoneNormalizer.normalizeForMessaging(raw);
    if (normalized.isNotEmpty) return normalized;

    // Fallback: strip whitespace/dashes, check if already E.164
    final p = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.startsWith('+') && p.length >= 10) return p;

    return null;
  }
}

/// Result of a [TwilioVerifyService.checkOtp] call.
enum VerifyCheckResult {
  /// OTP correct — verification approved by Twilio.
  approved,

  /// OTP incorrect — verification still pending (user can retry).
  pending,

  /// Verification not found — expired (10 min) or already used.
  notFound,

  /// Network error or server-side failure.
  error,
}