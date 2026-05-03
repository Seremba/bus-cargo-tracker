import 'dart:convert';
import 'package:http/http.dart' as http;
import 'phone_normalizer.dart';

/// Routes all SMS sends through the Cloudflare Worker /sms endpoint.
/// Twilio credentials (accountSid, authToken, from) never leave the Worker.
/// The Flutter app only sends the recipient phone and message body.
class TwilioService {
  TwilioService._();

  static const String _workerBase =
      'https://bus-cargo-sync.pserembae.workers.dev';

  static const String _syncApiKey = String.fromEnvironment(
    'SYNC_API_KEY',
    defaultValue: '',
  );

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-Api-Key': _syncApiKey,
  };

  /// Sends an SMS via the Worker /sms endpoint.
  /// Returns null on success, or an error string on failure.
  static Future<String?> sendSms({
    required String toPhone,
    required String body,
  }) async {
    final e164 = _toE164(toPhone);
    if (e164 == null) return 'Invalid phone number: $toPhone';

    if (_syncApiKey.isEmpty) return 'Sync API key not configured.';

    try {
      final response = await http
          .post(
            Uri.parse('$_workerBase/sms'),
            headers: _headers,
            body: jsonEncode({'to': e164, 'body': body}),
          )
          .timeout(const Duration(seconds: 15));

      // ignore: avoid_print
      print('[TwilioService] status=${response.statusCode} body=${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['ok'] == true) return null; // success
        return 'Worker rejected SMS: ${json['error'] ?? 'unknown'}';
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final errCode    = (json['code']         ?? '').toString();
      final errMsg     = (json['error']        ?? 'Unknown error').toString();
      final twilioMsg  = (json['twilioMessage'] ?? '').toString();
      final detail = twilioMsg.isNotEmpty ? ' — $twilioMsg' : '';
      return '[$errCode] $errMsg$detail';
    } catch (e) {
      return 'SMS send failed: $e';
    }
  }

  /// Returns true if the phone number is a Uganda number (+256).
  static bool isUgandaNumber(String phone) {
    final e164 = _toE164(phone);
    if (e164 == null) return false;
    return e164.startsWith('+256');
  }

  /// Converts any supported phone format to E.164.
  /// Delegates to PhoneNormalizer then adds the + prefix.
  static String? _toE164(String raw) {
    // PhoneNormalizer returns digits only — prepend + for E.164
    final normalized = PhoneNormalizer.normalizeForMessaging(raw);
    if (normalized.isNotEmpty) return '+$normalized';

    // Fallback for formats PhoneNormalizer doesn't handle
    var p = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.isEmpty) return null;
    if (p.startsWith('+') && p.length >= 10) return p;
    if (p.startsWith('0') && p.length == 10) return '+256${p.substring(1)}';
    if (p.length == 9 && (p.startsWith('7') || p.startsWith('3'))) {
      return '+256$p';
    }
    if (p.length >= 10 && p.length <= 15 && !p.startsWith('0')) return '+$p';
    return null;
  }
}