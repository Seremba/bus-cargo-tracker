import 'dart:convert';
import 'package:http/http.dart' as http;

import 'at_settings_service.dart';

class AfricasTalkingService {
  AfricasTalkingService._();

  static const String _sandboxUrl =
      'https://api.sandbox.africastalking.com/version1/messaging';
  static const String _productionUrl =
      'https://api.africastalking.com/version1/messaging';

  static Future<String?> sendSms({
    required String toPhone,
    required String body,
  }) async {
    final settings = AtSettingsService.getOrCreate();

    final apiKey = settings.apiKey.trim();
    final username = settings.username.trim();

    if (apiKey.isEmpty || username.isEmpty) {
      return 'Africa\'s Talking not configured. Set API key in admin settings.';
    }

    final phone = _toE164Uganda(toPhone);
    if (phone == null) {
      return 'Invalid phone number: $toPhone';
    }

    final url = settings.isSandbox ? _sandboxUrl : _productionUrl;
    final senderId = settings.senderId.trim();

    try {
      final body_ = <String, String>{
        'username': username,
        'to': phone,
        'message': body,
      };
      if (senderId.isNotEmpty) body_['from'] = senderId;

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded',
              'apiKey': apiKey,
            },
            body: body_,
          )
          .timeout(const Duration(seconds: 15));

      // Log raw response for debugging
      // ignore: avoid_print
      print('[AT SMS] status=${response.statusCode} body=${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        return 'HTTP ${response.statusCode}: ${response.body}';
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>?;
      if (json == null) return 'Empty response from Africa\'s Talking';

      final smsData = json['SMSMessageData'] as Map<String, dynamic>?;
      if (smsData == null) return 'Unexpected response: ${response.body}';

      final message = (smsData['Message'] ?? '').toString();
      final recipients = smsData['Recipients'] as List?;

      if (recipients == null || recipients.isEmpty) {
        // AT returns empty recipients when there's an auth/config issue
        return 'No recipients processed. AT message: $message';
      }

      final first = recipients.first as Map<String, dynamic>;
      final status = (first['status'] ?? '').toString().toLowerCase();
      final number = (first['number'] ?? '').toString();
      final cost = (first['cost'] ?? '').toString();

      if (status == 'success') {
        // ignore: avoid_print
        print('[AT SMS] ✅ Sent to $number cost=$cost');
        return null; // success
      }

      return 'AT rejected message to $number: status=$status message=$message';
    } catch (e) {
      return 'SMS send failed: $e';
    }
  }

  static String? _toE164Uganda(String raw) {
    var p = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.isEmpty) return null;

    if (p.startsWith('+256')) {
      // already E.164
    } else if (p.startsWith('256') && p.length >= 12) {
      p = '+$p';
    } else if (p.startsWith('0') && p.length == 10) {
      p = '+256${p.substring(1)}';
    } else if (p.length == 9 && !p.startsWith('0')) {
      p = '+256$p';
    } else {
      return null;
    }

    if (!RegExp(r'^\+256\d{9}$').hasMatch(p)) return null;
    return p;
  }
}
