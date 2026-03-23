import 'package:url_launcher/url_launcher.dart';
import 'africas_talking_service.dart';
import 'at_settings_service.dart';

class SmsService {
  SmsService._();

  /// Sends an SMS via Africa's Talking if configured.
  ///
  /// Returns null on success, error string on failure.
  ///
  /// NOTE: This method no longer falls back to the device SMS composer.
  /// Automated OTP and notification SMS must go via AT only — opening a
  /// composer is inappropriate for background/automated sends and causes
  /// unexpected popups (WhatsApp, SMS app etc.) on the driver/staff device.
  ///
  /// If AT is not configured, returns an error string so the caller can
  /// keep the message queued for retry when AT is set up.
  static Future<String?> sendSms({
    required String toPhone,
    required String body,
  }) async {
    if (!AtSettingsService.isConfigured) {
      return 'AT SMS not configured — message kept queued for retry.';
    }
    return AfricasTalkingService.sendSms(toPhone: toPhone, body: body);
  }

  /// Opens the device SMS composer (for manual staff actions only —
  /// e.g. staff tapping a "Send via SMS" button explicitly).
  /// Never called automatically by the app.
  ///
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
