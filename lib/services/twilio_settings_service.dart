import '../models/twilio_settings.dart';
import 'hive_service.dart';

/// Stores Twilio credentials as a plain Map in appSettingsBox.
/// This avoids the HiveError that occurs when storing typed HiveObjects
/// in an untyped box — same pattern used by PasswordResetService.
class TwilioSettingsService {
  TwilioSettingsService._();

  static const String _sidKey   = 'twilio_account_sid';
  static const String _tokenKey = 'twilio_auth_token';
  static const String _fromKey  = 'twilio_from';

  static TwilioSettings getOrCreate() {
    final box = HiveService.appSettingsBox();
    return TwilioSettings(
      accountSid: (box.get(_sidKey)   as String? ?? '').trim(),
      authToken:  (box.get(_tokenKey) as String? ?? '').trim(),
      from:       (box.get(_fromKey)  as String? ?? '').trim(),
    );
  }

  static Future<void> save(TwilioSettings settings) async {
    final box = HiveService.appSettingsBox();
    await box.put(_sidKey,   settings.accountSid.trim());
    await box.put(_tokenKey, settings.authToken.trim());
    await box.put(_fromKey,  settings.from.trim());
  }

  static bool isConfigured() => getOrCreate().isConfigured;
}