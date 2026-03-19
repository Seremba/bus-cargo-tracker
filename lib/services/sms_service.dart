import 'package:url_launcher/url_launcher.dart';

import 'africas_talking_service.dart';
import 'at_settings_service.dart';

class SmsService {
  SmsService._();

  /// Sends an SMS via Africa's Talking if configured, otherwise falls back
  /// to opening the device SMS composer (manual send).
  ///
  /// Returns null on success, error string on failure.
  static Future<String?> sendSms({
    required String toPhone,
    required String body,
  }) async {
    if (AtSettingsService.isConfigured) {
      return AfricasTalkingService.sendSms(toPhone: toPhone, body: body);
    }
    // Fallback: open SMS composer
    final opened = await openSms(toPhone: toPhone, body: body);
    return opened ? null : 'Could not open SMS composer';
  }

  /// Opens the device SMS composer (manual send fallback).
  /// Returns true if the composer was opened successfully.
  static Future<bool> openSms({
    required String toPhone,
    required String body,
  }) async {
    final phone = toPhone.trim();
    if (phone.isEmpty) return false;

    final encoded = Uri.encodeComponent(body);
    final uri = Uri.parse('sms:$phone?body=$encoded');

    try {
      final can = await canLaunchUrl(uri);
      if (!can) return false;
      await launchUrl(uri);
      return true;
    } catch (_) {
      return false;
    }
  }
}
