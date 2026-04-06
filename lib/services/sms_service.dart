import 'africas_talking_service.dart';
import 'twilio_service.dart';

/// Smart SMS routing:
/// - Uganda numbers (+256) → Africa's Talking (cheaper, local)
/// - International numbers → Twilio (reliable global coverage)
/// - If primary fails → fallback to the other provider
class SmsService {
  SmsService._();

  static Future<String?> sendSms({
    required String toPhone,
    required String body,
  }) async {
    final isUganda = TwilioService.isUgandaNumber(toPhone);

    if (isUganda) {
      // Uganda → try AT first, fallback to Twilio
      final atError = await AfricasTalkingService.sendSms(
        toPhone: toPhone,
        body: body,
      );
      if (atError == null) return null; // AT succeeded

      // AT failed — fallback to Twilio
      // ignore: avoid_print
      print('[SmsService] AT failed for Uganda number, falling back to Twilio: $atError');
      return TwilioService.sendSms(toPhone: toPhone, body: body);
    } else {
      // International → try Twilio first, fallback to AT
      final twilioError = await TwilioService.sendSms(
        toPhone: toPhone,
        body: body,
      );
      if (twilioError == null) return null; // Twilio succeeded

      // Twilio failed — fallback to AT
      // ignore: avoid_print
      print('[SmsService] Twilio failed for international number, falling back to AT: $twilioError');
      return AfricasTalkingService.sendSms(toPhone: toPhone, body: body);
    }
  }

  /// Opens the device SMS composer as a last resort.
  static bool openSms({required String toPhone, required String body}) {
    // Not implemented — SMS composer removed in favour of API-only sending
    return false;
  }
}