import '../models/twilio_settings.dart';
import 'hive_service.dart';

class TwilioSettingsService {
  TwilioSettingsService._();

  static const String _key = 'twilio_settings';

  static TwilioSettings getOrCreate() {
    final box = HiveService.appSettingsBox();
    final existing = box.get(_key);
    if (existing is TwilioSettings) return existing;
    final defaults = TwilioSettings();
    box.put(_key, defaults);
    return defaults;
  }

  static Future<void> save(TwilioSettings settings) async {
    final box = HiveService.appSettingsBox();
    await box.put(_key, settings);
  }

  static bool isConfigured() => getOrCreate().isConfigured;
}