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
    final e164 = PhoneNormalizer.toE164(toPhone);
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
    final e164 = PhoneNormalizer.toE164(phone);
    if (e164 == null) return false;
    return e164.startsWith('+256');
  }
}