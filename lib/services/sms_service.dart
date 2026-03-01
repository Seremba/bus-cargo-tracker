import 'package:url_launcher/url_launcher.dart';

class SmsService {
  SmsService._();

  static Future<bool> openSms({
    required String toPhone,
    required String body,
  }) async {
    final phone = toPhone.trim();
    if (phone.isEmpty) return false;

    // sms:<phone>?body=<encoded>
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: <String, String>{
        'body': body,
      },
    );

    if (!await canLaunchUrl(uri)) return false;

    return launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }
}