import 'dart:convert';
import 'package:http/http.dart' as http;
import 'twilio_settings_service.dart';

class TwilioService {
  TwilioService._();

  static Future<String?> sendSms({
    required String toPhone,
    required String body,
  }) async {
    final settings = TwilioSettingsService.getOrCreate();

    if (!settings.isConfigured) {
      return 'Twilio not configured.';
    }

    final phone = _toE164(toPhone);
    if (phone == null) {
      return 'Invalid phone number: $toPhone';
    }

    try {
      final credentials = base64Encode(
        utf8.encode('${settings.accountSid}:${settings.authToken}'),
      );

      final response = await http.post(
        Uri.parse(
          'https://api.twilio.com/2010-04-01/Accounts/${settings.accountSid}/Messages.json',
        ),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'To': phone,
          'From': settings.from.trim(),
          'Body': body,
        },
      ).timeout(const Duration(seconds: 15));

      // ignore: avoid_print
      print('[Twilio SMS] status=${response.statusCode} body=${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final status = (json['status'] ?? '').toString().toLowerCase();
        final sid = (json['sid'] ?? '').toString();

        if (status == 'queued' || status == 'sent' || status == 'delivered') {
          // ignore: avoid_print
          print('[Twilio SMS] Success sid=$sid status=$status to=$phone');
          return null; // success
        }

        final errorMessage = (json['message'] ?? json['error_message'] ?? '').toString();
        return 'Twilio rejected: status=$status message=$errorMessage';
      }

      return 'Twilio HTTP ${response.statusCode}: ${response.body}';
    } catch (e) {
      return 'Twilio send failed: $e';
    }
  }

  /// Converts any supported phone format to E.164.
  /// Returns null if the number cannot be safely converted.
  static String? _toE164(String raw) {
    var p = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.isEmpty) return null;

    // Already E.164
    if (p.startsWith('+') && p.length >= 10) return p;

    // Uganda: 07XXXXXXXX → +2567XXXXXXXX
    if (p.startsWith('0') && p.length == 10) return '+256${p.substring(1)}';

    // Uganda: 7XXXXXXXX → +2567XXXXXXXX
    if (p.length == 9 && (p.startsWith('7') || p.startsWith('3'))) {
      return '+256$p';
    }

    // Has country code without +
    if (p.length >= 10 && p.length <= 15 && !p.startsWith('0')) {
      return '+$p';
    }

    return null;
  }

  /// Returns true if the phone number is a Uganda number (+256).
  static bool isUgandaNumber(String phone) {
    final e164 = _toE164(phone);
    if (e164 == null) return false;
    return e164.startsWith('+256');
  }
}